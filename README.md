# Hospital Appointment Operations Analytics (SQL Server)

## Objective
Analyze appointment operations to improve utilisation, reduce no-shows, and shorten patient waiting time.

## Tech
- SQL Server (T-SQL)
- SSMS

## Data Model
Tables:
departments, clinicians, patients, referral_sources, slot_types,
appointment_slots, appointments, reminders

## KPI Definitions
- No-show rate (%) = NoShow / total scheduled
- Cancellation rate (%) = Cancelled / total scheduled
- Lead time (days) = slot_start - booked_at
- Waiting time (mins) = start_time - checkin_time

## What I Analyzed
1. Status distribution (Completed / NoShow / Cancelled)
2. No-show and cancellation rates by department
3. Reminder effectiveness (Delivered vs not delivered)
4. Lead time impact on no-shows
5. Average waiting time by department

## Files
- schema.sql: table definitions
- seed.sql: generates synthetic data (~52k appointments)
- queries.sql: analytics queries
- insights.md: findings and recommendations
