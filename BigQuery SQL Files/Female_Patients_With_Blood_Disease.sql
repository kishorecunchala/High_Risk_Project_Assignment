-- ============================================================
-- DESCRIPTION:
-- This query extracts a cohort of FEMALE ICU patients diagnosed
-- with BLOOD DISEASES (ICD-9: 280–289).
--
-- It builds a model-ready dataset including:
--   • ICU stay information
--   • Mortality label (binary)
--   • First 24-hour vital signs (heart rate)
--   • First 24-hour lab values (hemoglobin, hematocrit, glucose)
--
-- TABLES USED:
--   • diagnoses_icd   → disease identification
--   • icustays        → ICU admission details
--   • patients        → demographics (gender)
--   • admissions      → mortality (death time)
--   • chartevents     → vital signs (time-series)
--   • labevents       → laboratory measurements
-- ============================================================


-- ============================================================
-- STEP 1: Identify Blood Disease Admissions
-- ============================================================
-- Select all hospital admissions (hadm_id) where the patient
-- has an ICD-9 diagnosis code between 280–289
-- (includes anemia, coagulation disorders, etc.)
-- ============================================================

WITH blood_disease AS (
  SELECT DISTINCT hadm_id
  FROM physionet-data.mimiciii_clinical.diagnoses_icd
  WHERE icd9_code BETWEEN '280' AND '289'
),


-- ============================================================
-- STEP 2: Build ICU Cohort (Female Patients Only)
-- ============================================================
-- Join ICU stays with:
--   • patient demographics → gender filter
--   • admissions → mortality information
--   • blood_disease → diagnosis filter
--
-- Output:
--   • One row per ICU stay
--   • Mortality label (1 = died, 0 = survived)
-- ============================================================

icu_cohort AS (
  SELECT 
         icu.subject_id,        -- Unique patient identifier
         icu.hadm_id,           -- Hospital admission ID
         icu.icustay_id,        -- ICU stay ID

         pat.gender,            -- Gender (filtered later)

         icu.intime,            -- ICU admission time
         icu.outtime,           -- ICU discharge time

         adm.deathtime,         -- Time of death (if applicable)

         -- Binary mortality label
         CASE 
           WHEN adm.deathtime IS NOT NULL THEN 1 
           ELSE 0 
         END AS mortality

  FROM physionet-data.mimiciii_clinical.icustays icu

  -- Join patient demographics
  JOIN physionet-data.mimiciii_clinical.patients pat 
       ON icu.subject_id = pat.subject_id

  -- Join admission data for mortality
  JOIN physionet-data.mimiciii_clinical.admissions adm 
       ON icu.hadm_id = adm.hadm_id

  -- Filter only blood disease admissions
  JOIN blood_disease bd 
       ON icu.hadm_id = bd.hadm_id

  -- Keep only female patients
  WHERE pat.gender = 'F'
),


-- ============================================================
-- STEP 3: Extract First 24h Vital Signs (Heart Rate)
-- ============================================================
-- From chartevents:
--   • Filter measurements within first 24h of ICU stay
--   • Extract heart rate using ITEMIDs
--   • Aggregate into summary statistics
--
-- ITEMIDs:
--   • 211, 220045 → Heart Rate
--
-- Output:
--   • Mean, Min, Max heart rate per ICU stay
-- ============================================================

vitals_24h AS (
  SELECT 
         ce.icustay_id,

         -- Average heart rate in first 24h
         AVG(CASE 
               WHEN ce.itemid IN (211, 220045) 
               THEN ce.valuenum 
             END) AS heart_rate_mean,

         -- Minimum heart rate
         MIN(CASE 
               WHEN ce.itemid IN (211, 220045) 
               THEN ce.valuenum 
             END) AS heart_rate_min,

         -- Maximum heart rate
         MAX(CASE 
               WHEN ce.itemid IN (211, 220045) 
               THEN ce.valuenum 
             END) AS heart_rate_max

  FROM physionet-data.mimiciii_clinical.chartevents ce

  -- Restrict to ICU cohort
  JOIN icu_cohort icu 
       ON ce.icustay_id = icu.icustay_id

  -- Only consider first 24 hours after ICU admission
  WHERE ce.charttime BETWEEN icu.intime 
                         AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)

  GROUP BY ce.icustay_id
),


-- ============================================================
-- STEP 4: Extract First 24h Lab Values
-- ============================================================
-- From labevents:
--   • Filter labs within first 24h of ICU stay
--   • Select clinically relevant labs
--   • Aggregate using average
--
-- ITEMIDs:
--   • 50811 → Hemoglobin
--   • 50813 → Hematocrit
--   • 50809 → Glucose
--
-- Output:
--   • Average lab values per hospital admission
-- ============================================================

labs_24h AS (
  SELECT 
         le.hadm_id,

         -- Hemoglobin (oxygen-carrying capacity)
         AVG(CASE 
               WHEN le.itemid = 50811 
               THEN le.valuenum 
             END) AS hemoglobin,

         -- Hematocrit (blood volume proportion)
         AVG(CASE 
               WHEN le.itemid = 50813 
               THEN le.valuenum 
             END) AS hematocrit,

         -- Glucose (metabolic indicator)
         AVG(CASE 
               WHEN le.itemid = 50809 
               THEN le.valuenum 
             END) AS glucose

  FROM physionet-data.mimiciii_clinical.labevents le

  -- Restrict to ICU cohort
  JOIN icu_cohort icu 
       ON le.hadm_id = icu.hadm_id

  -- Only first 24 hours after ICU admission
  WHERE le.charttime BETWEEN icu.intime 
                         AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)

  GROUP BY le.hadm_id
)


-- ============================================================
-- STEP 5: Final Dataset Assembly
-- ============================================================
-- Combine:
--   • ICU cohort (demographics + mortality)
--   • Vital signs (heart rate features)
--   • Lab values
--
-- LEFT JOIN ensures:
--   • Patients without labs/vitals are still included
-- ============================================================

SELECT 
       icu.*,     -- Core cohort data
       vit.*,     -- Vital sign features
       lab.*      -- Lab features

FROM icu_cohort icu

-- Join vitals using ICU stay ID
LEFT JOIN vitals_24h vit 
       USING(icustay_id)

-- Join labs using hospital admission ID
LEFT JOIN labs_24h lab 
       USING(hadm_id);
      