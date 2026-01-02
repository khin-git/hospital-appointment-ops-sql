## Dataset Overview
- Departments: 8
- Clinicians: 40
- Patients: 12,000
- Appointment slots: 33,648
- Appointments: 52,261
- Reminders: 43,358

## Status Distribution
- Completed: ~40,700
- Cancelled: 7,306
- No-show: 4,198

Overall no-show rate is ~8.0%, within a realistic operational range for outpatient clinics.

## No-show and Cancellation Rates by Department
- Highest no-show rate:
  - Ophthalmology: 8.51%
  - Physiotherapy: 8.45%
  - Dermatology: 8.40%

- Lowest no-show rate:
  - Orthopedics: 7.39%
  - ENT: 7.52%

- Cancellation rates are consistently higher than no-shows across all departments
  (≈13–15%), indicating rescheduling or patient availability issues are a bigger
  operational driver than outright non-attendance.

## Reminder Effectiveness
- Appointments with delivered reminders:
  - No-show rate: 8.07%
- Appointments without delivered reminders:
  - No-show rate: 7.91%

In this dataset, reminder delivery alone does not significantly reduce no-shows,
suggesting that reminders are being sent broadly rather than targeted to
high-risk segments (e.g., long lead times or low-priority cases).

## Lead Time vs No-show Rate
- Lowest no-show rates:
  - 0–6 days: 7.16%
  - 7–13 days: 7.18%
  - 14–20 days: 6.80%

- Highest no-show rates:
  - 21–29 days: 9.12%
  - 30+ days: 8.36%

No-show rates increase materially once lead time exceeds ~21 days, indicating
that long booking delays are a key risk factor for non-attendance.

## Clinic Waiting Time
- Average waiting time across departments: ~27 minutes
- Highest average wait:
  - Radiology: 27.23 minutes
- Lowest average wait:
  - Endocrinology: 26.79 minutes

Waiting times are relatively uniform across departments, suggesting system-wide
flow constraints rather than department-specific bottlenecks.

## Recommendations
1. Prioritise reminder delivery and follow-up for appointments with lead times
   greater than 21 days, where no-show risk is highest.
2. Review scheduling capacity and slot allocation to reduce long lead times,
   especially in high-demand departments.
3. Investigate cancellation drivers separately from no-shows, as cancellations
   account for a larger share of appointment loss.
4. Implement targeted interventions (e.g., overbooking or confirmation calls)
   for departments with persistently higher no-show rates.
5. Conduct clinic flow reviews to reduce average waiting time below 25 minutes
   across all departments.