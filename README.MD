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

# Single Inputation RF

## Cara Kerja Matematis untuk Variabel Binomial


## 1. Notasi Dasar

Misalkan dataset $\mathbf{X}$ berukuran $n \times p$, di mana:

| Simbol | Keterangan |
|--------|------------|
| $n$ | Jumlah observasi (baris) |
| $p$ | Jumlah variabel (kolom) |
| $x_{ij}$ | Nilai observasi ke-$i$ pada variabel ke-$j$ |
| $\mathcal{M}_j$ | Himpunan indeks baris yang *missing* pada variabel $j$ |
| $\mathcal{O}_j$ | Himpunan indeks baris yang terobservasi pada variabel $j$ |
| $\mathbf{x}_{i,-j}$ | Vektor baris ke-$i$ tanpa kolom $j$ (semua variabel lain sebagai prediktor) |
| $\mathcal{C}$ | Himpunan indeks variabel binomial/kategorik, $\mathcal{C} \subseteq \{1, \ldots, p\}$ |

---

## 1.1 Langkah 1 — Inisialisasi

Sebelum iterasi dimulai, semua nilai yang hilang diisi dengan nilai awal kasar. Untuk setiap variabel binomial $j \in \mathcal{C}$, nilai yang hilang diisi dengan **modus** dari nilai yang terobservasi:

$$\hat{x}_{ij}^{(0)} = \text{Mode}\left(\{x_{kj} : k \in \mathcal{O}_j\}\right) = \arg\max_{c \in \{0,1\}} \sum_{k \in \mathcal{O}_j} \mathbf{1}[x_{kj} = c], \quad \forall i \in \mathcal{M}_j$$

Matriks hasil inisialisasi yang sudah terisi penuh adalah:

$$\mathbf{X}^{(0)} = \left[x_{ij}^{(0)}\right]_{n \times p}, \quad \text{di mana} \quad x_{ij}^{(0)} = \begin{cases} x_{ij} & \text{jika } i \in \mathcal{O}_j \\ \hat{x}_{ij}^{(0)} & \text{jika } i \in \mathcal{M}_j \end{cases}$$

> **Catatan:** Untuk variabel kontinu, inisialisasi menggunakan *mean* kolom, sedangkan variabel binomial/kategorik menggunakan modus.

---

## 1.2 Langkah 2 — Pengurutan Variabel

Variabel diurutkan berdasarkan **proporsi missing** dari terkecil ke terbesar agar variabel dengan informasi paling lengkap diimputasi terlebih dahulu dan dapat dimanfaatkan sebagai prediktor yang lebih baik untuk variabel berikutnya.

Proporsi missing variabel ke-$j$:

$$\pi_j = \frac{|\mathcal{M}_j|}{n}, \quad j = 1, \ldots, p$$

Urutan imputasi $j_1, j_2, \ldots, j_p$ ditentukan sehingga:

$$\pi_{j_1} \leq \pi_{j_2} \leq \cdots \leq \pi_{j_p}$$

---

## 1.3 Langkah 3 — Konstruksi Data Latih dan Data Prediksi

Pada iterasi ke-$t$, untuk setiap variabel binomial $j$, dataset dibagi menjadi dua bagian:

**Data latih** (*training set*) — baris yang nilainya sudah terobservasi pada variabel $j$:

$$\mathcal{T}_j^{(t)} = \left\{\left(\mathbf{x}_{i,-j}^{(t)},\ x_{ij}\right) : i \in \mathcal{O}_j\right\}$$

**Data prediksi** (*test set*) — baris yang nilainya masih missing pada variabel $j$:

$$\mathcal{P}_j^{(t)} = \left\{\mathbf{x}_{i,-j}^{(t)} : i \in \mathcal{M}_j\right\}$$

> **Perhatikan** bahwa $\mathbf{x}_{i,-j}^{(t)}$ menggunakan nilai imputasi terkini dari iterasi ke-$t$, sehingga kualitas data latih terus membaik di setiap iterasi.

---

## 1.4 Langkah 4 — Membangun Random Forest Klasifikasi

Karena variabel $j$ bersifat **binomial** (nilai $\in \{0, 1\}$), Random Forest yang dibangun adalah model **klasifikasi**, bukan regresi. Random Forest terdiri dari $B$ buah pohon keputusan independen.

### 1.4.1 Bootstrap Sampling

Untuk setiap pohon $b = 1, 2, \ldots, B$, dari $|\mathcal{O}_j|$ data latih diambil sampel **dengan pengembalian** (*sampling with replacement*) sebanyak $|\mathcal{O}_j|$ observasi:

$$\mathcal{T}_j^{(t,b)} \sim \text{Bootstrap}\left(\mathcal{T}_j^{(t)}\right)$$

Probabilitas suatu observasi ke-$i$ terpilih **setidaknya sekali** dalam satu bootstrap sample:

$$P\left(i \in \mathcal{T}_j^{(t,b)}\right) = 1 - \left(1 - \frac{1}{|\mathcal{O}_j|}\right)^{|\mathcal{O}_j|} \xrightarrow{|\mathcal{O}_j| \to \infty} 1 - e^{-1} \approx 0.632$$

Observasi yang **tidak** terpilih (~36.8%) disebut *Out-of-Bag* (OOB) dan dapat digunakan untuk estimasi error internal.

### 1.4.2 Pemilihan Fitur Acak

Pada setiap node pemisahan dalam pohon ke-$b$, dipilih $m$ fitur secara **acak tanpa pengembalian** dari $p-1$ fitur yang tersedia:

$$m = \left\lfloor\sqrt{p-1}\right\rfloor \quad \text{(default untuk klasifikasi)}$$

Himpunan fitur yang terpilih untuk node ke-$q$ pada pohon ke-$b$:

$$\mathcal{F}_{b,q} \subset \{1, \ldots, p\} \setminus \{j\}, \quad |\mathcal{F}_{b,q}| = m$$

### 1.4.3 Kriteria Pemisahan Node — Gini Impurity

Misalkan node $\mathcal{N}$ berisi $n_\mathcal{N}$ observasi. Untuk variabel binomial dengan kelas $\{0, 1\}$, proporsi kelas $c$ di dalam node adalah:

$$\hat{p}_c(\mathcal{N}) = \frac{1}{n_\mathcal{N}} \sum_{i \in \mathcal{N}} \mathbf{1}[x_{ij} = c], \quad c \in \{0, 1\}$$

**Gini Impurity** node $\mathcal{N}$:

$$G(\mathcal{N}) = 1 - \sum_{c \in \{0,1\}} \hat{p}_c(\mathcal{N})^2 = 2\,\hat{p}_0(\mathcal{N})\,\hat{p}_1(\mathcal{N})$$

$G(\mathcal{N}) = 0$ berarti node murni (semua kelas sama); $G(\mathcal{N}) = 0.5$ berarti distribusi paling impure (50:50).

Untuk setiap kandidat pemisahan pada fitur $s \in \mathcal{F}_{b,q}$ dengan threshold $\tau$, node $\mathcal{N}$ dibagi menjadi:

$$\mathcal{N}_L = \{i \in \mathcal{N} : x_{is} \leq \tau\}, \quad \mathcal{N}_R = \{i \in \mathcal{N} : x_{is} > \tau\}$$

**Penurunan Gini (Gini Gain)**:

$$\Delta G(s, \tau) = G(\mathcal{N}) - \frac{|\mathcal{N}_L|}{|\mathcal{N}|}\,G(\mathcal{N}_L) - \frac{|\mathcal{N}_R|}{|\mathcal{N}|}\,G(\mathcal{N}_R)$$

Pemisahan terbaik dipilih dengan memaksimalkan Gini Gain:

$$s^*,\, \tau^* = \arg\max_{s \in \mathcal{F}_{b,q},\; \tau}\; \Delta G(s, \tau)$$

### 1.4.4 Prediksi Satu Pohon

Setiap pohon ke-$b$ menghasilkan fungsi klasifikasi:

$$\hat{f}_b^{(j,t)} : \mathbb{R}^{p-1} \to \{0, 1\}$$

Prediksi di setiap *leaf node* $\ell$ ditentukan oleh kelas mayoritas:

$$\hat{f}_b^{(j,t)}(\mathbf{x}_{i,-j}) = \arg\max_{c \in \{0,1\}} \hat{p}_c(\ell), \quad \text{di mana } \ell = \text{leaf yang dicapai oleh } \mathbf{x}_{i,-j}$$

---

## 1.5 Langkah 5 — Agregasi: Majority Vote

Untuk setiap baris $i \in \mathcal{M}_j$ yang missing, prediksi dari $B$ pohon diagregasi menggunakan **majority vote**. Pertama, hitung jumlah suara untuk setiap kelas $c$:

$$V_{ic} = \sum_{b=1}^{B} \mathbf{1}\!\left[\hat{f}_b^{(j,t)}(\mathbf{x}_{i,-j}^{(t)}) = c\right], \quad c \in \{0, 1\}$$

Nilai imputasi baru pada iterasi ke-$t$:

$$\hat{x}_{ij}^{(t)} = \arg\max_{c \in \{0,1\}} V_{ic} = \arg\max_{c \in \{0,1\}} \frac{1}{B}\sum_{b=1}^{B} \mathbf{1}\!\left[\hat{f}_b^{(j,t)}(\mathbf{x}_{i,-j}^{(t)}) = c\right]$$

Jika terjadi **seri** ($V_{i0} = V_{i1}$), resolusi dilakukan berdasarkan *prior probability* kelas dari data latih:

$$\hat{x}_{ij}^{(t)} = \arg\max_{c \in \{0,1\}} \hat{p}_c^{\text{prior}}, \quad \text{di mana } \hat{p}_c^{\text{prior}} = \frac{|\{k \in \mathcal{O}_j : x_{kj} = c\}|}{|\mathcal{O}_j|}$$

> **Kunci:** Hasil imputasi **selalu bernilai diskret** $\in \{0, 1\}$, tidak pernah menghasilkan nilai fraksional, sehingga sifat binomial variabel tetap terjaga.

---

## 1.6 Langkah 6 — Pembaruan Matriks

Setelah semua variabel $j = j_1, j_2, \ldots, j_p$ diimputasi dalam satu iterasi penuh, setiap elemen matriks diperbarui:

$$x_{ij}^{(t)} = \begin{cases} x_{ij} & \text{jika } i \in \mathcal{O}_j \quad \text{(nilai asli tidak diubah)} \\ \hat{x}_{ij}^{(t)} & \text{jika } i \in \mathcal{M}_j \quad \text{(nilai imputasi terbaru)} \end{cases}$$

Matriks lengkap hasil iterasi ke-$t$:

$$\mathbf{X}^{(t)} = \left[x_{ij}^{(t)}\right]_{n \times p}$$

---

## 1.7 Langkah 7 — Kriteria Konvergensi

Setelah setiap iterasi penuh, dihitung **proporsi perubahan** nilai imputasi pada variabel kategorik/binomial dibanding iterasi sebelumnya:

$$\gamma_{\text{cat}}^{(t)} = \frac{\displaystyle\sum_{j \in \mathcal{C}}\; \sum_{i \in \mathcal{M}_j} \mathbf{1}\!\left[\hat{x}_{ij}^{(t)} \neq \hat{x}_{ij}^{(t-1)}\right]}{\displaystyle\sum_{j \in \mathcal{C}} |\mathcal{M}_j|}$$

$\gamma_{\text{cat}}^{(t)} = 0$ berarti tidak ada nilai imputasi yang berubah (konvergensi sempurna); $\gamma_{\text{cat}}^{(t)} = 1$ berarti semua nilai berubah.

Algoritma berhenti pada iterasi $t^*$ ketika **$\gamma$ mulai meningkat**:

$$t^* = \min\left\{t : \gamma_{\text{cat}}^{(t)} > \gamma_{\text{cat}}^{(t-1)}\right\}$$

Matriks final yang digunakan sebagai output adalah matriks dari **iterasi sebelum divergensi**:

$$\mathbf{X}^{\text{final}} = \mathbf{X}^{(t^*-1)}$$

---

## 2. Ringkasan Alur Matematis

### Alur Iterasi Keseluruhan

$$\mathbf{X} \xrightarrow{\text{Inisialisasi modus}} \mathbf{X}^{(0)} \xrightarrow{t=1} \mathbf{X}^{(1)} \xrightarrow{t=2} \mathbf{X}^{(2)} \xrightarrow{\;\cdots\;} \xrightarrow{\gamma^{(t^*)} > \gamma^{(t^*-1)}} \mathbf{X}^{\text{final}} = \mathbf{X}^{(t^*-1)}$$

### Alur Per Variabel Binomial $j$ dalam Satu Iterasi

$$\underbrace{\mathcal{T}_j^{(t)}}_{\text{data latih}} \xrightarrow{\text{Bootstrap}} \underbrace{\mathcal{T}_j^{(t,b)}}_{b=1,\ldots,B} \xrightarrow{\text{Gini split}} \underbrace{\left\{\hat{f}_b^{(j,t)}\right\}_{b=1}^{B}}_{B \text{ pohon klasifikasi}} \xrightarrow{\text{Majority vote}} \underbrace{\hat{x}_{ij}^{(t)} \in \{0,1\}}_{\text{nilai imputasi baru}}$$

### Mengapa MissForest Cocok untuk Variabel Binomial

| Properti | Penjelasan |
|----------|------------|
| **Hasil selalu valid** | Majority vote menghasilkan $\{0,1\}$, tidak pernah nilai fraksional |
| **Non-parametrik** | Tidak mengasumsikan distribusi tertentu atau hubungan linear |
| **Interaksi otomatis** | Pohon keputusan menangkap interaksi kompleks antar variabel |
| **Mixed-type data** | Menangani variabel kontinu dan kategorik dalam satu kerangka |
| **Robust terhadap outlier** | Berbasis voting, bukan rata-rata numerik |

---

*Referensi: Stekhoven, D.J. & Bühlmann, P. (2012). MissForest — non-parametric missing value imputation for mixed-type data. Bioinformatics, 28(1), 112–118.*

```R
# MissForest Simple Imputation
# install.packages("missForest")
library(missForest)

# 1. Buat data simulasi
set.seed(42)
n <- 100

data <- data.frame(
  outcome = rnorm(n, mean = 80, sd = 15),                      # kontinu
  var1    = rnorm(n, mean = 50, sd = 10),                      # kontinu
  var2    = factor(sample(c(0, 1), n, replace = TRUE))         # binomial
)

# 2. Sisipkan missing HANYA pada var2
missing_idx <- sample(1:n, size = 15)
data$var2[missing_idx] <- NA

cat("Jumlah NA pada var2:", sum(is.na(data$var2)), "\n")

# 3. Imputasi MissForest
set.seed(42)
hasil <- missForest(data, maxiter = 10, ntree = 100)

# 4. Ambil data hasil imputasi
data_imputed <- hasil$ximp

cat("\nOOB Error (PFC untuk var2):\n")
print(hasil$OOBerror)

cat("\nData hasil imputasi (6 baris pertama):\n")
print(head(data_imputed))
```

# Analisa Data
# Kesimpulan
# Referensi
