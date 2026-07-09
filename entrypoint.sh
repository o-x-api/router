#!/bin/bash
set -euo pipefail

# ======================= Yapılandırma =======================
export DB_DIR="/app/data"
export REPO_ID="${HF_USER_NAME}/${HF_DATASET_NAME}"
export HF_HOME="/tmp/.cache/huggingface"

# --- 🔐 FORCE OMNIROUTE TO USE DOCKER ENV KEYS ---
export INITIAL_PASSWORD="${INITIAL_PASSWORD}"
export JWT_SECRET="${JWT_SECRET}"
export API_KEY_SECRET="${API_KEY_SECRET}"
export STORAGE_ENCRYPTION_KEY="${STORAGE_ENCRYPTION_KEY}"
# ===========================================================

echo "[$(date +'%T')] --- OmniRoute /app/data Yedekleme Başlatıldı ---"
mkdir -p "$DB_DIR"

if [[ -z "${HF_TOKEN:-}" ]]; then
    echo "[HATA] HF_TOKEN eksik!"
    exit 1
fi

# 1. Ön Kontrol: Dataset yoksa Gizli (Private) olarak oluştur
echo "[GÜVENLİK] Dataset kontrol ediliyor..."
python3 -c "
import os
from huggingface_hub import HfApi
from huggingface_hub.errors import RepositoryNotFoundError

hf_token = os.environ.get('HF_TOKEN')
repo_id = os.environ.get('REPO_ID')
api = HfApi(token=hf_token)
try:
    info = api.repo_info(repo_id=repo_id, repo_type='dataset')
    print(f'√ Dataset mevcut. Durum: {\"GİZLİ (Private)\" if info.private else \"AÇIK (Public)⚠️\"}')
except RepositoryNotFoundError:
    print('ℹ️ Dataset bulunamadı. Tamamen GİZLİ (Private) olarak yeni bir tane oluşturuluyor...')
    api.create_repo(repo_id=repo_id, repo_type='dataset', private=True)
    print('√ Yeni Gizli Dataset başarıyla oluşturuldu.')
"

# 2. Restore (Download existing database checkpoints from Hugging Face Hub)
echo "[Restore] Hub'dan dosyalar indiriliyor..."
python3 -c "
import os
from huggingface_hub import hf_hub_download
files = ['storage.sqlite', 'storage.sqlite-shm', 'storage.sqlite-wal']
repo_id = os.environ.get('REPO_ID')
db_dir = os.environ.get('DB_DIR')
hf_token = os.environ.get('HF_TOKEN')
for f in files:
    try:
        hf_hub_download(
            repo_id=repo_id,
            filename=f,
            repo_type='dataset',
            local_dir=db_dir,
            token=hf_token
        )
        print(f'√ {f} başarıyla indirildi.')
    except Exception:
        print(f'- {f} bulunamadı (İlk çalıştırma olabilir), atlanıyor.')
" || true

# 3. CommitScheduler (Live Background State Synchronization Loop)
echo "[Scheduler] Otomatik senkronizasyon arka planda başlatılıyor..."
python3 -c "
import os
import time
from huggingface_hub import CommitScheduler

repo_id = os.environ.get('REPO_ID')
db_dir = os.environ.get('DB_DIR')
hf_token = os.environ.get('HF_TOKEN')

scheduler = CommitScheduler(
    repo_id=repo_id,
    repo_type='dataset',
    folder_path=db_dir,
    allow_patterns=['*.sqlite', '*.sqlite-shm', '*.sqlite-wal'],
    every=5,
    squash_history=True,
    token=hf_token,
)
print('[Scheduler] Aktif: Her 5 dakikada bir otomatik yedekleme yapılıyor.')
while True:
    time.sleep(60)
" &

# 4. Boot OmniRoute Single-Instance Binary Runtime
echo "[System] OmniRoute başlatılıyor (/app/data)..."
node dev/run-standalone.mjs
