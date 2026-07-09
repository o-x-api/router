#!/usr/bin/env python3
import os
import sys
import signal
import subprocess
from pathlib import Path
from huggingface_hub import HfApi, snapshot_download

# Configuration from environment variables
HF_TOKEN = os.getenv("HF_TOKEN")
HF_DATASET = os.getenv("HF_DATASET_NAME", "username/omnirout-data")
LOCAL_DATA_DIR = os.getenv("OMNIROUT_DATA_DIR", "./data")

api = HfApi(token=HF_TOKEN)

def restore_from_hf():
    """Initializes local storage with contents pulled from Hugging Face."""
    if not HF_TOKEN:
        print("[!] No HF_TOKEN provided. Skipping data restoration.")
        return
    print(f"[*] Downloading snapshot from HF Dataset: {HF_DATASET}...")
    try:
        snapshot_download(
            repo_id=HF_DATASET,
            repo_type="dataset",
            local_dir=LOCAL_DATA_DIR,
            token=HF_TOKEN
        )
        print("[+] Storage restoration complete.")
    except Exception as e:
        print(f"[!] Error restoring snapshot: {e}. Starting fresh.")

def backup_to_hf():
    """Pushes all generated runtime states back to your HF repository."""
    if not HF_TOKEN:
        print("[!] No HF_TOKEN provided. Skipping upstream persistence pass.")
        return
    print(f"[*] Committing state changes to HF Dataset: {HF_DATASET}...")
    try:
        # Force the repository to be 100% private upon creation
        api.create_repo(repo_id=HF_DATASET, repo_type="dataset", exist_ok=True, private=True)
        api.upload_folder(
            folder_path=LOCAL_DATA_DIR,
            repo_id=HF_DATASET,
            repo_type="dataset",
            commit_message="OmniRoute auto-sync snapshot save"
        )
        print("[+] System sync state successfully archived upstream.")
    except Exception as e:
        print(f"[!] Error during upstream backup synchronization pass: {e}")

def handle_shutdown(signum, frame):
    """Graceful termination handler to execute persistence sync."""
    print(f"[!] Termination signal caught ({signum}). Initializing structural dump...")
    backup_to_hf()
    sys.exit(0)

if __name__ == "__main__":
    signal.signal(signal.SIGTERM, handle_shutdown)
    signal.signal(signal.SIGINT, handle_shutdown)

    # 1. Pull dataset from Hugging Face before launching application
    restore_from_hf()

    # 2. Prepare the OmniRoute application environment locally on the runner
    app_dir = Path("./omniroute_app").resolve()
    if not app_dir.exists():
        print("[*] Cloning OmniRoute repository framework...")
        subprocess.run(["git", "clone", "https://github.com/diegosouzapw/OmniRoute.git", str(app_dir)], check=True)
        print("[*] Installing OmniRoute application dependencies (npm install)...")
        subprocess.run(["npm", "install"], cwd=str(app_dir), check=True)
        print("[*] Compiling application production assets...")
        subprocess.run(["npm", "run", "build"], cwd=str(app_dir), check=True)

    # 3. Boot the compiled production build
    print("[*] Launching OmniRoute production server...")
    process = subprocess.Popen(["npm", "start"], cwd=str(app_dir))

    # Monitor runtime execution status
    while process.poll() is None:
        try:
            process.wait(timeout=60)
        except subprocess.TimeoutExpired:
            continue

    print("[*] Main application process terminated internally.")
    backup_to_hf()
