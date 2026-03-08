import os
import sys
from pathlib import Path
import json
from dotenv import load_dotenv
import re
from collections import Counter

# --------------- SETUP PATH & ENVIRONMENT ---------------
load_dotenv()
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
storage_folder = os.getenv("STORAGE_FOLDER")

current_directory = os.getcwd()
if current_directory.endswith("export_json"):
	parent_directory = os.path.dirname(current_directory)
else:
    parent_directory = os.path.join(current_directory, storage_folder) # type: ignore
all_data = []


raw_data_path = os.path.join(parent_directory, "raw_data")
export_dir = os.path.join(parent_directory, "skrining")
output_file = os.path.join(export_dir, "2.json")
import_file = os.path.join(export_dir, "1.json")

all_data = []
with open(import_file, 'r', encoding='utf-8') as f:
	data = json.load(f)
	if isinstance(data, list):
		all_data.extend(data)
inklusi_umur = 18

# ----------------------------------------------------------
# TAHAP 2: RESTRUKTURISASI DATA PASIEN BERDASARKAN KUNJUNGAN, 
# DENGAN FILTER UMUR DAN DIAGNOSA FRAKTUR EKSTREMITAS BAWAH
# Untuk Mempermudah Analisis Kita Akan Ekstrak Mengggunakan Mapping Berdasarkan Kata Kunci Diagnosa
# Penyeleksian Tetap Dilakukan MANUAL untuk memastikan akurasi, 
# namun dengan bantuan mapping ini diharapkan prosesnya lebih cepat dan konsisten
#-----------------------------------------------------------


def retstruktur_kunjungan_dan_filter_umur(data_input):
    pasien_terkelompok = {}

    for record in data_input:
        pasien_id = record.get("pasien_id")
        if not pasien_id:
            continue

        erm = record.get("erm", {})
        diagnosa = erm.get("diagnosa", "").lower()
        
        if pasien_id not in pasien_terkelompok:
            if record.get("umur", {}).get("tahun", 0) < inklusi_umur:
                continue
            pasien_terkelompok[pasien_id] = {
                "id": pasien_id,
                "nama": record.get("nama"),
                "no_rm": record.get("no_rm"),
                "sex": record.get("sex"),
                "umur": record.get("umur"),
                "kunjungan": []
            }

        pasien_terkelompok[pasien_id]["kunjungan"].append({
            "tgl_kunjungan": record.get("tgl_kunjungan"),
            "id": record.get("id"),
            "erm": erm,
        })

    daftar_final = []
    
    for p_id, p_data in pasien_terkelompok.items():
        # FITUR 1 : MEMPERKIRAKAN DIAGNOSA UTAMA BERDASARKAN FREKUENSI DIAGNOSA KUNJUNGAN
        diagnosa_kunjungan = [kunjungan.get("erm", {}).get("diagnosa", "").lower() for kunjungan in p_data["kunjungan"]]

        
        
        # FITUR 2 : MENGKATEGORIKAN LOKASI ANATOMI BERDASARKAN DIAGNOSA UTAMA
        filter = [
            "femur", 
            "femoral",
            "tibia", 
            "ankle", 
            "calcaneus", 
            "talus",
            "navicular", 
            "cuneiformis", 
            "kuboid", 
            "metatarsal", 
        ]
        
        WEIGHT = 3 

        weighted = []
        for d in diagnosa_kunjungan:
            is_filtered = any(f in d.lower() for f in filter)
            weighted.extend([d] * (WEIGHT if is_filtered else 1))

        diagnosa = Counter(weighted).most_common(1)[0][0]
        p_data["diagnosa"] = diagnosa
               
        if not any(re.search(rf"\b{bone}\b", diagnosa, re.IGNORECASE) for bone in filter):
            continue
        
        if "femur" in diagnosa:
            p_data["lokasi_anatomi"] = "Femur"
        elif "tibia" in diagnosa:
            p_data["lokasi_anatomi"] = "Tibia"
        elif "ankle" in diagnosa:
            p_data["lokasi_anatomi"] = "Ankle"
        elif "talus" in diagnosa or "cuneiformis" in diagnosa or "kuboid" in diagnosa or "metatarsal" in diagnosa or "navicular" in diagnosa or "calcaneus" in diagnosa:
            p_data["lokasi_anatomi"] = "Ankle"
        else:
            p_data["lokasi_anatomi"] = "Unknown"
        
        
        # FITUR 3 : MENGKATEGORIKAN PROTOKOL BEBAN TERAKHIR BERDASARKAN TINDAKAN KUNJUNGAN
        
        tindakan_kunjungan = [kunjungan.get("erm", {}).get("tindakan", "").lower() for kunjungan in p_data["kunjungan"]]
        nwb_search = any("nwb" in tindakan for tindakan in tindakan_kunjungan)
        pwb_search = any("pwb" in tindakan for tindakan in tindakan_kunjungan)
        fwb_search = any("fwb" in tindakan for tindakan in tindakan_kunjungan)
        wbat_search = any("wbat" in tindakan for tindakan in tindakan_kunjungan)
        
        protokol_wb = ""
        if fwb_search:
            protokol_wb = "FWB"
        elif pwb_search:
            protokol_wb = "PWB"
        elif nwb_search:
            protokol_wb = "NWB"
        elif wbat_search:
            protokol_wb = "WBAT"
                    
        
        p_data["protokol_wb"] = protokol_wb
        
        # FITUR 4 : EKSTRAK UMUR TAHUN DARI NESTED OBJECT UMUR
        umur_dict = p_data.get("umur", {}).get("tahun", 0)
        umur_tahun = umur_dict.get("tahun", 0) if isinstance(umur_dict, dict) else umur_dict
        p_data["umur_tahun"] = umur_tahun
        
        # FINALISASI SKRINING UNTUK DICEK MANUAL
        daftar_final.append(p_data)

    return daftar_final



print('-'* 60)
print(f"Kunjungan Pasien 1 Januari 2024 s.d 31 Desember 2025")
print(f"Filter Kunjungan Semua Fraktur Ekstremitas Bawah")


restruktur_kedua = retstruktur_kunjungan_dan_filter_umur(all_data)
Path(export_dir).mkdir(parents=True, exist_ok=True)
print(f'Hasil Analisis: {len(restruktur_kedua)} Pasien')
print('Selanjutnya data akan dikelompokan Berdasarkan Subjek')

statistik_kunjungan = {}

for pasien in restruktur_kedua:
    jumlah_kunjungan = len(pasien["kunjungan"])
    label = f"Subjek {jumlah_kunjungan}x kunjungan"
    
    if label not in statistik_kunjungan:
        statistik_kunjungan[label] = 0
    statistik_kunjungan[label] += 1


print("--- RINGKASAN DATA PASIEN ---")
print(f"Total Subjek Pontensial Masuk: {len(restruktur_kedua)}")

statistik = {
    "Total Male (L)": 0,
    "Total Female (P)": 0,
    "Total Ankle": 0,
    "Total Femur": 0,
    "Total Tibia": 0,
    "Umur 18-44": 0,
    "Umur 45 - 60": 0,
    "Umur >= 60": 0
}

for p in restruktur_kedua:
    # 1. Hitung Jenis Kelamin
    gender = str(p.get("sex", "")).strip().upper()
    if gender == 'L':
        statistik["Total Male (L)"] += 1
    elif gender == 'P':
        statistik["Total Female (P)"] += 1

    # 3. Hitung Lokasi Anatomi
    lokasi = p.get("lokasi_anatomi", "Unknown")
    if lokasi == "Femur":
        statistik["Total Femur"] += 1
    elif lokasi == "Tibia":
        statistik["Total Tibia"] += 1
    elif lokasi == "Ankle":
        statistik["Total Ankle"] += 1

    # 4. Hitung Distribusi Umur (Mengambil dari nested object)
    try:
        usia_obj = p.get("umur", {})
        if isinstance(usia_obj, dict):
            usia_tahun = int(usia_obj.get("tahun", 0))
        else:
            # Jaga-jaga jika ada data yang formatnya langsung integer
            usia_tahun = int(usia_obj)

        if usia_tahun < 18:
            statistik["Umur < 18"] += 1
        elif 18 <= usia_tahun <= 44:
            statistik["Umur 18-44"] += 1
        elif 45 <= usia_tahun <= 59:
            statistik["Umur 45 - 60"] += 1
        else:
            statistik["Umur >= 60"] += 1
            
    except (ValueError, TypeError, AttributeError):
        pass
for key, value in statistik.items():
    print(f"{key}: {value}")



# --- PRINT OUTPUT ---
print("\n" + "-"*30)
print("--- RINGKASAN DATA PASIEN ---")
print("-"*30)


for label, total in statistik.items():
    print(f"{label:<25} = {total}")

print("-"*30)
print(f"Lakukan Audit erm: {len(restruktur_kedua)} apakah Bisa masuk?")

with open(output_file, 'w', encoding='utf-8') as out_f:
	json.dump(restruktur_kedua, out_f, ensure_ascii=False, indent=2)
