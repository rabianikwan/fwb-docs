import os
import json
from pathlib import Path
import hashlib
from dotenv import load_dotenv
load_dotenv()

#----------------- SETUP ENVIRONTMENT ------------------------
storage_folder = os.getenv("STORAGE_FOLDER")

current_directory = os.getcwd()
if current_directory.endswith("export_json"):
	parent_directory = os.path.dirname(current_directory)
else:
    parent_directory = os.path.join(current_directory, storage_folder) # type: ignore
all_data = []



raw_data_path = os.path.join(parent_directory, "raw_data")
export_dir = os.path.join(parent_directory, "skrining")
output_file = os.path.join(export_dir, "1.json")

raw_data = Path(raw_data_path)

if not raw_data.exists():
	print(f"Error: Folder '{raw_data_path}' tidak ditemukan!")
	raise SystemExit(1)
json_files = list(raw_data.glob("**/*.json"))

sensitive_keys = os.getenv("SENSITIVE_KEYS").split(",") # type: ignore

#----------------------------------------------------------
# TAHAP 1: MEMBUAT ERM DENGAN NO RM DAN NO REGISTER BARU
# Tujuan: Deidentifikasi dari erm asi
#----------------------------------------------------------

# ─────────────────────────────────────────────
# PENDEKATAN Hash Direct
# no_rm yang sama → selalu menghasilkan ID yang sama
# Tidak membutuhkan dataset lengkap
# ─────────────────────────────────────────────

def generate_patient_id_hash(no_rm: str, prefix: str = "p", digits: int = 5) -> str:
    """
    Menghasilkan ID deterministik dari no_rm menggunakan SHA-256.
    
    Args:
        no_rm  : Nomor rekam medis unik pasien
        prefix : Awalan ID (default: 'p')
        digits : Panjang angka pada ID (default: 5 → p-00123)
    
    Returns:
        str: ID unik seperti 'p-00483'
    
    Contoh:
        generate_patient_id_hash("RM-001")  → "p-04721"  (selalu sama)
        generate_patient_id_hash("RM-001")  → "p-04721"  (run ulang → tetap sama)
    """
    hash_bytes = hashlib.sha256(no_rm.strip().upper().encode()).digest()
    numeric_id = int.from_bytes(hash_bytes[:4], byteorder="big") % (10 ** digits)
    return f"{prefix}-{str(numeric_id).zfill(digits)}"


def build_rm_id_map(all_no_rm: list, prefix: str = "P", digits: int = 3) -> dict:
    def hash_key(no_rm: str) -> str:
        return hashlib.sha256(str(no_rm).strip().upper().encode()).hexdigest()
    unique_rms = sorted(set(all_no_rm), key=hash_key)  
    return {
        rm: f"{prefix}-{str(i + 1).zfill(digits)}"
        for i, rm in enumerate(unique_rms)
    }

def ambil_semua_pasien(data):
    hasil = []
    for record in data:
        no_rm = record.get(sensitive_keys[1].strip()) 
        if no_rm:
            id_pasien = generate_patient_id_hash(no_rm)
            record['id'] = id_pasien
            hasil.append(record)
    return hasil

def mapping_semua_pasien(data, filter1: list=[''], filter2: list=['']):
    
    ############ ETIK PENELITIAN ############
    hasil_prediksi = []
    rm_to_id_map = {}
    initial_id = 1
    ########################################
    semua_rm = ambil_semua_pasien(data)
    all_no_rm_list = [record['no_rm'] for record in semua_rm] 
    rm_to_id_map = build_rm_id_map(all_no_rm_list) 

    for record in data:
        erm = record.get(sensitive_keys[2].strip())
        id = f'ERM-{initial_id}'
        
        if isinstance(erm, dict):
            diagnosa = erm.get('ds', '') or ''
            diagnosa = diagnosa.lower()
            
            if not any(loc in diagnosa for loc in filter1) or not any(keyword in diagnosa for keyword in filter2):
                continue
                    
            keluhan = erm.get('cm', '') or ''
            tindakan = erm.get('tn', '') or ''
            pemeriksaan = erm.get('pm', '') or ''
            jenis_kelamin = record.get('sex') or ''
            nama = record.get(sensitive_keys[0].strip()) or ''
                
            no_rm = record.get(sensitive_keys[1].strip())
            key_id = id
                    
            id_pasien_generated = rm_to_id_map.get(no_rm)
                               
            data = ({
                        "id": key_id,
                        "pasien_id": id_pasien_generated,
                        # "no_rm": record.get("no_rm"),
                        # "nama": nama,
						"tgl_kunjungan": record.get("tgl_kunjungan"),
						"sex": jenis_kelamin,
						"umur": record.get('umur'),
						"erm": {
						"keluhan": keluhan.replace("\r\n", ", "),
						"pemeriksaan": pemeriksaan.replace("\r\n", ", "),
						"diagnosa": diagnosa.replace("\r\n", ", "),
						"tindakan": tindakan.replace("\r\n", ", "),
						}
                })

            hasil_prediksi.append(data)
            initial_id = initial_id + 1
                
    return hasil_prediksi

print('-'* 60)
print(f"Kunjungan Pasien 1 Januari 2024 s.d 31 Desember 2025")

for json_file in sorted(json_files):
	try:
		with open(json_file, 'r', encoding='utf-8') as f:
			data = json.load(f)
			if isinstance(data, list):
				all_data.extend(data)
			else:
				all_data.append(data)
	except Exception as e:
		print(e)

Path(export_dir).mkdir(parents=True, exist_ok=True)


semua_pasien = mapping_semua_pasien(all_data)

with open(output_file, 'w', encoding='utf-8') as out_f:
	json.dump(semua_pasien, out_f, ensure_ascii=False, indent=2)
 
print(f"Selesai. SEMUA KUJUNGAN: {len(semua_pasien)}")

print('*'* 60)

