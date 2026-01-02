-- A. Status distribution (headline metric)
SELECT appointment_status, COUNT(*) AS cnt
FROM dbo.appointments
GROUP BY appointment_status
ORDER BY cnt DESC;

-- B. KPI by department (utilisation + no-show + cancel)
WITH dep AS (
  SELECT
    d.department_name,
    COUNT(*) AS total,
    SUM(CASE WHEN a.appointment_status='Completed' THEN 1 ELSE 0 END) AS completed,
    SUM(CASE WHEN a.appointment_status='NoShow' THEN 1 ELSE 0 END) AS noshow,
    SUM(CASE WHEN a.appointment_status='Cancelled' THEN 1 ELSE 0 END) AS cancelled
  FROM dbo.appointments a
  JOIN dbo.appointment_slots s ON s.slot_id = a.slot_id
  JOIN dbo.departments d ON d.department_id = s.department_id
  GROUP BY d.department_name
)
SELECT
  department_name,
  total,
  completed,
  noshow,
  cancelled,
  CAST(ROUND(noshow * 100.0 / NULLIF(total,0), 2) AS DECIMAL(10,2)) AS noshow_rate_pct,
  CAST(ROUND(cancelled * 100.0 / NULLIF(total,0), 2) AS DECIMAL(10,2)) AS cancel_rate_pct
FROM dep
ORDER BY noshow_rate_pct DESC;

-- C. Reminder effectiveness (key story)
WITH base AS (
  SELECT
    a.appointment_id,
    a.appointment_status,
    CASE WHEN EXISTS (
      SELECT 1 FROM dbo.reminders r
      WHERE r.appointment_id = a.appointment_id
        AND r.delivery_status = 'Delivered'
    ) THEN 1 ELSE 0 END AS reminder_delivered
  FROM dbo.appointments a
  WHERE a.appointment_status IN ('Completed','NoShow','Cancelled')
)
SELECT
  reminder_delivered,
  COUNT(*) AS total,
  SUM(CASE WHEN appointment_status='NoShow' THEN 1 ELSE 0 END) AS noshow,
  CAST(ROUND(SUM(CASE WHEN appointment_status='NoShow' THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*),0), 2) AS DECIMAL(10,2)) AS noshow_rate_pct
FROM base
GROUP BY reminder_delivered
ORDER BY reminder_delivered DESC;

-- D. Lead time + no-show relationship (another strong story)
WITH x AS (
  SELECT
    a.appointment_status,
    DATEDIFF(DAY, a.booked_at, s.slot_start) AS lead_days
  FROM dbo.appointments a
  JOIN dbo.appointment_slots s ON s.slot_id = a.slot_id
  WHERE a.appointment_status IN ('Completed','NoShow','Cancelled')
),
b AS (
  SELECT
    appointment_status,
    CASE
      WHEN lead_days < 7  THEN '0-6 days'
      WHEN lead_days < 14 THEN '7-13 days'
      WHEN lead_days < 21 THEN '14-20 days'
      WHEN lead_days < 30 THEN '21-29 days'
      ELSE '30+ days'
    END AS lead_bucket,
    CASE
      WHEN lead_days < 7  THEN 1
      WHEN lead_days < 14 THEN 2
      WHEN lead_days < 21 THEN 3
      WHEN lead_days < 30 THEN 4
      ELSE 5
    END AS bucket_order
  FROM x
)
SELECT
  lead_bucket,
  COUNT(*) AS total,
  SUM(CASE WHEN appointment_status='NoShow' THEN 1 ELSE 0 END) AS noshow,
  CAST(
    ROUND(
      SUM(CASE WHEN appointment_status='NoShow' THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*),0),
      2
    ) AS DECIMAL(10,2)
  ) AS noshow_rate_pct
FROM b
GROUP BY lead_bucket, bucket_order
ORDER BY bucket_order;


-- E. Waiting time (clinic flow) by department
SELECT
  d.department_name,
  COUNT(*) AS samples,
  CAST(ROUND(AVG(DATEDIFF(MINUTE, a.checkin_time, a.start_time) * 1.0), 2) AS DECIMAL(10,2)) AS avg_wait_mins
FROM dbo.appointments a
JOIN dbo.appointment_slots s ON s.slot_id = a.slot_id
JOIN dbo.departments d ON d.department_id = s.department_id
WHERE a.appointment_status='Completed'
  AND a.checkin_time IS NOT NULL
  AND a.start_time IS NOT NULL
GROUP BY d.department_name
ORDER BY avg_wait_mins DESC;

