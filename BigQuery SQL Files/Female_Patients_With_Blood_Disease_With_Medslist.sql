-- ============================================================
-- Female ICU patients with blood disease ICD-9 codes 280–289
-- Include BOTH survivors and non-survivors
-- Include only rows where medications were prescribed
-- Remove duplicate drug rows
-- ============================================================

WITH blood_disease_admissions AS (
  SELECT DISTINCT
      subject_id,
      hadm_id,
      icd9_code
  FROM `physionet-data.mimiciii_clinical.diagnoses_icd`
  WHERE icd9_code BETWEEN '280' AND '289'
),

female_icu_patients AS (
  SELECT DISTINCT
      icu.subject_id,
      icu.hadm_id,
      icu.icustay_id,
      pat.gender,
      adm.admittime,
      adm.dischtime,
      adm.deathtime,
      adm.hospital_expire_flag,

      -- Mortality label:
      -- 0 = survived hospital admission
      -- 1 = died during hospital admission
      CASE
        WHEN adm.hospital_expire_flag = 1 THEN 1
        ELSE 0
      END AS mortality,

      icu.intime,
      icu.outtime
  FROM `physionet-data.mimiciii_clinical.icustays` icu
  JOIN `physionet-data.mimiciii_clinical.patients` pat
      ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciii_clinical.admissions` adm
      ON icu.hadm_id = adm.hadm_id
  JOIN blood_disease_admissions bd
      ON icu.hadm_id = bd.hadm_id
  WHERE pat.gender = 'F'
),

dedup_medications AS (
  SELECT DISTINCT
      subject_id,
      hadm_id,
      LOWER(TRIM(drug)) AS drug,
      LOWER(TRIM(drug_name_generic)) AS drug_name_generic,
      route
  FROM `physionet-data.mimiciii_clinical.prescriptions`
  WHERE drug IS NOT NULL
)

SELECT DISTINCT
    fp.subject_id,
    fp.hadm_id,
    fp.icustay_id,
    fp.gender,
    fp.admittime,
    fp.dischtime,
    fp.deathtime,
    fp.hospital_expire_flag,
    fp.mortality,
    fp.intime,
    fp.outtime,

    bd.icd9_code,

    med.drug,
    med.drug_name_generic,
    med.route

FROM female_icu_patients fp

JOIN blood_disease_admissions bd
    ON fp.hadm_id = bd.hadm_id

JOIN dedup_medications med
    ON fp.hadm_id = med.hadm_id

ORDER BY
    fp.subject_id,
    fp.hadm_id,
    med.drug;