library(naniar)
library(missForest)
library(survival)
library(survminer)
library(rms)
library(gtsummary)
library(gt)
library(tibble)
library(Hmisc)
library(dplyr)
library(timeROC)
library(dcurves)

# ==============================================================================
# 1. LOAD & PERSIAPAN AWAL DATA
# ==============================================================================

data <- read.csv("data.csv")

data$Mekanisme.Trauma = as.factor(data$Mekanisme.Trauma)
data$Lokasi.Fraktur   = as.factor(data$Lokasi.Fraktur)
data$Tipe.Fiksasi     = as.factor(data$Tipe.Fiksasi)
data$Jenis.Kelamin = as.factor(data$Jenis.Kelamin)
units(data$Time)      = "Weeks"

mcar_result <- mcar_test(data)
mcar_result

# ==============================================================================
# 2. IMPUTASI MISSING DATA (missForest)
# ==============================================================================

set.seed(12091993)
copy_data             <- data
copy_data$Jenis.Kelamin <- NULL
copy_data <- missForest(
  xmis         = copy_data
)
copy_data$OOBerror


baris_data_hilang = which(is.na(data$Mekanisme.Trauma))
jumlah_data_hilang = length(baris_data_hilang)

imputed_rows <- copy_data$ximp[baris_data_hilang, ] |>
  as.data.frame() |>
  tibble::rownames_to_column("Row") |>
  mutate(
    Mekanisme.Trauma = ifelse(Mekanisme.Trauma == "1", "Energi Tinggi", "Energi Rendah"),
    Lokasi.Fraktur   = case_when(
      Lokasi.Fraktur == "0" ~ "Ankle & Foot",
      Lokasi.Fraktur == "1" ~ "Tibia-Fibula",
      Lokasi.Fraktur == "2" ~ "Femur"
    ),
    Tipe.Fiksasi = ifelse(Tipe.Fiksasi == "1", "Fiksasi Internal/Eksternal", "Fiksasi Konservatif")
  ) |>
  select(Row, Usia, Mekanisme.Trauma, Lokasi.Fraktur, Tipe.Fiksasi)


# ==============================================================================
# 3. TABEL EVALUASI MISSING DATA
# ==============================================================================

tbl_mcar <- tribble(
  ~Metric,                          ~Value,
  "Little's MCAR Test Statistic",   as.character(round(mcar_result$statistic,       2)),
  "Degrees of Freedom",             as.character(mcar_result$df),
  "p-value",                        as.character(round(mcar_result$p.value,          3)),
  "Missing Patterns",               as.character(mcar_result$missing.patterns)
)

oob_numeric <- copy_data$OOBerror[names(copy_data$OOBerror) == "MSE"]
oob_factor  <- copy_data$OOBerror[names(copy_data$OOBerror) == "PFC"]

tbl_oob <- bind_rows(
  tibble(
    Metric = paste0("NRMSE – ", names(oob_numeric)),
    Value  = as.character(round(sqrt(oob_numeric), 3))   # MSE → NRMSE
  ),
  tibble(
    Metric = paste0("PFC – ", names(oob_factor)),
    Value  = as.character(round(oob_factor, 3))
  )
)

bind_rows(
  tbl_mcar |> mutate(Section = "MCAR Test (Missing Completely at Random)"),
  tbl_oob  |> mutate(Section = "missForest OOB Imputation Error")
) |>
  gt(groupname_col = "Section") |>
  tab_header(
    title    = md("**Evaluasi & Imputasi Data Hilang**"),
    subtitle = md("Uji MCAR dan Akurasi Imputasi missForest")
  ) |>
  cols_label(
    Metric = md("**Parameter**"),
    Value  = md("**Nilai**")
  ) |>
  tab_style(
    style     = cell_text(weight = "bold"),
    locations = cells_row_groups()
  ) |>
  tab_style(
    style     = cell_fill(color = "#f2f2f2"),
    locations = cells_row_groups()
  ) |>
  tab_footnote(
    footnote  = "p > 0.05 menunjukkan data hilang bersifat MCAR (Missing Completely at Random).",
    locations = cells_body(columns = Metric, rows = Metric == "p-value")
  ) |>
  tab_footnote(
    footnote  = "PFC (Proportion of Falsely Classified) untuk variabel kategorik; NRMSE untuk variabel kontinu.",
    locations = cells_body(columns = Metric, rows = Metric == "PFC (Categorical variables)")
  ) |>
  cols_width(Metric ~ px(300), Value ~ px(150))


imputed_rows |>
  gt() |>
  tab_header(
    title    = md("**Hasil Imputasi Data Hilang**"),
    subtitle = md("Nilai Imputasi missForest terhadap *Mekanisme Trauma*")
  ) |>
  cols_label(
    Row              = md("**Baris**"),
    Usia             = md("**Usia**"),
    Mekanisme.Trauma = md("**Mekanisme Trauma**"),
    Lokasi.Fraktur   = md("**Lokasi Fraktur**"),
    Tipe.Fiksasi     = md("**Tipe Fiksasi**")
  ) |>
  tab_style(
    style     = cell_fill(color = "#fff3cd"),
    locations = cells_body(columns = Mekanisme.Trauma)
  ) |>
  tab_footnote(
    footnote  = "Kolom Mekanisme Trauma adalah variabel yang diimputasi.",
    locations = cells_column_labels(columns = Mekanisme.Trauma)
  ) |>
  cols_width(
    Row              ~ px(80),
    Usia             ~ px(80),
    Mekanisme.Trauma ~ px(180),
    Lokasi.Fraktur   ~ px(150),
    Tipe.Fiksasi     ~ px(200)
  )


# ==============================================================================
# 4. FAKTORISASI & LABELISASI SENTRAL
# ==============================================================================


data$Mekanisme.Trauma <- copy_data$ximp$Mekanisme.Trauma

data$Mekanisme.Trauma <- factor(
  x      = data$Mekanisme.Trauma,
  levels = c(0, 1),
  labels = c("Energi Rendah", "Energi Tinggi")
)

data$Lokasi.Fraktur <- factor(
  x      = data$Lokasi.Fraktur,
  levels = c(0, 1, 2),
  labels = c("Ankle&Foot", "Tibia-Fibula", "Femur")
)

data$Tipe.Fiksasi <- factor(
  x      = data$Tipe.Fiksasi,
  levels = c(0, 1),
  labels = c("Fiksasi Konservatif", "Fiksasi Internal / Eksternal")
)

data$Jenis.Kelamin <- factor(
  x      = data$Jenis.Kelamin,
  levels = c(0, 1),
  labels = c("Laki - Laki", "Perempuan")
)

label(data$Usia)             <- "Usia (tahun)"
label(data$Mekanisme.Trauma) <- "Mekanisme Trauma"
label(data$Lokasi.Fraktur)   <- "Lokasi Fraktur"
label(data$Tipe.Fiksasi)     <- "Tipe Fiksasi"

label_vars <- list(
  Usia             ~ "Usia (tahun)",
  Mekanisme.Trauma ~ "Mekanisme Trauma",
  Lokasi.Fraktur   ~ "Lokasi Fraktur",
  Tipe.Fiksasi     ~ "Tipe Fiksasi"
)

label_umum <- list(
  Usia             ~ "Usia (tahun)",
  Jenis.Kelamin    ~ "Jenis Kelamin"
)

dd <- datadist(data)
options(datadist = "dd")


# ==============================================================================
# 5. KARAKTERISTIK PASIEN
# ==============================================================================

# 5a. Karakteristik Umum
tabel_karakteristik_umum <- data |>
  select(Usia, Jenis.Kelamin) |>
  tbl_summary(label = label_umum) |>
  modify_header(label = "**Karakteristik Umum Pasien**") |>
  bold_labels()

tabel_karakteristik_umum


# 5b. Karakteristik Sesuai Tujuan Khusus
tabel_karakteristik_khusus <- data |>
  select(Usia, Mekanisme.Trauma, Tipe.Fiksasi, Lokasi.Fraktur) |>
  tbl_summary(
    label     = label_vars,
    type      = list(all_continuous() ~ "continuous"),
    statistic = list(
      all_continuous()  ~ "{mean} | {median} ({p25} - {p75}) | [{min} - {max}]",
      all_categorical() ~ "{n} ({p}%)"
    )
  ) |>
  modify_header(label = "**Variabel Independen**") |>   
  modify_caption("**Karakteristik Berdasarkan Tujuan Khusus**") |>
  bold_labels() 

tabel_karakteristik_khusus


# ==============================================================================
# 6. OBJEK SURVIVAL 
# ==============================================================================
# referensi KM, Multivariat, dan Schoenfeld : https://doi.org/10.4097/kja.19183
citation("survival")
citation("survminer")
citation("rms")
survival_object <- Surv(data$Time, data$Status)


# ==============================================================================
# 7. ANALISIS KAPLAN-MEIER PER VARIABEL
# ==============================================================================

# 7a. Mekanisme Trauma
km.mekanismetrauma     <- survfit(survival_object ~ Mekanisme.Trauma, data = data, conf.type = "log-log")
logrank.mekanismetrauma <- survdiff(survival_object ~ Mekanisme.Trauma, data = data)

tbl_survfit(
  km.mekanismetrauma,
  label        = Mekanisme.Trauma ~ "Mekanisme Trauma",
  probs        = 0.5,
  label_header = "**Median Survival (95% CI)**",
  statistic    = "{estimate} ({conf.low} - {conf.high})"
) |>
  add_n() |>
  add_nevent() |>
  add_p() |>
  modify_header(N ~ "**N**", nevent ~ "**Events**") |>
  modify_caption("**Kaplan-Meier Mekanisme Trauma**") |>
  modify_header(label = "Variabel Independen")

ggsurvplot(
  km.mekanismetrauma,
  data             = data,
  fun              = "event",
  pval             = TRUE,
  conf.int         = TRUE,
  surv.median.line = "hv",
  linetype         = "strata",
  palette          = c("black", "steelblue"),
  xlab             = "Time (Weeks)",
  legend.title     = "Mekanisme Trauma",
  legend.labs      = c("Energi Rendah", "Energi Tinggi"),
  legend           = c(.2, .8),
  break.time.by    = 4,
  risk.table       = TRUE,
  tables.height    = 0.2,
  tables.theme     = theme_classic(),
  risk.table.y.text.col = TRUE,
  risk.table.y.text     = TRUE
)


# 7b. Lokasi Fraktur
km.lokasifraktur     <- survfit(survival_object ~ Lokasi.Fraktur, data = data, conf.type = "log-log")
logrank.lokasifraktur <- survdiff(survival_object ~ Lokasi.Fraktur, data = data)

tbl_survfit(
  km.lokasifraktur,
  label        = Lokasi.Fraktur ~ "Lokasi Fraktur",
  probs        = 0.5,
  label_header = "**Median Survival (95% CI)**",
  statistic    = "{estimate} ({conf.low} - {conf.high})"
) |>
  add_n() |>
  add_nevent() |>
  add_p() |>
  modify_header(N ~ "**N**", nevent ~ "**Events**") |>
  modify_caption("**Kaplan-Meier Lokasi Fraktur**") |>
  modify_header(label = "Variabel Independen") |>
  bold_labels() 

ggsurvplot(
  km.lokasifraktur,
  data             = data,
  fun              = "event",
  pval             = TRUE,
  conf.int         = TRUE,
  surv.median.line = "hv",
  linetype         = "strata",
  palette          = c("black", "steelblue", "goldenrod3"),
  xlab             = "Time (Weeks)",
  legend.title     = "Lokasi Fraktur",
  legend.labs      = c("Foot&Ankle", "Tibia-Fibula", "Femur"),
  legend           = c(.2, .8),
  break.time.by    = 4,
  risk.table       = TRUE,
  tables.height    = 0.2,
  tables.theme     = theme_classic(),
  risk.table.y.text.col = TRUE,
  risk.table.y.text     = TRUE
)


# 7c. Tipe Fiksasi
km.tipefiksasi     <- survfit(survival_object ~ Tipe.Fiksasi, data = data, conf.type = "log-log")
logrank.tipefiksasi <- survdiff(survival_object ~ Tipe.Fiksasi, data = data)

tbl_survfit(
  km.tipefiksasi,
  label        = Tipe.Fiksasi ~ "Tipe Fiksasi",
  probs        = 0.5,
  label_header = "**Median Survival (95% CI)**",
  statistic    = "{estimate} ({conf.low} - {conf.high})"
) |>
  add_n() |>
  add_nevent() |>
  add_p() |>
  modify_header(N ~ "**N**", nevent ~ "**Events**") |>
  modify_caption("**Kaplan-Meier Tipe Fiksasi**") |>
  modify_header(label = "Variabel Independen")

ggsurvplot(
  km.tipefiksasi,
  data             = data,
  fun              = "event",
  pval             = TRUE,
  conf.int         = TRUE,
  surv.median.line = "hv",
  linetype         = "strata",
  palette          = c("black", "steelblue"),
  xlab             = "Time (Weeks)",
  legend.title     = "Tipe Fiksasi",
  legend.labs      = c("Pembidaian Eksternal", "Fiksasi Internal / Eksternal"),
  legend           = c(.2, .8),
  break.time.by    = 4,
  risk.table       = TRUE,
  tables.height    = 0.2,
  tables.theme     = theme_classic(),
  risk.table.y.text.col = TRUE,
  risk.table.y.text     = TRUE
)


# ==============================================================================
# 8. ANALISIS SURVIVAL UNIVARIAT (Overall / Waktu Pencapaian FWB)
# ==============================================================================

km.univariat <- survfit(survival_object ~ 1, data = data, conf.type = "log-log")

# Update add_ncensor dengan relocate
fill_stratum_stats <- function(tbl, km_obj) {
  surv_tbl <- summary(km_obj)$table
  labels   <- sub(".*=", "", rownames(surv_tbl))
  lookup   <- tibble(
    label       = labels,
    N_fill      = as.integer(surv_tbl[, "records"]),
    nevent_fill = as.integer(surv_tbl[, "events"])
  )
  tbl |>
    modify_table_body(~ {
      .x |>
        left_join(lookup, by = "label") |>
        mutate(
          N      = if_else(row_type == "level" & !is.na(N_fill),      N_fill,      N),
          nevent = if_else(row_type == "level" & !is.na(nevent_fill), nevent_fill, nevent)
        ) |>
        select(-N_fill, -nevent_fill)
    })
}

add_ncensor <- function(tbl) {
  tbl |>
    modify_table_body(~ .x |> 
                        mutate(ncensor = as.integer(N - nevent)) |>
                        relocate(ncensor, .before = stat_1)
    ) |>
    modify_column_unhide(ncensor) |>
    modify_header(ncensor ~ "**Censoring**")
}

# Rebuild semua tabel
tbl_overall2 <- tbl_survfit(
  km.univariat,
  probs        = 0.5,
  label_header = "**Median Survival (95% CI)**",
  statistic    = "{estimate} ({conf.low}, {conf.high})"
) |>
  add_n() |> add_nevent() |>
  modify_header(N ~ "**N**", nevent ~ "**Events**") |>
  add_ncensor()

tbl_mekanisme3 <- tbl_survfit(
  km.mekanismetrauma,
  probs        = 0.5,
  label_header = "**Median Survival (95% CI)**",
  statistic    = "{estimate} ({conf.low}, {conf.high})"
) |>
  add_n() |> add_nevent() |> add_p() |>
  modify_header(N ~ "**N**", nevent ~ "**Events**") |>
  fill_stratum_stats(km.mekanismetrauma) |>
  add_ncensor()
tbl_lokasi3 <- tbl_survfit(
  km.lokasifraktur,
  probs        = 0.5,
  label_header = "**Median Survival (95% CI)**",
  statistic    = "{estimate} ({conf.low}, {conf.high})"
) |>
  add_n() |> add_nevent() |> add_p() |>
  modify_header(N ~ "**N**", nevent ~ "**Events**") |>
  fill_stratum_stats(km.lokasifraktur) |>
  add_ncensor()

tbl_fiksasi3 <- tbl_survfit(
  km.tipefiksasi,
  probs        = 0.5,
  label_header = "**Median Survival (95% CI)**",
  statistic    = "{estimate} ({conf.low}, {conf.high})"
) |>
  add_n() |> add_nevent() |> add_p() |>
  modify_header(N ~ "**N**", nevent ~ "**Events**") |>
  fill_stratum_stats(km.tipefiksasi) |>
  add_ncensor()

tbl_stack(
  list(tbl_overall2, tbl_mekanisme3, tbl_lokasi3, tbl_fiksasi3),
  group_header = c("Waktu Pencapaian FWB", "Mekanisme Trauma", "Lokasi Fraktur", "Tipe Fiksasi")
) |>
  bold_labels() |>
  modify_header(label = "Variabel Independen / Dependen") |>
  modify_caption("**Median Survival Berdasarkan Variabel Independen / Dependen**")

ggsurvplot(
  km.univariat,
  data             = data,
  fun              = "event",
  conf.int         = TRUE,
  palette          = "steelblue",
  surv.median.line = "hv",
  break.time.by    = 4,
  censor           = TRUE,
  legend           = c(.2, .8),
  legend.title     = "Variabel Dependen",
  legend.labs      =  "Waktu Pencapaian FWB",
  xlab             = "Time (Weeks)",
  risk.table       = TRUE,
  tables.height    = 0.2,
  tables.theme     = theme_classic(),
  risk.table.y.text = FALSE
)

# ==============================================================================
# 9. COX REGRESSION MULTIVARIAT
# ==============================================================================
cox_m1 <- coxph(
  survival_object ~ Lokasi.Fraktur + Mekanisme.Trauma + Tipe.Fiksasi + Usia,
  data = data
)

uji_schoenfeld <- cox.zph(cox_m1)

uji_schoenfeld$table |>
  as.data.frame() |>
  tibble::rownames_to_column("Variable") |>
  dplyr::mutate(
    Variable = dplyr::case_when(
      Variable == "Lokasi.Fraktur"   ~ "Lokasi Fraktur",
      Variable == "Mekanisme.Trauma" ~ "Mekanisme Trauma",
      Variable == "Tipe.Fiksasi"     ~ "Tipe Fiksasi",
      Variable == "Usia"             ~ "Usia",
      Variable == "GLOBAL"           ~ "GLOBAL",
      TRUE                           ~ Variable
    ),
    p     = round(p, 3),
    chisq = round(chisq, 3)
  ) |>
  gt() |>
  cols_label(
    Variable = md("**Variable**"),
    chisq    = md("**Chi-Square**"),
    df       = md("**df**"),
    p        = md("**p-value**")
  ) |>
  tab_header(
    title    = md("**Uji Asumsi Proportional Hazards**"),
    subtitle = md("Schoenfeld Residuals")
  ) |>
  tab_style(
    style     = cell_text(weight = "bold"),
    locations = cells_body(rows = Variable == "GLOBAL")
  ) |>
  tab_footnote(
    footnote  = "p > 0.05 mengindikasikan tidak ada pelanggaran asumsi *proportional hazards*.",
    locations = cells_column_labels(columns = p)
  ) |>
  fmt_number(columns = c(chisq, p), decimals = 3)

ggcoxzph(
  uji_schoenfeld,
  point.col   = "steelblue",
  point.size  = 1.5,
  point.shape = 19,
  point.alpha = 1,
  ggtheme     = theme_bw()
)

print(cox_m1)
summary(cox_m1)
coef(cox_m1)

# --- Tabel Cox Regression ---
tabel_cox <- tbl_regression(
  cox_m1,
  label        = label_vars,
  exponentiate = TRUE,
  pvalue_fun   = ~style_pvalue(.x, digits = 3)
) |>
  bold_p() |>
  modify_header(label = "**Variabel Independen**") |>
  bold_labels() |>
  modify_caption("**Analisis Cox Regression**")

tabel_cox

ggforest(
  cox_m1,
  data       = data,
  main       = "Hazard Ratio - Pengaruh tiap Variabel Terhadap Durasi Pencapaian FWB",
  cpositions = c(0.02, 0.20, 0.38),
  ref        = "Referensi",
  fontsize   = 0.85,
  noDigits   = 2
) +
  theme(
    plot.title   = element_text(hjust = 0.5, face = "bold", size = 12),
    plot.caption = element_text(size = 8, color = "gray50")
  ) +
  labs(caption = "HR = Hazard Ratio; CI = Confidence Interval; * p<0.05, ** p<0.01, *** p<0.001")


# ==============================================================================
# 10. MODEL Cox PH (rms) — KALIBRASI, VALIDASI, DISKRIMINASI, DCA, NOMOGRAM
# ==============================================================================
citation("rms")
median <- round(summary(km.univariat)$table["median"], digits = 0)
median

model <- cph(
  survival_object ~ Lokasi.Fraktur + Mekanisme.Trauma + Tipe.Fiksasi + Usia,
  data     = data,
  x        = TRUE,
  y        = TRUE,
  surv     = TRUE,
  time.inc = median
)

print(model)


# 10a. Kalibrasi
set.seed(12091993)
kalibrasi <- calibrate(
  fit    = model,
  method = "boot",
  B      = 500,
  u      = median,
  m      = 15
)
kalibrasi

output  <- capture.output(print(kalibrasi))
output
baris   <- output[grep("Mean \\|error\\|", output)]

mean_err     <- as.numeric(sub(".*Mean \\|error\\|:(\\S+)\\s.*", "\\1", baris))
q90_err <- as.numeric(sub(".*0\\.9 Quantile of \\|error\\|:(\\S+).*", "\\1", baris))

mean_err     <- round(mae, 4)
q90_err <- round(q90_err, 4)

cat("MAE  :", mae, "\n")
cat("E90  :", q90_err, "\n")



# 10b. Validasi (Diskriminasi Global)
set.seed(12091993)
validasi <- validate(
  fit    = model,
  method = "boot",
  B      = 500,
  u      = median     
)
validasi


dxy_row     <- validasi["Dxy", ]
dxy_row
c_apparent  <- round((dxy_row["index.orig"]      + 1) / 2, 3)
c_corrected <- round((dxy_row["index.corrected"] + 1) / 2, 3)
c_lower     <- round((dxy_row["Lower"]           + 1) / 2, 3)
c_upper     <- round((dxy_row["Upper"]           + 1) / 2, 3)

# 10c. Diskriminasi (AUC-IPCW)
citation("timeROC")
lp <- predict(model, type = "lp")

tauc <- timeROC(
  T         = data$Time,
  delta     = data$Status,
  marker    = lp,
  cause     = 1,
  weighting = "marginal",
  times     = median,
  iid       = FALSE
)

auc_ipcw <- round(tauc$AUC["t=22"] * 100, 2)



# --- Plot Kalibrasi ---
plot(kalibrasi,
     xlab = "Prediksi Probabilitas Keterlambatan FWB (22 Minggu)",
     ylab = "Proporsi Observasi Keterlambatan FWB (22 Minggu)",)

legend(
  "bottomright",
  legend  = c("Apparent", "Bias-corrected", "Ideal", "95% Bootstrap CI"),
  lty     = c(1, 1, 2, 1),
  lwd     = c(2, 2, 1, 1),
  col     = c("black", "#2171B5", "black", "gray70"),
  bty     = "n",
  cex     = 0.82,
  seg.len = 1.8
)

grid(nx = NULL, ny = NULL, col = "gray88", lty = 1, lwd = 0.7)

metric_text <- c(
  paste0("AUC (t=22 weeks) = ", auc_ipcw, "%"),
  paste0("C-Statistic Apparent = ", c_apparent),
  paste0("C-Statistic Bias-Corrected = ", c_corrected)
)

legend(
  "topleft",
  legend  = metric_text,
  bty     = "o",          # kotak border
  cex     = 0.82,
  text.col = c("black", "black", "black"),   # biru untuk bias-corrected, sesuai warna garis
  bg      = "white"
)

# 10d. Decision Curve Analysis (DCA)
# Referensi: 
citation("dcurves")

sv_median           <- Survival(model)
prediksi_survival   <- survest(model, newdata = data, times = 22)$surv
data$probabilitas_prediksi <- 1 - prediksi_survival


dca_survival <- dca(
  formula    = survival_object ~ probabilitas_prediksi,
  data       = data,
  time       = 22,
  thresholds = seq(0, 0.5, by = 0.01)
)

dca(survival_object ~ probabilitas_prediksi, 
    data,
    time = median,
    thresholds = seq(0, 0.5, by = 0.01),
    label = list(probabilitas_prediksi = "Model Cox")) %>%
  plot(smooth = TRUE)

 dca_tbl <- dca_survival$dca |>
  filter(
    threshold %in% seq(0.05, 0.5, by = 0.01),
    variable  %in% c("all", "probabilitas_prediksi")
  ) |>
  select(label, threshold, net_benefit) |>
  tidyr::pivot_wider(names_from = label, values_from = net_benefit) |>
  rename(Threshold = threshold) |>
  mutate(
    Metric = paste0("Net Benefit (Threshold ", scales::percent(Threshold, accuracy = 1), ")"),
    Value  = paste0("Model: ",     round(probabilitas_prediksi, 3),
                    " | Treat All: ", round(`Treat All`, 3))
  ) |>
  select(Metric, Value)

# --- Tabel Keseluruhan ---
combined <- tribble(
  ~Section,          ~Metric,                                  ~Value,
  "Discrimination",  "AUC-IPCW (t = 22 weeks)",               paste0(auc_ipcw, "%"),
  "Discrimination",  "C-statistic (Apparent)",                 as.character(c_apparent),
  "Discrimination",  "C-statistic (Bias-Corrected, 95% CI)",   paste0(c_corrected, " (", c_lower, "–", c_upper, ")"),
  "Calibration",     "Mean Absolute Error",                    as.character(round(mean_err, 4)),
  "Calibration",     "90th Percentile Absolute Error",         as.character(round(q90_err, 4))
) |>
  bind_rows(
    dca_tbl |> mutate(Section = "Decision Curve Analysis") |> select(Section, Metric, Value)
  )

combined |>
  gt(groupname_col = "Section") |>
  tab_header(
    title    = md("**Model Performance Summary**"),
    subtitle = md("Discrimination, Calibration, and Decision Curve Analysis")
  ) |>
  cols_label(
    Metric = md("**Metric**"),
    Value  = md("**Value**")
  ) |>
  tab_style(
    style     = cell_text(weight = "bold"),
    locations = cells_row_groups()
  ) |>
  tab_style(
    style     = cell_fill(color = "#f2f2f2"),
    locations = cells_row_groups()
  ) |>
  tab_footnote(
    footnote  = "C-statistic = (Dxy + 1) / 2; bias-corrected via bootstrap (B = 500).",
    locations = cells_body(columns = Metric, rows = Metric == "C-statistic (Bias-Corrected, 95% CI)")
  ) |>
  tab_footnote(
    footnote  = "AUC estimated using IPCW at t = 22 weeks.",
    locations = cells_body(columns = Metric, rows = Metric == "AUC-IPCW (t = 22 weeks)")
  ) |>
  cols_width(Metric ~ px(320), Value ~ px(250))


# 10e. Nomogram Referensi : https://doi.org/10.21037/atm.2017.04.01
at.surv <- c(.01, .05, seq(.1, .9, by = .1), .95, .99, .999)

surv_median <- function(x) sv_median(median, lp = x)

nomogram_cox <- nomogram(
  model,
  fun      = list(surv_median),
  fun.at   = list(at.surv),
  funlabel = c(paste0("Probabilitas Keterlambatan FWB pada t = ", round(median, 1), " Minggu")),
  lp       = FALSE
)

par(
  bg     = "white",
  family = "sans",
  mar    = c(3, 1, 2, 1),
  oma    = c(0, 0, 4, 0)
)

plot(
  nomogram_cox,
  cex.axis           = 0.75,
  cex.var            = 0.92,
  lmgp               = 0.3,
  nint               = 8,
  col.grid           = c("#DDEEFF", "#F5F5F5"),
  xfrac              = 0.38,
  label.every        = 1,
  tcl                = -0.3,
  ia.space           = 0.75,
  points.label       = "Points",
  total.points.label = "Total Points"
)

mtext(
  text  = "Estimasi Probabilistik Individu Terhadap Luaran FWB Pada 22 Minggu ",
  side  = 3,
  outer = TRUE,
  line  = 1.5,
  cex   = 0.95,
  font  = 2
)

box("figure", col = "gray60", lwd = 0.8)
