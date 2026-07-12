#!/bin/bash
set -euo pipefail

# Determine script directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Initializing OmniRoute GitHub Action Environment..."

# 1. Install cloudflared on runner host if not present
if ! command -v cloudflared &> /dev/null; then
    echo "📥 Downloading and installing cloudflared on runner..."
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /tmp/cloudflared
    chmod +x /tmp/cloudflared
    sudo mv /tmp/cloudflared /usr/local/bin/cloudflared
fi

# 2. Build the Docker Image
echo "⚡ Building unified OmniRoute Docker Image..."
docker build -t custom-omniroute -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"

# 3. Create persistent directories and run the container
mkdir -p "$REPO_DIR/data"

echo "🐳 Launching OmniRoute Container..."
docker rm -f omniroute-instance 2>/dev/null || true
docker run -d --name omniroute-instance \
  -p 20128:20128 \
  -v "$REPO_DIR/data:/app/data" \
  -e HF_TOKEN="$HF_TOKEN" \
  -e HF_USER_NAME="$HF_USER_NAME" \
  -e HF_DATASET_NAME="$HF_DATASET_NAME" \
  -e API_KEY_SECRET="$API_KEY_SECRET" \
  -e STORAGE_ENCRYPTION_KEY="$STORAGE_ENCRYPTION_KEY" \
  -e INITIAL_PASSWORD="$INITIAL_PASSWORD" \
  -e JWT_SECRET="$JWT_SECRET" \
  -e BASE_URL="${BASE_URL:-}" \
  -e SYNC_DELY="${SYNC_DELY:-}" \
  -e MODEL_TEST_TIMEOUT_MS="${MODEL_TEST_TIMEOUT_MS:-}" \
  custom-omniroute

# Stream the container's logs to stdout so we can see the OmniRoute boot and sync log messages in GitHub Actions
echo "🪵 Streaming container logs to stdout..."
docker logs -f omniroute-instance &
LOGS_PID=$!

# 4. Initialize Cloudflare Edge Routing
echo "🌐 Spin up edge tunnel..."
export OMNIROUTE_PORT=20128
export CF_TUNNEL_TOKEN="$CLOUDFLARE_TUNNEL_TOKEN"
python3 "$SCRIPT_DIR/tunnel.py" &
TUNNEL_PID=$!

# 5. Heartbeat loop to keep GitHub Action alive
# GitHub Actions timeouts at 6 hours (21600 seconds). Default duration: 5 hours 45 minutes (20700 seconds).
DURATION=${RUN_DURATION:-20700}
START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION))

shutdown() {
    echo ""
    echo "[$(date +'%T')] ⚠️ Shutdown signal detected! Initializing backup sequence..."
    
    # Terminate Container Log Stream
    if [ -n "${LOGS_PID:-}" ]; then
        echo "🛑 Terminating docker logs stream..."
        kill "$LOGS_PID" 2>/dev/null || true
    fi

    # Terminate Cloudflare Tunnel
    if [ -n "${TUNNEL_PID:-}" ]; then
        echo "🛑 Terminating cloudflared tunnel..."
        kill "$TUNNEL_PID" 2>/dev/null || true
    fi

    # Trigger final database backup push to Hugging Face
    echo "📦 Triggering final database sync snapshot to Hugging Face Hub..."
    docker exec \
      -e HF_TOKEN="$HF_TOKEN" \
      -e HF_USER_NAME="$HF_USER_NAME" \
      -e HF_DATASET_NAME="$HF_DATASET_NAME" \
      -i omniroute-instance python3 -c "
import os
from huggingface_hub import HfApi
try:
    api = HfApi(token=os.environ.get('HF_TOKEN'))
    repo_id = f\"{os.environ.get('HF_USER_NAME')}/{os.environ.get('HF_DATASET_NAME')}\"
    print(f'⚡ Target Repository: {repo_id}')
    api.upload_folder(
        folder_path='/app/data',
        repo_id=repo_id,
        repo_type='dataset',
        commit_message='Final Auto-Backup from GitHub Actions Runner',
        ignore_patterns=['*.sqlite-shm', '*.sqlite-wal']
    )
    print('✅ Success: Final database snapshot successfully saved to Hugging Face Hub.')
except Exception as e:
    print('❌ Error pushing final backup:', e)
" || true

    # Stop container instance
    echo "🛑 Tearing down docker container safely..."
    docker stop omniroute-instance || true
    docker rm omniroute-instance || true

    echo "🎉 Goodbye! System states successfully preserved."
    exit 0
}

# Trap signals for cleanup
trap shutdown SIGINT SIGTERM

echo "[Keep-Alive] Monitor loop started. Duration: $DURATION seconds."
while [ "$(date +%s)" -lt "$END_TIME" ]; do
    REMAINING=$((END_TIME - $(date +%s)))
    MIN_REMAINING=$((REMAINING / 60))
    echo "[Keep-Alive] OmniRoute is running. Remaining time: $MIN_REMAINING minutes..."
    sleep 300 # Print heartbeat logs every 5 minutes to prevent logs timeout
done

echo "[Keep-Alive] Runtime session elapsed."
shutdown
