/* ============================================================
   Seed Data: Hospital Appointment Ops Analytics (SQL Server)
   Assumes tables already exist:
   departments, clinicians, patients, referral_sources, slot_types,
   appointment_slots, appointments, reminders
   ============================================================ */

SET NOCOUNT ON;

BEGIN TRY
  BEGIN TRAN;

  /* ---------------------------
     0) Clean (optional)
     --------------------------- */
  -- If you want a clean re-run, uncomment below (order matters due to FKs).
  /*
  DELETE FROM reminders;
  DELETE FROM appointments;
  DELETE FROM appointment_slots;
  DELETE FROM patients;
  DELETE FROM clinicians;
  DELETE FROM referral_sources;
  DELETE FROM slot_types;
  DELETE FROM departments;
  */

  /* ---------------------------
     1) Dimensions
     --------------------------- */

  -- Departments (unique department_name)
  IF NOT EXISTS (SELECT 1 FROM departments)
  BEGIN
    INSERT INTO departments (department_name, site_name, specialty_group)
    VALUES
      ('Cardiology',     'Main Campus', 'Medicine'),
      ('Orthopedics',    'Main Campus', 'Surgery'),
      ('Dermatology',    'Main Campus', 'Medicine'),
      ('ENT',            'Main Campus', 'Surgery'),
      ('Ophthalmology',  'East Clinic', 'Medicine'),
      ('Endocrinology',  'East Clinic', 'Medicine'),
      ('Physiotherapy',  'East Clinic', 'Rehab'),
      ('Radiology',      'Main Campus', 'Diagnostics');
  END

  -- Referral sources
  IF NOT EXISTS (SELECT 1 FROM referral_sources)
  BEGIN
    INSERT INTO referral_sources (source_name)
    VALUES ('GP'), ('ED'), ('Self'), ('Specialist'), ('Screening');
  END

  -- Slot types
  IF NOT EXISTS (SELECT 1 FROM slot_types)
  BEGIN
    INSERT INTO slot_types (slot_type_name, planned_mins)
    VALUES
      ('New', 20),
      ('FollowUp', 15),
      ('Procedure', 30),
      ('Teleconsult', 15);
  END

  -- Clinicians (40 unique names, distributed across departments)
  IF NOT EXISTS (SELECT 1 FROM clinicians)
  BEGIN
    ;WITH d AS (
      SELECT department_id, department_name,
             ROW_NUMBER() OVER (ORDER BY department_id) AS rn
      FROM departments
    ),
    n AS (
      SELECT TOP (40) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
      FROM sys.all_objects
    )
    INSERT INTO clinicians (clinician_name, department_id, role, active_flag)
    SELECT
      CONCAT('Clinician_', RIGHT(CONCAT('00', n.n), 2)) AS clinician_name,
      (SELECT department_id FROM d WHERE d.rn = ((n.n - 1) % (SELECT COUNT(*) FROM d)) + 1),
      CASE
        WHEN n.n % 10 IN (1,2) THEN 'Consultant'
        WHEN n.n % 10 IN (3,4,5,6) THEN 'Registrar'
        ELSE 'NursePractitioner'
      END AS role,
      1
    FROM n;
  END

  /* ---------------------------
     2) Patients (12,000)
     --------------------------- */
  IF NOT EXISTS (SELECT 1 FROM patients)
  BEGIN
    ;WITH n AS (
      SELECT TOP (12000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
      FROM sys.all_objects a CROSS JOIN sys.all_objects b
    )
    INSERT INTO patients (gender, birth_year, postcode_area, created_at)
    SELECT
      CASE (n.n % 4)
        WHEN 0 THEN 'F'
        WHEN 1 THEN 'M'
        WHEN 2 THEN 'U'
        ELSE 'X'
      END AS gender,
      1945 + (n.n % 65) AS birth_year,                     -- 1945..2009
      CONCAT('D', (n.n % 24) + 1) AS postcode_area,        -- D1..D24
      DATEADD(DAY, -(n.n % 365), SYSDATETIME())
    FROM n;
  END

  /* ---------------------------
     3) Generate appointment slots (180 days)
        Weekdays heavier than weekends
        Each clinician has a small number of slots per day
     --------------------------- */

  IF NOT EXISTS (SELECT 1 FROM appointment_slots)
  BEGIN
    DECLARE @startDate DATE = DATEADD(DAY, -180, CAST(GETDATE() AS DATE));
    DECLARE @endDate   DATE = CAST(GETDATE() AS DATE);

    ;WITH dates AS (
      SELECT @startDate AS d
      UNION ALL
      SELECT DATEADD(DAY, 1, d) FROM dates WHERE d < @endDate
    ),
    cl AS (
      SELECT clinician_id, department_id,
             ROW_NUMBER() OVER (ORDER BY clinician_id) AS rn
      FROM clinicians
      WHERE active_flag = 1
    ),
    st AS (
      SELECT slot_type_id, slot_type_name, planned_mins,
             ROW_NUMBER() OVER (ORDER BY slot_type_id) AS rn
      FROM slot_types
    ),
    slots AS (
      SELECT
        c.clinician_id,
        c.department_id,
        d.d AS slot_day,
        -- Create 6 slot "templates" per day (09:00 to 16:30)
        v.slot_index
      FROM dates d
      CROSS JOIN cl c
      CROSS APPLY (VALUES (1),(2),(3),(4),(5),(6)) v(slot_index)
      WHERE
        -- Reduce weekend slots significantly
        (DATEPART(WEEKDAY, d.d) IN (1,7) AND c.rn % 5 = 0)  -- small subset on weekends
        OR
        (DATEPART(WEEKDAY, d.d) NOT IN (1,7))              -- weekdays
    )
    INSERT INTO appointment_slots (clinician_id, department_id, slot_type_id, slot_start, slot_end, capacity, created_at)
    SELECT
      s.clinician_id,
      s.department_id,
      -- Slot type mix: New / FollowUp / Procedure / Teleconsult
      CASE
        WHEN (ABS(CHECKSUM(CONCAT(s.clinician_id,'|',s.slot_day,'|',s.slot_index))) % 100) < 35 THEN (SELECT slot_type_id FROM slot_types WHERE slot_type_name='FollowUp')
        WHEN (ABS(CHECKSUM(CONCAT(s.clinician_id,'|',s.slot_day,'|',s.slot_index))) % 100) < 60 THEN (SELECT slot_type_id FROM slot_types WHERE slot_type_name='New')
        WHEN (ABS(CHECKSUM(CONCAT(s.clinician_id,'|',s.slot_day,'|',s.slot_index))) % 100) < 80 THEN (SELECT slot_type_id FROM slot_types WHERE slot_type_name='Teleconsult')
        ELSE (SELECT slot_type_id FROM slot_types WHERE slot_type_name='Procedure')
      END AS slot_type_id,
      -- Slot start times
      DATEADD(MINUTE,
        CASE s.slot_index
          WHEN 1 THEN 9*60
          WHEN 2 THEN 9*60 + 30
          WHEN 3 THEN 10*60 + 30
          WHEN 4 THEN 13*60
          WHEN 5 THEN 14*60
          ELSE 15*60 + 30
        END,
        CAST(s.slot_day AS DATETIME2)
      ) AS slot_start,
      -- Slot end times (use planned mins + buffer)
      DATEADD(MINUTE,
        CASE
          WHEN (ABS(CHECKSUM(CONCAT(s.clinician_id,'|',s.slot_day,'|',s.slot_index))) % 100) < 80 THEN 30
          ELSE 45
        END,
        DATEADD(MINUTE,
          CASE s.slot_index
            WHEN 1 THEN 9*60
            WHEN 2 THEN 9*60 + 30
            WHEN 3 THEN 10*60 + 30
            WHEN 4 THEN 13*60
            WHEN 5 THEN 14*60
            ELSE 15*60 + 30
          END,
          CAST(s.slot_day AS DATETIME2)
        )
      ) AS slot_end,
      -- Capacity: higher for FollowUp/Teleconsult
      CASE
        WHEN (ABS(CHECKSUM(CONCAT(s.clinician_id,'|',s.slot_day,'|',s.slot_index))) % 100) < 35 THEN 3
        WHEN (ABS(CHECKSUM(CONCAT(s.clinician_id,'|',s.slot_day,'|',s.slot_index))) % 100) < 80 THEN 2
        ELSE 1
      END AS capacity,
      DATEADD(DAY, - (ABS(CHECKSUM(CONCAT(s.clinician_id,'|',s.slot_day))) % 30), SYSDATETIME()) AS created_at
    FROM slots s
    OPTION (MAXRECURSION 0);
  END

  /* ---------------------------
     4) Create appointments
        Respect capacity per slot
        Mix of statuses with realistic patterns
     --------------------------- */

  IF NOT EXISTS (SELECT 1 FROM appointments)
  BEGIN
    -- We will attempt to fill slots up to capacity with a probability < 1
    -- so there are under-utilised days too.
    DECLARE @minSlotId BIGINT, @maxSlotId BIGINT;
    SELECT @minSlotId = MIN(slot_id), @maxSlotId = MAX(slot_id) FROM appointment_slots;

    ;WITH s AS (
      SELECT
        slot_id, slot_start, slot_end, capacity,
        department_id
      FROM appointment_slots
    ),
    -- Create one row per potential booking position (1..capacity)
    cap AS (
      SELECT
        s.slot_id, s.slot_start, s.slot_end, s.department_id,
        v.pos
      FROM s
      CROSS APPLY (SELECT TOP (s.capacity) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS pos
                   FROM sys.all_objects) v
    ),
    -- Decide whether to actually book that capacity position
    to_book AS (
      SELECT
        c.slot_id,
        c.slot_start,
        c.department_id,
        c.pos,
        -- booking probability: ~75% weekdays, ~40% weekends
        CASE
          WHEN DATEPART(WEEKDAY, CAST(c.slot_start AS DATE)) IN (1,7) THEN 40
          ELSE 75
        END AS base_prob,
        ABS(CHECKSUM(CONCAT(c.slot_id,'|',c.pos,'|seed'))) % 100 AS r
      FROM cap c
    ),
    booked AS (
      SELECT *
      FROM to_book
      WHERE r < base_prob
    ),
    -- Assign patient and booking time, referral source, triage
    ap AS (
      SELECT
        b.slot_id,
        -- patient assignment deterministic but varied
        CAST((ABS(CHECKSUM(CONCAT(b.slot_id,'|',b.pos))) % (SELECT MAX(patient_id) FROM patients)) + 1 AS BIGINT) AS patient_id,
        -- booked_at: 1 to 60 days before slot
        DATEADD(DAY, -((ABS(CHECKSUM(CONCAT(b.slot_id,'|',b.pos,'|lead'))) % 60) + 1), b.slot_start) AS booked_at,
        -- referral source: weighted
        (SELECT TOP 1 referral_source_id
         FROM referral_sources
         ORDER BY CASE source_name
                    WHEN 'GP' THEN 1
                    WHEN 'Specialist' THEN 2
                    WHEN 'ED' THEN 3
                    WHEN 'Screening' THEN 4
                    ELSE 5
                  END,
                  ABS(CHECKSUM(CONCAT(b.slot_id,'|',b.pos,'|ref'))) % 100
        ) AS referral_source_id,
        CASE
          WHEN (ABS(CHECKSUM(CONCAT(b.slot_id,'|',b.pos,'|prio'))) % 100) < 10 THEN 'P1'
          WHEN (ABS(CHECKSUM(CONCAT(b.slot_id,'|',b.pos,'|prio'))) % 100) < 35 THEN 'P2'
          ELSE 'P3'
        END AS triage_priority,
        b.slot_start
      FROM booked b
    ),
    -- Determine reminder delivered (future bookings more likely to get reminder)
    ap2 AS (
      SELECT
        ap.*,
        DATEDIFF(DAY, ap.booked_at, ap.slot_start) AS lead_days,
        CASE
          WHEN (ABS(CHECKSUM(CONCAT(ap.slot_id,'|',ap.patient_id,'|rem'))) % 100) < 88 THEN 1
          ELSE 0
        END AS reminder_delivered_flag
      FROM ap
    ),
    -- Determine final status based on lead time, priority, reminder
    final AS (
      SELECT
        slot_id, patient_id, referral_source_id, booked_at, triage_priority, lead_days, slot_start,
        CASE
          -- cancellations: higher when lead time is high
          WHEN (ABS(CHECKSUM(CONCAT(slot_id,'|',patient_id,'|status'))) % 100) < 
               CASE WHEN lead_days >= 30 THEN 18
                    WHEN lead_days >= 14 THEN 12
                    ELSE 7
               END
            THEN 'Cancelled'

          -- no-shows: reduced if reminder delivered, higher if lead time high and low priority
          WHEN (ABS(CHECKSUM(CONCAT(slot_id,'|',patient_id,'|status2'))) % 100) <
               CASE
                 WHEN triage_priority='P1' THEN 4
                 WHEN triage_priority='P2' THEN CASE WHEN reminder_delivered_flag=1 THEN 6 ELSE 10 END
                 ELSE CASE
                        WHEN lead_days >= 21 AND reminder_delivered_flag=0 THEN 18
                        WHEN lead_days >= 21 AND reminder_delivered_flag=1 THEN 12
                        WHEN reminder_delivered_flag=0 THEN 12
                        ELSE 8
                      END
               END
            THEN 'NoShow'

          ELSE 'Completed'
        END AS appointment_status,
        reminder_delivered_flag
      FROM ap2
    )
    INSERT INTO appointments
      (slot_id, patient_id, referral_source_id, booked_at, appointment_status,
       checkin_time, start_time, end_time, cancel_time, cancel_reason, rescheduled_to_id, triage_priority)
    SELECT
      f.slot_id,
      f.patient_id,
      f.referral_source_id,
      f.booked_at,
      f.appointment_status,
      CASE WHEN f.appointment_status='Completed'
           THEN DATEADD(MINUTE, - (ABS(CHECKSUM(CONCAT(f.slot_id,'|',f.patient_id,'|chk'))) % 20 + 5), f.slot_start)
           ELSE NULL END AS checkin_time,
      CASE WHEN f.appointment_status='Completed'
           THEN DATEADD(MINUTE, (ABS(CHECKSUM(CONCAT(f.slot_id,'|',f.patient_id,'|late'))) % 25), f.slot_start)
           ELSE NULL END AS start_time,
      CASE WHEN f.appointment_status='Completed'
           THEN DATEADD(MINUTE, (ABS(CHECKSUM(CONCAT(f.slot_id,'|',f.patient_id,'|late'))) % 25)
                             + (ABS(CHECKSUM(CONCAT(f.slot_id,'|',f.patient_id,'|dur'))) % 25 + 10),
                        f.slot_start)
           ELSE NULL END AS end_time,
      CASE WHEN f.appointment_status='Cancelled'
           THEN DATEADD(DAY, (ABS(CHECKSUM(CONCAT(f.slot_id,'|',f.patient_id,'|ct'))) % 20) * -1, f.slot_start)
           ELSE NULL END AS cancel_time,
      CASE WHEN f.appointment_status='Cancelled'
           THEN CASE (ABS(CHECKSUM(CONCAT(f.slot_id,'|',f.patient_id,'|cr'))) % 5)
                  WHEN 0 THEN 'Patient unavailable'
                  WHEN 1 THEN 'Work conflict'
                  WHEN 2 THEN 'Recovered / symptoms improved'
                  WHEN 3 THEN 'Transport issue'
                  ELSE 'Other'
                END
           ELSE NULL END AS cancel_reason,
      NULL AS rescheduled_to_id,
      f.triage_priority
    FROM final f;
  END

  /* ---------------------------
     5) Reminders
     Create reminders for most appointments that were booked (including those completed/no-show/cancelled),
     with some delivery failures.
     --------------------------- */
  IF NOT EXISTS (SELECT 1 FROM reminders)
  BEGIN
    ;WITH a AS (
      SELECT
        appointment_id,
        booked_at,
        s.slot_start
      FROM appointments ap
      JOIN appointment_slots s ON s.slot_id = ap.slot_id
    ),
    r AS (
      SELECT
        a.appointment_id,
        -- choose channel
        CASE (ABS(CHECKSUM(CONCAT(a.appointment_id,'|ch'))) % 4)
          WHEN 0 THEN 'SMS'
          WHEN 1 THEN 'Email'
          WHEN 2 THEN 'WhatsApp'
          ELSE 'Voice'
        END AS channel,
        -- sent 1 to 3 days before slot (if possible)
        DATEADD(DAY, -((ABS(CHECKSUM(CONCAT(a.appointment_id,'|sd'))) % 3) + 1), a.slot_start) AS sent_at,
        CASE
          WHEN (ABS(CHECKSUM(CONCAT(a.appointment_id,'|ds'))) % 100) < 90 THEN 'Delivered'
          WHEN (ABS(CHECKSUM(CONCAT(a.appointment_id,'|ds'))) % 100) < 97 THEN 'Sent'
          ELSE 'Failed'
        END AS delivery_status
      FROM a
      WHERE DATEDIFF(DAY, a.booked_at, a.slot_start) >= 2  -- only if booked early enough
        AND (ABS(CHECKSUM(CONCAT(a.appointment_id,'|make'))) % 100) < 85 -- not everyone gets a reminder
    )
    INSERT INTO reminders (appointment_id, channel, sent_at, delivery_status)
    SELECT appointment_id, channel, sent_at, delivery_status
    FROM r;
  END

  COMMIT;
END TRY
BEGIN CATCH
  IF @@TRANCOUNT > 0 ROLLBACK;

  DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
  RAISERROR(@msg, 16, 1);
END CATCH;

-- Quick sanity counts
SELECT 'departments' AS table_name, COUNT(*) AS cnt FROM departments
UNION ALL SELECT 'clinicians', COUNT(*) FROM clinicians
UNION ALL SELECT 'patients', COUNT(*) FROM patients
UNION ALL SELECT 'appointment_slots', COUNT(*) FROM appointment_slots
UNION ALL SELECT 'appointments', COUNT(*) FROM appointments
UNION ALL SELECT 'reminders', COUNT(*) FROM reminders;
