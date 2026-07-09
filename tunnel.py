#!/usr/bin/env python3
import os
import sys
import time
import subprocess
import threading
import signal

# Configuration
LOCAL_PORT = os.environ.get("OMNIROUTE_PORT", "20128")
TUNNEL_TOKEN = os.environ.get("CF_TUNNEL_TOKEN", os.environ.get("CLOUDFLARE_TUNNEL_TOKEN", "")).strip()

STOP_EVENT = threading.Event()
PROCESS = None

def log(message: str):
    print(f"[Tunnel] {message}", flush=True)

def run_tunnel():
    global PROCESS
    
    # Check if a specific Tunnel Token is provided for a managed Cloudflare tunnel
    if TUNNEL_TOKEN:
        log("Found Cloudflare Tunnel Token. Initializing managed tunnel...")
        cmd = ["cloudflared", "--no-autoupdate", "tunnel", "run", "--token", TUNNEL_TOKEN]
    else:
        log(f"No tunnel token found. Creating a temporary quick tunnel for port {LOCAL_PORT}...")
        cmd = ["cloudflared", "tunnel", "--url", f"http://localhost:{LOCAL_PORT}"]

    try:
        # Start the cloudflared process
        PROCESS = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )
        
        # Read the logs in real-time to look for the generated URL if using a quick tunnel
        for line in iter(PROCESS.stdout.readline, ""):
            if STOP_EVENT.is_set():
                break
            
            cleaned_line = line.strip()
            # Catch the ephemeral URL printout from Cloudflare
            if "trycloudflare.com" in cleaned_line:
                log(f"🎉 Your OmniRoute URL is live: {cleaned_line.split()[-1]}")
            elif "Error" in cleaned_line or "error" in cleaned_line.lower():
                log(f"⚠️ {cleaned_line}")
                
        PROCESS.stdout.close()
    except Exception as e:
        log(f"❌ Failed to run cloudflared process: {e}")

def handle_signal(_sig, _frame):
    log("Shutdown signal received. Stopping tunnel...")
    STOP_EVENT.set()
    if PROCESS:
        PROCESS.terminate()
    sys.exit(0)

def main():
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)
    
    # Quick sanity check to ensure cloudflared is installed on the host OS
    try:
        subprocess.run(["cloudflared", "--version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        log("❌ 'cloudflared' CLI binary is not installed or not in PATH.")
        log("Install it via: curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared")
        return 1

    # Spin up the tunnel daemon in a dedicated thread
    tunnel_thread = threading.Thread(target=run_tunnel, daemon=True)
    tunnel_thread.start()
    
    # Keep main thread alive
    while not STOP_EVENT.is_set():
        time.sleep(1)
        
    return 0

if __name__ == "__main__":
    sys.exit(main())
