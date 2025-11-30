# LockDev GitOps Registry & Controller

This repository contains the configuration and documentation for the **GitOps Registry** (Harbor) and **GitOps Controller** (Komodo) infrastructure.

## 🚀 Services

| Service | URL | Description |
| :--- | :--- | :--- |
| **Harbor** | [https://harbor.internal](https://harbor.internal) (or [https://192.168.1.33](https://192.168.1.33)) | Container Registry & Helm Chart Repository |
| **Komodo** | [https://komodo.internal](https://komodo.internal) | GitOps Controller & Fleet Manager |

## 🔑 Credentials (Initial Setup)

> **⚠️ IMPORTANT:** Change these passwords immediately after first login!

*   **Harbor Admin:**
    *   Username: `admin`
    *   Password: `YourStrongPassword123`
*   **Komodo Admin:**
    *   (Created on first launch)
*   **Mongo DB (Internal):**
    *   Username: `root`
    *   Password: `password`

## 🏗️ Infrastructure

*   **LXC Container:** `gitops-registry` (ID: `901`)
*   **IP Address:** `192.168.1.42`
*   **Host:** Proxmox Node (`192.168.1.30`)
*   **SSH Access:** `ssh root@192.168.1.42`

## 🛠️ Operational Management

### Restarting Services

Services are managed via Docker Compose inside the LXC.

**Harbor:**
```bash
ssh root@192.168.1.42
cd /root/harbor
docker compose restart
```

**Komodo:**
```bash
ssh root@192.168.1.42
cd /etc/komodo
docker compose restart
```

### Updating Images

**Harbor:**
Harbor upgrades require running the `install.sh` script with the `--with-trivy` (optional) flags again after downloading the new offline installer. Refer to [Harbor Docs](https://goharbor.io/docs/).

**Komodo:**
```bash
ssh root@192.168.1.42
cd /etc/komodo
docker compose pull
docker compose up -d
```

## 🐛 Troubleshooting

### 1. "Pulling fs layer" Hangs (Docker)
If Docker pulls hang indefinitely, it is likely an MTU issue or IPv6 timeout.
*   **Fix:** Ensure IPv6 is disabled and MTU is set to 1450.
*   **Check:** `cat /etc/docker/daemon.json`
    ```json
    {
      "storage-driver": "fuse-overlayfs",
      "mtu": 1450,
      "max-concurrent-downloads": 1
    }
    ```

### 2. Services Unreachable via Domain
*   **Check Traefik:** Ensure the Home Server (`192.168.1.33`) has the routing rules in `config/traefik/rules/gitops-registry.yml`.
*   **Check DNS:** Ensure `harbor.internal` resolves to `192.168.1.33` (Traefik IP), **NOT** the LXC IP.

### 3. "Connection Refused" (502 Bad Gateway)
*   **Check Containers:** SSH into LXC and run `docker ps`. Ensure `nginx` (Harbor) and `komodo-komodo-1` are Up.
*   **Check Ports:** Harbor listens on port **80** (HTTP). Komodo listens on port **9120** (HTTP).

## 📂 Directory Structure

*   `/root/harbor`: Harbor installation & config (`harbor.yml`).
*   `/etc/komodo`: Komodo installation & config (`docker-compose.yml`).
*   `/etc/komodo/data`: Persistent data for Komodo & Mongo.
*   `/data`: Persistent data for Harbor (images, database).
