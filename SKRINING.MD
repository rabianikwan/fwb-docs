# Penjelas Teknis Penelitian Tugas Akhir


## 📋 Daftar Isi

> Klik tautan di bawah untuk langsung menuju bagian yang diinginkan.

| No | Topik |
|----|-------|
| 1 | [Skrining Awal](#skrining-awal) |
| 2 | [Single Inputation RF](#metodologi) |
| 3 | [Analisa Data](#hasil-dan-pembahasan) |
| 4 | [Kesimpulan](#kesimpulan) |
| 5 | [Referensi](#referensi) |

---

# Skrining Awal

>  Algoritma data mining tidak dijelaskan secara detail dan source code tidak disertakan dalam dokumen ini guna mencegah potensi eksploitasi struktur data oleh pihak yang tidak berwenang.

# Dokumentasi Teknis: Pipeline Skrining Data Kunjungan Pasien
### Tahap 1 — Deidentifikasi dan Restrukturisasi Data
### Tahap 2 — Pengelompokan Pasien, Ekstraksi Fitur, dan Skrining Awal

---

## Tahap 1: Deidentifikasi dan Restrukturisasi Data

### 1.1 Deskripsi Umum

Tahap 1 merupakan tahap awal dalam pipeline pemrosesan data. Proses yang dilakukan meliputi pembacaan data mining data dari file JSON, penyaringan berdasarkan kriteria diagnosa, deidentifikasi identitas pasien, serta restrukturisasi skema data menjadi format terstandarisasi. Output tahap ini menjadi input pada Tahap 2.

---

### 1.2 Konfigurasi Lingkungan

Konfigurasi path dan variabel sensitif dimuat dari file `.env` menggunakan `python-dotenv`.

| Variabel | Keterangan |
|---|---|
| `STORAGE_FOLDER` | Nama folder penyimpanan utama |
| `SENSITIVE_KEYS` | Daftar kunci data sensitif |

Direktori kerja ditentukan secara dinamis berdasarkan lokasi eksekusi skrip:

```
parent_directory/
├── raw_data/       ← Input: file JSON mining data
└── skrining/
    └── 1.json      ← Output Tahap 1
```

---

### 1.3 Alur Proses

```
File JSON mining data (raw_data/)
        ↓
  Baca & Gabungkan (all_data)
        ↓
  ambil_semua_pasien()  →  Generate pasien_id via SHA-256
        ↓
  build_rm_id_map()     →  Bangun mapping no_rm → P-001, P-002, ...
        ↓
  mapping_semua_pasien()
        ├── Filter diagnosa (filter1 AND filter2)
        ├── Ekstrak field klinis
        └── Restrukturisasi skema
        ↓
  Output: skrining/1.json
```

---

### 1.4 Komponen Teknis

#### 1.4.1 Pembacaan Data

Seluruh file JSON dalam direktori `raw_data/` dibaca secara iteratif dan digabungkan ke dalam satu list `all_data`.

```python
for json_file in sorted(json_files):
    with open(json_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
        if isinstance(data, list):
            all_data.extend(data)
        else:
            all_data.append(data)
```

---

#### 1.4.2 Deidentifikasi — Hash Deterministik (`generate_patient_id_hash`)

ID pasien dihasilkan dari `no_rm` menggunakan algoritma **SHA-256**. ID bersifat deterministik: input yang sama selalu menghasilkan output yang sama tanpa menyimpan pemetaan secara eksplisit.

```python
hash_bytes = hashlib.sha256(no_rm.strip().upper().encode()).digest()
numeric_id = int.from_bytes(hash_bytes[:4], byteorder="big") % (10 ** digits)
return f"{prefix}-{str(numeric_id).zfill(digits)}"
```

**Alur proses:**
1. `no_rm` dinormalisasi (strip + uppercase)
2. Di-encode ke bytes dan di-hash dengan SHA-256
3. 4 byte pertama dikonversi ke integer
4. Diambil modulo `10^digits` untuk membatasi panjang angka
5. Diformat menjadi string ID (contoh: `p-04721`)

---

#### 1.4.3 Deidentifikasi — Sequential Mapping (`build_rm_id_map`)

Menghasilkan ID sekuensial (`P-001`, `P-002`, dst.) dengan urutan deterministik berdasarkan nilai hash dari `no_rm`, bukan dari nilai aslinya.

```python
unique_rms = sorted(set(all_no_rm), key=hash_key)
return {
    rm: f"{prefix}-{str(i + 1).zfill(digits)}"
    for i, rm in enumerate(unique_rms)
}
```

---

#### 1.4.4 Penyaringan Diagnosa

Penyaringan menggunakan dua parameter `filter1` (lokasi anatomis) dan `filter2` (kata kunci klinis). Rekaman hanya diproses apabila diagnosa memenuhi **kedua** kondisi secara bersamaan.

Pencocokan kata menggunakan *word boundary* regex `\b` untuk menghindari *false match* pada substring:

```python
if not any(re.search(rf"\b{bone}\b", diagnosa, re.IGNORECASE) for bone in filter):
    continue
```

---

#### 1.4.5 Restrukturisasi Skema Output

Field sensitif dihapus dari skema utama. Output hanya menyimpan data yang diperlukan untuk analisis:

```json
{
  "id": "ERM-1",
  "pasien_id": "p-04721",
  "tgl_kunjungan": "...",
  "sex": "...",
  "umur": { "tahun": 35 },
  "erm": {
    "keluhan": "...",
    "pemeriksaan": "...",
    "diagnosa": "...",
    "tindakan": "..."
  }
}
```

Field `nama` dan `no_rm` tidak disertakan dalam output. Kunci data sensitif diakses melalui variabel lingkungan `SENSITIVE_KEYS`, bukan di-hardcode dalam skrip.

---

### 1.5 Output

| Properti | Nilai |
|---|---|
| Format | JSON (UTF-8, indent 2) |
| Lokasi | `skrining/1.json` |
| Satuan record | Per kunjungan |

---

---

## Tahap 2: Pengelompokan Pasien, Ekstraksi Fitur, dan Skrining Awal

### 2.1 Deskripsi Umum

Tahap 2 memproses output dari Tahap 1 (`skrining/1.json`) untuk mengelompokkan rekaman kunjungan berdasarkan identitas pasien, mengekstraksi fitur klinis, serta menghasilkan daftar subjek potensial yang siap untuk dilakukan audit manual.

---

### 2.2 Kriteria Populasi

| Kriteria | Nilai |
|---|---|
| Batas usia minimum | ≥ 18 tahun (`inklusi_umur = 18`) |
| Lokasi anatomis | Femur, Tibia, atau Ankle & Foot|
| Diagnosa | Mengandung kata kunci lokasi anatomis fraktur ekstremitas bawah |

---

### 2.3 Alur Proses

```
Input: skrining/1.json
        ↓
  retstruktur_kunjungan_dan_filter_umur()
        ├── Kelompokkan kunjungan per pasien_id
        ├── Filter umur (≥ 18 tahun)
        ├── [Fitur 1] Estimasi diagnosa utama (Weighted Term Frequency)
        ├── [Fitur 2] Klasifikasi lokasi anatomi
        ├── [Fitur 3] Klasifikasi protokol weight-bearing
        └── [Fitur 4] Ekstraksi umur dari nested object
        ↓
  Cetak statistik deskriptif
        ↓
  Output: skrining/2.json
```

---

### 2.4 Komponen Teknis

#### 2.4.1 Pengelompokan Kunjungan per Pasien

Rekaman dikelompokkan berdasarkan `pasien_id`. Setiap pasien memiliki satu entri dengan list `kunjungan` berisi seluruh rekaman kunjungannya.

```python
pasien_terkelompok[pasien_id] = {
    "id": pasien_id,
    "sex": ...,
    "umur": ...,
    "kunjungan": []
}
pasien_terkelompok[pasien_id]["kunjungan"].append({
    "tgl_kunjungan": ...,
    "id": ...,
    "erm": erm
})
```

---

#### 2.4.2 Fitur 1 — Estimasi Diagnosa Utama (Weighted Term Frequency)

Diagnosa utama pasien diestimasi berdasarkan seluruh diagnosa kunjungannya menggunakan skema **Modified Frequency-Based Term Weighting** yang diadaptasi pada level string diagnosa.

Kata kunci yang termasuk dalam daftar filter anatomis dikalikan dengan bobot `WEIGHT = 3`, sehingga frekuensi efektifnya lebih tinggi dalam proses seleksi.

```python
WEIGHT = 3
weighted = []
for d in diagnosa_kunjungan:
    is_filtered = any(f in d.lower() for f in filter)
    weighted.extend([d] * (WEIGHT if is_filtered else 1))

diagnosa = Counter(weighted).most_common(1)[0][0]
```

**Ilustrasi pembobotan:**

| Diagnosa | Frekuensi Asli | Masuk Filter? | Bobot Efektif |
|---|---|---|---|
| `"femur fracture"` | 2 | ✅ | 2 × 3 = **6** |
| `"back pain"` | 5 | ❌ | 5 × 1 = **5** |
| `"tibia injury"` | 1 | ✅ | 1 × 3 = **3** |

Hasil: `"femur fracture"` terpilih sebagai diagnosa utama meskipun frekuensi aslinya lebih rendah.

---

#### 2.4.3 Fitur 2 — Klasifikasi Lokasi Anatomi

Lokasi anatomi diklasifikasikan berdasarkan kata kunci yang ditemukan dalam diagnosa utama menggunakan *word boundary* regex:

```python
if not any(re.search(rf"\b{bone}\b", diagnosa, re.IGNORECASE) for bone in filter):
    continue
```

Aturan klasifikasi:

| Kondisi | Lokasi Anatomi |
|---|---|
| `femur` atau `hip` ditemukan | `Femur` |
| `tibia` ditemukan | `Tibia` |
| `ankle`, `talus`, `calcaneus`, `navicular`, `cuneiformis`, `kuboid`, atau `metatarsal` ditemukan | `Ankle` |
| Tidak ada kecocokan | Record dilewati (`continue`) |

---

#### 2.4.4 Fitur 3 — Klasifikasi Protokol Weight-Bearing

Protokol beban berdiri (*weight-bearing*) terakhir diekstraksi dari seluruh catatan tindakan kunjungan pasien berdasarkan deteksi kata kunci.

```python
nwb_search  = any("nwb"  in tindakan for tindakan in tindakan_kunjungan)
pwb_search  = any("pwb"  in tindakan for tindakan in tindakan_kunjungan)
fwb_search  = any("fwb"  in tindakan for tindakan in tindakan_kunjungan)
wbat_search = any("wbat" in tindakan for tindakan in tindakan_kunjungan)
```

Prioritas klasifikasi (dari tertinggi ke terendah):

| Prioritas | Kode | Keterangan |
|---|---|---|
| 1 | `FWB` | Full Weight Bearing |
| 2 | `PWB` | Partial Weight Bearing |
| 3 | `NWB` | Non Weight Bearing |
| 4 | `WBAT` | Weight Bearing As Tolerated |
| — | `""` | Tidak ditemukan |

---

#### 2.4.5 Fitur 4 — Ekstraksi Umur dari Nested Object

Field `umur` pada data sumber berupa nested object. Ekstraksi dilakukan dengan penanganan dua format yang mungkin:

```python
umur_dict = p_data.get("umur", {}).get("tahun", 0)
umur_tahun = umur_dict.get("tahun", 0) if isinstance(umur_dict, dict) else umur_dict
p_data["umur_tahun"] = umur_tahun
```

---

### 2.5 Statistik Deskriptif Output

Setelah pemrosesan, statistik berikut dicetak secara otomatis sebagai ringkasan awal:

| Statistik | Keterangan |
|---|---|
| Total subjek potensial | Jumlah pasien yang lolos seluruh filter |
| Jenis kelamin (L/P) | Distribusi gender |
| Lokasi anatomi | Jumlah per kategori (Femur / Tibia / Ankle) |
| Distribusi usia | Kelompok 18–44, 45–59, ≥ 60 tahun |

---

### 2.6 Output

| Properti | Nilai |
|---|---|
| Format | JSON (UTF-8, indent 2) |
| Lokasi | `skrining/2.json` |
| Satuan record | Per pasien (berisi nested list kunjungan) |

Skema output per pasien:

```json
{
  "id": "p-04721",
  "sex": "L",
  "umur": { "tahun": 45 },
  "umur_tahun": 45,
  "diagnosa": "femur fracture closed",
  "lokasi_anatomi": "Femur",
  "protokol_wb": "FWB",
  "kunjungan": [
    {
      "tgl_kunjungan": "...",
      "id": "ERM-1",
      "erm": {
        "keluhan": "...",
        "pemeriksaan": "...",
        "diagnosa": "...",
        "tindakan": "..."
      }
    }
  ]
}
```

---

### 2.7 Catatan

Data hasil Tahap 2 (`2.json`) merupakan output skrining otomatis yang **belum bersifat final**. Audit manual tetap diperlukan untuk memverifikasi kelayakan setiap subjek sebelum digunakan pada tahap analisis selanjutnya, sebagaimana ditunjukkan oleh pesan:

```
Lakukan Audit erm: [n] apakah Bisa masuk?
```

---

## Catatan Keamanan

Detail implementasi algoritma mining data, deidentifikasi, skema kunci sensitif (`SENSITIVE_KEYS`), dan logika filter diagnosa tidak dipublikasikan secara lengkap. Informasi tersebut dirahasiakan untuk meminimalisir risiko rekonstruksi data identitas pasien oleh pihak yang tidak berwenang.
