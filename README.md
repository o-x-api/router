# GH_OmniRout: Near-Continuous Serverless OmniRoute Runner

A production-ready pipeline wrapper designed to run **OmniRoute** (the advanced proxy, translation, and gateway dashboard for LLMs) inside a **GitHub Actions Runner** with near-continuous uptime (using scheduled cron jobs) and secure public exposure via a **Cloudflare Edge Tunnel**. 

It uses a **Hugging Face Hub dataset** as a free, persistent storage engine to automatically backup and restore database files and secrets.

---

## ⚡ Key Features

* **Serverless Hosting:** Hosted entirely on GitHub Actions runners—no dedicated server or VPS required.
* **Persistent Storage:** Integrated with Hugging Face Hub datasets to sync, restore on boot, and back up SQLite database files and secrets dynamically during runtime.
* **Secure Cloudflare Edge Tunneling:** Exposes the runner safely using `cloudflared` managed edge tunnels, masking server IPs and removing the need for open ports.
* **Anti-Inactivity Keepalive:** Automatically commits small keepalive updates when active commit gaps approach GitHub’s workflow suspension threshold (6 days of repository inactivity).
* **Environment Protection:** Custom encryption keys are injected directly via GitHub Secrets at startup to avoid zero-config warning alerts and preserve session encryption integrity.

---

## 🏗️ Repository Structure

```
├── README.md                      # Deployment guide & overview
├── Dockerfile                 # Custom OmniRoute image with HF & network tools
├── entrypoint.sh              # Entry point script (RESTORE -> START -> BACKUP SCHEDULER)
├── keepalive.txt              # Keep-alive heartbeat file
├── start.sh                   # Runner orchestrator (DOCKER BUILD -> RUN -> CF TUNNEL -> KEEP ALIVE)
├── tunnel.py                  # Cloudflare Managed Tunnel initializer
└── .github/workflows/
    └── run-omniroute.yml      # Cron workflow definition (Runs every 6 hours)
```

---

## 🛠️ Setup & Deployment Guide

Follow these steps to deploy your own instance of OmniRoute using this pipeline:

### 1. Hugging Face Dataset Setup (Persistent Storage)
1. Register/Login to [Hugging Face Hub](https://huggingface.co/).
2. Create a new **Dataset** (recommend setting it to **Private** to protect your database secrets):
   * Select **SDK** as the dataset type.
3. Generate a **User Access Token** with **Write** permissions:
   * Go to **Settings -> Access Tokens -> New Token**.

### 2. Cloudflare Tunnel Setup (Public Access)
1. Register/Login to [Cloudflare Dashboard](https://dash.cloudflare.com/).
2. Navigate to **Zero Trust -> Networks -> Tunnels**.
3. Create a new tunnel (e.g., named `omniroute-runner`).
4. Copy the **Tunnel Token** generated in the Cloudflare Dashboard installation instructions.
5. Bind your custom domain/subdomain inside Cloudflare to the tunnel's local service:
   * Path: `http://localhost:20128`

### 3. GitHub Repository Secrets Setup
Create a new GitHub Repository and push this code. Then, go to **Settings -> Secrets and variables -> Actions** and add the following repository secrets:

| Secret Name | Description | Example / Format |
| :--- | :--- | :--- |
| `HF_TOKEN` | Hugging Face Access Token with Write scope | `hf_...` |
| `HF_USER_NAME` | Your Hugging Face Username | `myuser` |
| `HF_DATASET_NAME` | Your Private Dataset Name | `omniroute-db` |
| `CLOUDFLARE_TUNNEL_TOKEN` | Your Cloudflare Zero Trust Tunnel Token | A long JWT token string |
| `INITIAL_PASSWORD` | Initial admin dashboard setup password | `MySecureAdminPassword123` |
| `JWT_SECRET` | Secret key used to sign dashboard cookies | 64-character hex string (e.g., `openssl rand -hex 32`) |
| `STORAGE_ENCRYPTION_KEY` | Key used to encrypt credentials in SQLite | 64-character hex string (e.g., `openssl rand -hex 32`) |
| `API_KEY_SECRET` | Secret key used to sign locally-generated API keys | 64-character hex string (e.g., `openssl rand -hex 32`) |
| `MODEL_TEST_TIMEOUT_MS` | (Optional) Limit for model testing connection checks in ms | `60000` (Defaults to 60s if not set) |


---

## 🚀 How it Works under the Hood

When the GitHub Actions workflow runs:

1. **Keep-alive Check:** Checks if the repository has had any activity in the last 6 days. If not, it pushes a minor edit to `keepalive.txt` to keep the runner active.
2. **Build and Restore:**
   * Downloads and installs the `cloudflared` binary on the runner host.
   * Builds a custom Docker image extending the official `diegosouzapw/omniroute` release.
   * Restores the latest database file (`storage.sqlite`) and encryption keys (`server.env`) from your Hugging Face dataset folder.
3. **Execution & Port Forwarding:**
   * Starts the docker container, mounting the `/app/data` volume.
   * Runs the Cloudflare tunnel in the background to securely expose port `20128` to your configured domain.
   * Sinks custom credentials safely to `/app/data/server.env` so that OmniRoute boots with `OMNIROUTE_BOOTSTRAPPED="false"` (no zero-config warning alerts).
4. **Active Sync Scheduler:**
   * Spins up an automatic cron routine in the container background that pushes SQLite database snapshots to your Hugging Face dataset every 5 minutes.
5. **Session Termination & Backup:**
   * The Action loops for ~5 hours 45 minutes to maximize runner lifetime.
   * On termination (or when receiving shutdown signals), a final snapshot backup is successfully synced to Hugging Face before stopping the container.
