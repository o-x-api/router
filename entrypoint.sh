#!/bin/bash
set -euo pipefail

# ======================= Yapılandırma =======================
export DB_DIR="/app/data"
export REPO_ID="${HF_USER_NAME}/${HF_DATASET_NAME}"
export HF_HOME="/tmp/.cache/huggingface"
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

# 2. Restore (Download existing database checkpoints and server.env from Hugging Face Hub)
echo "[Restore] Hub'dan dosyalar indiriliyor..."
python3 -c "
import os
from huggingface_hub import hf_hub_download
files = ['storage.sqlite', 'storage.sqlite-shm', 'storage.sqlite-wal', 'server.env']
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

# --- 🔐 CONFIG & ENCRYPTION KEYS SETUP ---
mkdir -p ~/.omniroute

# Ensure /app/data/server.env exists and link ~/.omniroute/server.env to it
touch /app/data/server.env
ln -sf /app/data/server.env ~/.omniroute/server.env

if [[ -n "${JWT_SECRET:-}" ]]; then
    echo "[GÜVENLİK] GitHub secrets found. Writing custom keys to /app/data/server.env..."
    cat << EOF > /app/data/server.env
JWT_SECRET="${JWT_SECRET}"
STORAGE_ENCRYPTION_KEY="${STORAGE_ENCRYPTION_KEY:-}"
API_KEY_SECRET="${API_KEY_SECRET:-}"
EOF
else
    echo "[GÜVENLİK] GitHub secrets not set. Checking persistent storage..."
    # Check if a valid JWT_SECRET exists in the persistent file
    if grep -q "JWT_SECRET=" /app/data/server.env && [[ $(grep "JWT_SECRET=" /app/data/server.env | cut -d'=' -f2) != "" ]]; then
        echo "[GÜVENLİK] Loading existing keys from /app/data/server.env..."
    else
        echo "[GÜVENLİK] Creating new keys..."
        JWT_SECRET_GEN=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
        STORAGE_ENCRYPTION_KEY_GEN=$(python3 -c "import secrets; print(secrets.token_hex(32))")
        API_KEY_SECRET_GEN=$(python3 -c "import secrets; print(secrets.token_hex(32))")
        
        cat << EOF > /app/data/server.env
JWT_SECRET="${JWT_SECRET_GEN}"
STORAGE_ENCRYPTION_KEY="${STORAGE_ENCRYPTION_KEY_GEN}"
API_KEY_SECRET="${API_KEY_SECRET_GEN}"
EOF
    fi
fi

# Load environment keys from server.env to process environment
echo "[GÜVENLİK] Sourcing /app/data/server.env..."
while IFS='=' read -r key value; do
    if [[ ! -z "$key" && ! "$key" =~ ^# ]]; then
        # remove quotes and carriage returns
        key=$(echo "$key" | tr -d '"\r' | xargs)
        value=$(echo "$value" | tr -d '"\r' | xargs)
        export "$key=$value"
    fi
done < /app/data/server.env

echo "[DEBUG] JWT_SECRET length: ${#JWT_SECRET}"
echo "[DEBUG] STORAGE_ENCRYPTION_KEY length: ${#STORAGE_ENCRYPTION_KEY}"
echo "[DEBUG] API_KEY_SECRET length: ${#API_KEY_SECRET}"

# Print MD5 and keys before startup
echo "[DEBUG] Before startup server.env MD5: $(md5sum /app/data/server.env | cut -d' ' -f1)"
echo "[DEBUG] Before startup keys:"
grep -o '^[A-Za-z0-9_]*' /app/data/server.env || true
echo "[DEBUG] Before startup JWT_SECRET MD5: $(grep '^JWT_SECRET=' /app/data/server.env | cut -d'=' -f2- | tr -d '"\r' | xargs | md5sum | cut -d' ' -f1)"
echo "[DEBUG] Before startup STORAGE_ENCRYPTION_KEY MD5: $(grep '^STORAGE_ENCRYPTION_KEY=' /app/data/server.env | cut -d'=' -f2- | tr -d '"\r' | xargs | md5sum | cut -d' ' -f1)"

# Monitor if server.env gets modified or rewritten by the server process
(
    sleep 15
    echo "[DEBUG] 15s after startup server.env MD5: $(md5sum /app/data/server.env | cut -d' ' -f1)"
    echo "[DEBUG] 15s after startup keys:"
    grep -o '^[A-Za-z0-9_]*' /app/data/server.env || true
    echo "[DEBUG] After startup JWT_SECRET MD5: $(grep '^JWT_SECRET=' /app/data/server.env | cut -d'=' -f2- | tr -d '"\r' | xargs | md5sum | cut -d' ' -f1)"
    echo "[DEBUG] After startup STORAGE_ENCRYPTION_KEY MD5: $(grep '^STORAGE_ENCRYPTION_KEY=' /app/data/server.env | cut -d'=' -f2- | tr -d '"\r' | xargs | md5sum | cut -d' ' -f1)"
    python3 -c "
with open('/app/data/server.env') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'): continue
        if '=' not in line: continue
        k, v = line.split('=', 1)
        print(f'[DEBUG] Key format check - {k}: starts_with_quote={v.startswith(\'\"\')} ends_with_quote={v.endswith(\'\"\')} len={len(v)}')
"
) &

export INITIAL_PASSWORD="${INITIAL_PASSWORD:-}"
export HOST="0.0.0.0"
export OMNIROUTE_SERVER_HOST="0.0.0.0"
export APP_LOG_TO_FILE="false"
# ===========================================================

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
    allow_patterns=['*.sqlite', '*.sqlite-shm', '*.sqlite-wal', 'server.env'],
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
