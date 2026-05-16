

# Analisis Faktor Yang Berpengaruh Terhadap Waktu Pencapaian *Full Weight-Bearing* (FWB) Pasien Fraktur Ekstremitas Bawah Menggunakan *Cox Proportional Hazard* Multivariat

> **Desain** — *Retrospective Cohort Study* 
> **Metode Utama** — *Survival Analysis*

## Daftar Isi

1.  [Deskripsi Project](#1-deskripsi-proyek)
2.  [Struktur Repository](#2-struktur-repository)
3.  [Variabel Penelitian](#3-variabel-penelitian)
4.  [Alur Analisis](#4-alur-analisis)
5.  [Dependensi R](#5-dependensi-r)
6.  [Cara Menjalankan](#6-cara-menjalankan)
7.  [Output yang Dihasilkan](#7-output-yang-dihasilkan)
8.  [Referensi Metodologis](#8-referensi-metodologis)

------------------------------------------------------------------------

## 1. Deskripsi Project

Penelitian ini menganalisis **waktu pencapaian *full weight-bearing*** (FWB) sebagai *event of interest* pada pasien dewasa penderita fraktur ekstremitas bawah. Analisis survival digunakan karena sebagian pasien belum mencapai FWB pada akhir periode observasi (data tersensor). Model Cox Proportional Hazards dibangun untuk mengestimasi pengaruh simultan empat prediktor klinis terhadap kecepatan pemulihan FWB, dilengkapi nomogram sebagai alat prediksi probabilistik individual.

**Pertanyaan Penelitian:**
Apakah usia, mekanisme trauma, lokasi fraktur, dan tipe fiksasi berpengaruh terhadap waktu pencapaian FWB pada pasien fraktur ekstremitas bawah?

------------------------------------------------------------------------

## 2. Struktur Repository

```         
.
├── main.R                    # Skrip utama — seluruh pipeline analisis
└── README.md                   # Dokumentasi proyek (file ini)
```

> **Catatan privasi:** `data.csv` tidak memuat identitas langsung pasien. ID pasien di-*hash* menggunakan SHA-256 pada tahap pra-pemrosesan sebelum masuk ke pipeline ini.

------------------------------------------------------------------------

## 3. Variabel Penelitian

| Peran | Variabel | Tipe | Kode/Kategori |
|------------------|------------------|------------------|------------------|
| **Dependen** | Waktu pencapaian FWB (`Time`) | Kontinu (minggu) | — |
| **Dependen** | Status event (`Status`) | Biner | `1` = FWB tercapai, `0` = tersensor |
| **Independen** | Usia | Kontinu (tahun) | — |
| **Independen** | Mekanisme Trauma | Kategorik | `0` = Energi Rendah, `1` = Energi Tinggi |
| **Independen** | Lokasi Fraktur | Kategorik (3 level) | `0` = Ankle & Foot, `1` = Tibia-Fibula, `2` = Femur |
| **Independen** | Tipe Fiksasi | Kategorik | `0` = Fiksasi Konservatif, `1` = Fiksasi Internal/Eksternal |
| **Deskriptif** | Jenis Kelamin | Kategorik | `0` = Laki-Laki, `1` = Perempuan |

------------------------------------------------------------------------

## 4. Alur Analisis

Pipeline analisis terbagi menjadi sepuluh tahap berurutan, semuanya terdapat dalam `analysis.R`.

------------------------------------------------------------------------

### Tahap 1 — Pemuatan & Persiapan Awal Data

``` r
data <- read.csv("data.csv")
```

- Variabel kategorik dikonversi ke `factor`.
- Satuan waktu (`Time`) ditetapkan dalam **minggu** menggunakan `Hmisc::units()`.
- Uji *Missing Completely at Random* (MCAR) dilakukan via `naniar::mcar_test()` sebelum imputasi.

------------------------------------------------------------------------

### Tahap 2 — Imputasi Data Hilang (`missForest`)

Missing data pada variabel `Mekanisme.Trauma` diimputasi menggunakan **missForest** (random forest non-parametrik).

``` r
set.seed(12091993)
copy_data <- missForest(
  xmis        = copy_data
)
```

**Justifikasi metode:** - Data diasumsikan *Missing at Random* (MAR) berdasarkan p-value uji MCAR (p > 0.05 → gagal tolak H₀ MCAR, sehingga asumsi MAR valid sebagai kasus konservatif).
- Jenis Kelamin dieksklusi dari matriks imputasi karena tidak relevan sebagai prediktor imputasi `Mekanisme.Trauma`.
- Akurasi imputasi dievaluasi menggunakan **PFC** (*Proportion of Falsely Classified*) untuk variabel kategorik dan **NRMSE** untuk variabel kontinu (konversi dari MSE OOB).

------------------------------------------------------------------------

### Tahap 3 — Evaluasi Missing Data (Tabel `gt`)

Dua tabel evaluasi dihasilkan:

1.  **Tabel MCAR + OOB Error** — menampilkan statistik uji Little's MCAR, df, p-value, dan akurasi imputasi (PFC/NRMSE) dalam format `gt`.
2.  **Tabel Hasil Imputasi** — menampilkan baris-baris yang diimputasi dengan highlight kolom `Mekanisme.Trauma`.

------------------------------------------------------------------------

### Tahap 4 — Faktorisasi & Labelisasi Sentral

Seluruh variabel kategorik diberi level dan label definitif di satu titik, menghindari inkonsistensi lintas tahap:

``` r
data$Lokasi.Fraktur <- factor(data$Lokasi.Fraktur,
  levels = c(0, 1, 2),
  labels = c("Ankle&Foot", "Tibia-Fibula", "Femur"))
```

Objek `datadist` (`rms`) diinisialisasi di akhir tahap ini sehingga berlaku global untuk seluruh model `rms`.

------------------------------------------------------------------------

### Tahap 5 — Karakteristik Pasien

Dua tabel karakteristik dihasilkan menggunakan `gtsummary::tbl_summary()`:

| Tabel | Variabel | Keterangan |
|------------------------|------------------------|------------------------|
| Karakteristik Umum | Usia, Jenis Kelamin | Deskriptif demografi |
| Karakteristik Khusus | Usia, Mekanisme Trauma, Tipe Fiksasi, Lokasi Fraktur dan Waktu Pencapaian FWB | Sesuai variabel penelitian |

Statistik kontinu: mean | median (IQR) | [min–max]. Statistik kategorik: n (%).

------------------------------------------------------------------------

### Tahap 6 — Pembentukan Objek Survival

``` r
survival_object <- Surv(data$Time, data$Status)
```

Objek `Surv` menjadi respons untuk seluruh model KM dan Cox di tahap berikutnya.

------------------------------------------------------------------------

### Tahap 7 — Analisis Kaplan-Meier per Variabel

Untuk setiap variabel independen kategorik (Mekanisme Trauma, Lokasi Fraktur, Tipe Fiksasi):

1.  **`survfit()`** — estimasi KM dengan `conf.type = "log-log"` (lebih stabil untuk CI di ekor distribusi).
2.  **`survdiff()`** — uji log-rank antar strata.
3.  **`tbl_survfit()`** — tabel median survival dengan 95% CI.
4.  **`ggsurvplot()`** — kurva KM kumulatif (`fun = "event"`), lengkap dengan risk table, median line, dan p-value log-rank.

Kurva menggunakan `fun = "event"` (bukan default `fun = "surv"`) untuk menampilkan *cumulative incidence function* pencapaian FWB, lebih intuitif untuk luaran klinis positif.

------------------------------------------------------------------------

### Tahap 8 — Analisis Survival Univariat (Overall)

Kurva KM keseluruhan (`~ 1`) dihitung untuk mendapatkan **median survival global** (digunakan sebagai landmark time *t* pada kalibrasi, DCA, dan nomogram).

Tabel ringkasan disusun menggunakan `tbl_stack()` yang menggabungkan: - Overall FWB - Per strata Mekanisme Trauma, Lokasi Fraktur, Tipe Fiksasi

Kolom **Censoring** ditambahkan secara custom via `add_ncensor()` (N − Events).

------------------------------------------------------------------------

### Tahap 9 — Cox Regression Multivariat

``` r
cox_m1 <- coxph(
  survival_object ~ Lokasi.Fraktur + Mekanisme.Trauma + Tipe.Fiksasi + Usia,
  data = data
)
```

**Uji asumsi Proportional Hazards:**

``` r
uji_schoenfeld <- cox.zph(cox_m1)
```

- Schoenfeld residuals diperiksa per variabel dan secara global.
- p > 0.05 pada semua variabel → asumsi PH terpenuhi.
- Plot `ggcoxzph()` ditampilkan untuk inspeksi visual tren residual terhadap waktu.

**Output:** - Tabel HR + 95% CI + p-value via `tbl_regression(exponentiate = TRUE)`.
- Forest plot via `ggforest()`.

------------------------------------------------------------------------

### Tahap 10 — Model `rms`: Kalibrasi, Validasi, Diskriminasi, DCA, Nomogram

Model dibangun ulang menggunakan `rms::cph()` untuk mengakses fungsi validasi dan kalibrasi internal `rms`.

``` r
model <- cph(
  survival_object ~ Lokasi.Fraktur + Mekanisme.Trauma + Tipe.Fiksasi + Usia,
  data = data, x = TRUE, y = TRUE, surv = TRUE, time.inc = median
)
```

#### 10a. Kalibrasi

``` r
kalibrasi <- calibrate(model, method = "boot", B = 500, u = median, m = 15)
```

Plot kalibrasi menampilkan tiga kurva: - **Apparent** — sebelum koreksi bias - **Bias-corrected** — setelah bootstrap 500 iterasi - **Ideal** — garis diagonal sempurna

Metrik ringkasan: Mean Absolute Error dan 90th Percentile Absolute Error.

#### 10b. Validasi Internal (Diskriminasi Global)

``` r
validasi <- validate(model, method = "boot", B = 500)
```

**C-statistic** diekstrak dari Somers' Dxy:

```         
C = (Dxy + 1) / 2
```

Dilaporkan: C apparent, C bias-corrected, dan 95% bootstrap CI.

#### 10c. Diskriminasi Berbasis Waktu (AUC-IPCW)

``` r
tauc <- timeROC(T = data$Time, delta = data$Status,
                marker = lp, cause = 1,
                weighting = "marginal", times = median, iid = FALSE)
```

AUC-IPCW (*Inverse Probability of Censoring Weighting*) pada *t* = median survival memberikan estimasi diskriminasi yang mengakomodasi sensoring.

#### 10d. Decision Curve Analysis (DCA)

``` r
dca(survival_object ~ probabilitas_prediksi, data, time = median,
    thresholds = seq(0, 0.5, by = 0.01))
```

DCA membandingkan net benefit model Cox terhadap strategi "treat all" dan "treat none" pada berbagai threshold keputusan klinis (0–50%).

#### 10e. Nomogram

``` r
nomogram_cox <- nomogram(model,
  fun      = list(surv_median),
  fun.at   = list(at.surv),
  funlabel = c("Probabilitas Keterlambatan FWB pada t = [median] Minggu"),
  lp       = FALSE)
```

Nomogram menerjemahkan skor prediktif model Cox menjadi **probabilitas individual** keterlambatan FWB pada waktu *t* = median survival. Digunakan sebagai alat bantu pendukung keputusan klinis.

------------------------------------------------------------------------

## 5. Dependensi R

``` r
# Instalasi semua dependensi
install.packages(c(
  "naniar",
  "missForest",
  "survival",
  "survminer",
  "rms",
  "gtsummary",
  "gt",
  "tibble",
  "Hmisc",
  "dplyr",
  "timeROC",
  "dcurves",
  "tidyr",
  "scales"
))
```

| Paket | Fungsi Utama dalam Pipeline |
|------------------------------------|------------------------------------|
| `naniar` | Uji MCAR (`mcar_test`) |
| `missForest` | Imputasi random forest |
| `survival` | Objek `Surv`, `coxph`, `survfit`, `survdiff` |
| `survminer` | Visualisasi KM (`ggsurvplot`, `ggforest`, `ggcoxzph`) |
| `rms` | `cph`, `calibrate`, `validate`, `nomogram`, `datadist` |
| `gtsummary` | Tabel ringkasan klinis (`tbl_summary`, `tbl_regression`, `tbl_survfit`) |
| `gt` | Tabel custom dengan formatting |
| `Hmisc` | Label variabel, `Surv` support |
| `timeROC` | AUC-IPCW berbasis waktu |
| `dcurves` | Decision curve analysis |
| `dplyr` / `tidyr` / `tibble` | Transoformasi / Labeling data |

------------------------------------------------------------------------

## 6. Cara Menjalankan

``` bash
# 1. Clone repository
git clone https://github.com/rabianikwan/fwb-docs.git
cd fwb-docs
```

``` r
# 2. Buka R atau RStudio, pastikan working directory sudah benar
setwd("path/to/fwb-docs")

# 3. Instalasi semua dependensi
install.packages(c(
  "naniar",
  "missForest",
  "survival",
  "survminer",
  "rms",
  "gtsummary",
  "gt",
  "tibble",
  "Hmisc",
  "dplyr",
  "timeROC",
  "dcurves",
  "tidyr",
  "scales"
))

# 4. Jalankan pipeline utama
source("Source.R")
```

> **Catatan:** `set.seed(12091993)` ditetapkan sebelum imputasi dan sebelum validasi bootstrap untuk memastikan reprodusibilitas hasil.

------------------------------------------------------------------------

## 7. Output yang Dihasilkan

| #  | Output                                               | Tahap |
|-----|------------------------------------------------------|-------|
| 1   | Tabel MCAR + OOB Error (`gt`)                        | 3     |
| 2   | Tabel hasil imputasi baris-baris missing (`gt`)      | 3     |
| 3   | Tabel karakteristik umum & khusus (`gtsummary`)      | 5     |
| 4   | Tabel median survival per variabel (KM) + log-rank p | 7–8   |
| 5   | Kurva KM per variabel (`ggsurvplot`)                 | 7     |
| 6   | Kurva KM overall dengan risk table                   | 8     |
| 7   | Tabel uji Schoenfeld (`gt`)                          | 9     |
| 8   | Plot Schoenfeld residuals (`ggcoxzph`)               | 9     |
| 9   | Tabel Cox regression (HR, 95% CI, p)                 | 9     |
| 10  | Forest plot HR (`ggforest`)                          | 9     |
| 11  | Plot kalibrasi bootstrap-corrected                   | 10a   |
| 12  | C-statistic apparent & bias-corrected                | 10b   |
| 13  | AUC-time dependent (IPCW) pada t = median            | 10c   |
| 14  | Plot DCA (model vs treat-all vs treat-none)          | 10d   |
| 15  | Nomogram visualisasi probabilitas individual FWB     | 10e   |
| 16  | Tabel Model Performance Summary (`gt`)               | 10    |

## 8. Referensi Metodologis

### **KM Curves, Cox PH Regression & Schoenfeld Residuals:** 

- Kim J, et al. (2019). *Korean J Anesthesiol*, 72(4), 296–306. <https://doi.org/10.4097/kja.19183>
- Schober, P., & Vetter, T. R. (2018). Survival Analysis and Interpretation of Time-to-Event Data: The Tortoise and the Hare. Anesthesia & Analgesia, 127(3), 792–798. <https://doi.org/10.1213/ANE.0000000000003653>

### *Internal Validation*

- Collins, G. S., Dhiman, P., Ma, J., Schlussel, M. M., Archer, L., van Calster, B., Harrell, F. E., Martin, G. P., Moons, K. G. M., van Smeden, M., Sperrin, M., Bullock, G. S., & Riley, R. D. (2024). Evaluation of clinical prediction models (part 1): from development to external validation. BMJ. <https://doi.org/10.1136/bmj-2023-074819> - **Reduksi bias via EPV (Events Per Variable):**
- Vittinghoff, E., & McCulloch, C. E. (2007). Relaxing the Rule of Ten Events per Variable in Logistic and Cox Regression. American Journal of Epidemiology, 165(6), 710–718. <https://doi.org/10.1093/aje/kwk052> - Ogundimu, E. O., Altman, D. G., & Collins, G. S. (2016). Adequate sample size for developing prediction models is not simply related to events per variable. Journal of Clinical Epidemiology, 76, 175–182. <https://doi.org/10.1016/j.jclinepi.2016.02.031>

### **Kausal inference dalam studi observasional:** 

- Hernán, M. A. (2018). The C-Word: Scientific Euphemisms Do Not Improve Causal Inference From Observational Data. American Journal of Public Health, 108(5), 616–619. <https://doi.org/10.2105/AJPH.2018.304337>
- Olarte Parra, C., Bertizzolo, L., Schroter, S., Dechartres, A., & Goetghebeur, E. (2021). Consistency of causal claims in observational studies: a review of papers published in a general medical journal. BMJ Open, 11(5), e043339. <https://doi.org/10.1136/bmjopen-2020-043339>

### **Decision Curve Analysis:**

- Vickers, A. J., & Holland, F. (2021). Decision curve analysis to evaluate the clinical benefit of prediction models. Spine Journal, 21(10), 1643–1648. <https://doi.org/10.1016/j.spinee.2021.02.024>
- Vickers, A. J., & Elkin, E. B. (2006). Decision curve analysis: A novel method for evaluating prediction models. Medical Decision Making, 26(6), 565–574. <https://doi.org/10.1177/0272989X06295361>
- Sjoberg, D. D. (2021). dcurves: Decision Curve Analysis for Model Evaluation. Dalam CRAN: Contributed Packages. <https://doi.org/10.32614/CRAN.package.dcurves>

### **timeROC (AUC-IPCW):**

- Blanche, P. (2012). timeROC: Time-Dependent ROC Curve and AUC for Censored Survival Data. <https://doi.org/10.32614/CRAN.package.timeROC>

### **missForest:**

- Stekhoven, D. J., & Bühlmann, P. (2012). Missforest-Non-parametric missing value imputation for mixed-type data. Bioinformatics, 28(1), 112–118. <https://doi.org/10.1093/bioinformatics/btr597>

### **Little's MCAR Test:**

- Little, R. J. (2026). Missing Data Analysis. Annual Review of Clinical Psychology Annu. Rev. Clin. Psychol. 2024, 31, 57. <https://doi.org/10.1146/annurev-clinpsy-080822>

### **Nomogram Cox PH:** 

- Zhang, Z., & Kattan, M. W. (2017). Drawing Nomograms with R: Applications to categorical outcome and survival data. Annals of Translational Medicine, 5(10). <https://doi.org/10.21037/atm.2017.04.01>
- Wan G, et al. (2017). *Ann Transl Med*, 5(8), 168. <https://doi.org/10.21037/atm.2017.04.01>

------------------------------------------------------------------------

<details>

<summary><strong>Catatan Teknis Tambahan</strong></summary>

- `conf.type = "log-log"` pada `survfit()` dipilih karena menghasilkan CI yang lebih stabil secara statistik di ekor distribusi dibanding default `"plain"` atau `"log"`.
- *cumulative incidence function* (`fun = "event"`) digunakan pada semua kurva KM karena luaran penelitian adalah *waktu hingga event positif* (FWB tercapai), sehingga pembaca lebih mudah membaca probabilitas kumulatif event daripada probabilitas survival.
- Threshold DCA dibatasi 0–0.5 (bukan 0–1) karena pada threshold > 0.5, strategi "treat none" secara konsisten mendominasi secara klinis, sehingga rentang tersebut tidak relevan untuk pengambilan keputusan.
- Landmark time *t* untuk kalibrasi, DCA, dan nomogram ditetapkan pada **median survival** yang diperoleh dari `km.univariat`, bukan dari nilai arbitrer, untuk memastikan prediksi dilakukan pada titik waktu yang paling informatif secara klinik.

</details>

------------------------------------------------------------------------

*Dibuat untuk keperluan lampiran penelitian.*
