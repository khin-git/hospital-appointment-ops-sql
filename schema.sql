-- ==========================================
-- Hospital Appointment Ops Analytics (SQL Server)
-- ==========================================

-- DIMENSIONS
CREATE TABLE departments (
  department_id     INT IDENTITY(1,1) PRIMARY KEY,
  department_name   NVARCHAR(100) NOT NULL UNIQUE,
  site_name         NVARCHAR(100) NOT NULL,
  specialty_group   NVARCHAR(100) NOT NULL
);

CREATE TABLE clinicians (
  clinician_id      INT IDENTITY(1,1) PRIMARY KEY,
  clinician_name    NVARCHAR(100) NOT NULL,
  department_id     INT NOT NULL,
  role              NVARCHAR(50) NOT NULL,
  active_flag       BIT NOT NULL DEFAULT 1,
  CONSTRAINT fk_clinician_department
    FOREIGN KEY (department_id) REFERENCES departments(department_id)
);

CREATE TABLE patients (
  patient_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
  gender            CHAR(1) CHECK (gender IN ('F','M','X','U')) DEFAULT 'U',
  birth_year        INT CHECK (birth_year BETWEEN 1900 AND YEAR(GETDATE())),
  postcode_area     NVARCHAR(20),
  created_at        DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE referral_sources (
  referral_source_id INT IDENTITY(1,1) PRIMARY KEY,
  source_name        NVARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE slot_types (
  slot_type_id     INT IDENTITY(1,1) PRIMARY KEY,
  slot_type_name   NVARCHAR(50) NOT NULL UNIQUE,
  planned_mins     INT NOT NULL CHECK (planned_mins > 0)
);

-- FACTS
CREATE TABLE appointment_slots (
  slot_id          BIGINT IDENTITY(1,1) PRIMARY KEY,
  clinician_id     INT NOT NULL,
  department_id    INT NOT NULL,
  slot_type_id     INT NOT NULL,
  slot_start       DATETIME2 NOT NULL,
  slot_end         DATETIME2 NOT NULL,
  capacity         INT NOT NULL CHECK (capacity >= 1),
  created_at       DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

  CONSTRAINT fk_slot_clinician FOREIGN KEY (clinician_id)
    REFERENCES clinicians(clinician_id),
  CONSTRAINT fk_slot_department FOREIGN KEY (department_id)
    REFERENCES departments(department_id),
  CONSTRAINT fk_slot_type FOREIGN KEY (slot_type_id)
    REFERENCES slot_types(slot_type_id)
);

CREATE TABLE appointments (
  appointment_id       BIGINT IDENTITY(1,1) PRIMARY KEY,
  slot_id              BIGINT NOT NULL,
  patient_id           BIGINT NOT NULL,
  referral_source_id   INT NULL,
  booked_at            DATETIME2 NOT NULL,
  appointment_status   NVARCHAR(20) NOT NULL,

  checkin_time         DATETIME2 NULL,
  start_time           DATETIME2 NULL,
  end_time             DATETIME2 NULL,

  cancel_time          DATETIME2 NULL,
  cancel_reason        NVARCHAR(200) NULL,
  rescheduled_to_id    BIGINT NULL,

  triage_priority      CHAR(2) CHECK (triage_priority IN ('P1','P2','P3')) DEFAULT 'P3',

  CONSTRAINT fk_appt_slot FOREIGN KEY (slot_id)
    REFERENCES appointment_slots(slot_id),
  CONSTRAINT fk_appt_patient FOREIGN KEY (patient_id)
    REFERENCES patients(patient_id),
  CONSTRAINT fk_appt_referral FOREIGN KEY (referral_source_id)
    REFERENCES referral_sources(referral_source_id)
);

CREATE TABLE reminders (
  reminder_id       BIGINT IDENTITY(1,1) PRIMARY KEY,
  appointment_id    BIGINT NOT NULL,
  channel           NVARCHAR(20) NOT NULL,
  sent_at           DATETIME2 NOT NULL,
  delivery_status   NVARCHAR(20) NOT NULL,

  CONSTRAINT fk_reminder_appt FOREIGN KEY (appointment_id)
    REFERENCES appointments(appointment_id)
);
