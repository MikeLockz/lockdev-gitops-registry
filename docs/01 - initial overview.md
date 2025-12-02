# Deployment Plan: Komodo and Harbor on Proxmox LXC

This plan outlines the detailed deployment of a new infrastructure stack hosting Komodo and Harbor within a new Debian 12 LXC container on Proxmox, and integrating them into your existing environment.

## Phase 1: Planning and Decisions

Before touching any configuration files, several decisions must be made.

### Questions and Decisions Required

| Area | Question | Decision/Notes |
| :--- | :--- | :--- |
| **Networking** | Traefik Routing | **[COMPLETED] Selected: Local-Only Routing.**<br>1. **External:** No external access required via Cloud VPS.<br>2. **Internal:** User -> Local Traefik (Terminates SSL via Self-Signed or DNS Challenge) -> LXC.<br>**Note:** All traffic stays on the LAN.<br>**Update:** Added IP fallback `Host(\`192.168.1.33\`)` to Traefik rules to handle DNS issues on some clients. |
| **Networking** | Cloud VPS Traefik | **[COMPLETED] Not Required.** Since public access is not needed, the Cloud VPS Traefik is removed from the flow. |
| **DNS** | Local Resolution | **[COMPLETED] Crucial:** Pi-hole (on `192.168.1.*`) is already configured to resolve `*.internal` to the **Home Server's LAN IP**. This ensures all devices on the network can reach the services.<br>**Update:** Configured `/etc/hosts` on LXCs to resolve `harbor.internal` to `192.168.1.33`. |
| **Proxmox** | LXC Specs | **[COMPLETED]** - **ID**: `901`<br>- **Hostname**: `gitops-registry`<br>- **IP**: `192.168.1.42/24`<br>- **Gateway**: `192.168.1.1`<br>- **Resources**: 4GB RAM, 2 Cores, 40GB Storage (Harbor images can get large). |
| **Storage** | Harbor Persistence | **[COMPLETED]** Using local storage on the LXC for now. |

## Phase 2: Infrastructure Provisioning and Tool Installation [COMPLETED]

### Step 1: Create the New Debian 12 LXC on Proxmox [COMPLETED]

Provision a new unprivileged container (`gitops-registry`). Critical settings for Docker support are required.

**Proxmox Shell Command (Example):**

```bash
pct create 901 local-lvm:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
  --hostname gitops-registry \
  --cores 2 --memory 4096 --swap 512 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.42/24,gw=192.168.1.1 \
  --features nesting=1,keyctl=1 \
  --unprivileged 1 \
  --start 1
```

*Note: `nesting=1` and `keyctl=1` are essential for running Docker inside an LXC container.*

**Post-Boot Setup:**
SSH into `192.168.1.42` and run:

```bash
apt update && apt upgrade -y
apt install curl gnupg lsb-release ca-certificates git fuse-overlayfs -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Configure Docker to use fuse-overlayfs (Best for LXC)
mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "storage-driver": "fuse-overlayfs"
}
EOF

# Enable Docker service
systemctl enable docker
systemctl start docker
```

### Step 1.5: Configure Local DNS Resolution (Split-Horizon)

To prevent `harbor.internal` traffic from going out to the internet and back, configure your network's DNS resolver (e.g., Pi-hole, AdGuard Home, OPNsense/pfSense).

**Goal:** Ensure `*.internal` resolves to the **LAN IP** of the Home Server (the host running Traefik), **NOT** the new LXC IP directly (unless you are bypassing Traefik).

*   **Pi-hole:** Go to "Local DNS" -> "DNS Records". Add `harbor.internal` pointing to `192.168.1.X` (Home Server IP).
*   **AdGuard Home:** Go to "Filters" -> "DNS Rewrites". Add `*.internal` -> `192.168.1.X`.
*   **No Central DNS?** As a temporary measure, you can edit `/etc/hosts` on every LXC container that needs to access these services:
    ```bash
    # On App-LXC and Observability-LXC
    echo "192.168.1.X  harbor.internal komodo.internal" | sudo tee -a /etc/hosts
    ```

### Step 2: Configure Local Traefik (Internal Routing) [COMPLETED]

On your **existing** home server (where Traefik runs), you need to route traffic to the new LXC. This local Traefik instance will receive **HTTP traffic** from the Cloud VPS Traefik (which handles SSL termination) and then forward it to the LXC services. Assuming you use a file provider for dynamic configuration:

**File:** `traefik/dynamic/infra-lxc.yml`

```yaml
http:
  routers:
    harbor-rtr:
      rule: "Host(`harbor.internal`)"
      entryPoints: ["websecure"] # HTTPS entrypoint
      service: "harbor-svc"
      tls: {} # Enable TLS (uses default/self-signed cert if no resolver configured)

    komodo-rtr:
      rule: "Host(`komodo.internal`)"
      entryPoints: ["websecure"] # HTTPS entrypoint
      service: "komodo-svc"
      tls: {} # Enable TLS

  services:
    harbor-svc:
      loadBalancer:
        servers:
          - url: "http://192.168.1.42:80" # Harbor internal HTTP port

    komodo-svc:
      loadBalancer:
        servers:
          - url: "http://192.168.1.42:9120" # Komodo Manager port
```

*Ensure your local DNS server (e.g., Pi-hole, AdGuard Home, or Router) points `harbor.internal` and `komodo.internal` to your Traefik Host IP, NOT the new LXC IP directly, so Traefik can handle the routing.*

### Step 3: Install Harbor [COMPLETED]

1.  **Download Installer:**
    ```bash
    wget https://github.com/goharbor/harbor/releases/download/v2.10.0/harbor-offline-installer-v2.10.0.tgz
    tar xzvf harbor-offline-installer-v2.10.0.tgz
    cd harbor
    cp harbor.yml.tmpl harbor.yml
    ```

2.  **Configure `harbor.yml`:**
    Since Traefik handles SSL, we configure Harbor to run in HTTP mode internally but be aware of its external HTTPS URL.

    ```yaml
hostname: harbor.internal

# HTTP configuration
http:
  port: 80

# Comment out or remove the https section if Traefik terminates SSL
# https:
#   port: 443
#   certificate: /your/certificate/path
#   private_key: /your/private/key/path

external_url: https://harbor.internal

# Admin password
harbor_admin_password: "YourStrongPassword123!"
```

3.  **Install:**
    ```bash
    sudo ./install.sh
    ```

### Step 3.1: Configure Image Retention Policy [PENDING - ACTION REQUIRED]

To allow for rollbacks while preventing disk overflow, configure a retention policy.

1.  **Login:** Access `https://harbor.internal` (admin/YourStrongPassword123!).
2.  **Configure Policy:** Go to **Projects** -> [Select Project] -> **Policy** -> **Tag Retention**.
3.  **Add Rule:**
    *   **Repository Pattern:** `**`
    *   **Retention:** Keep the most recent **5** artifacts.
    *   **Schedule:** Run daily or weekly.

### Step 4: Install Komodo Manager [COMPLETED]

Deploy Komodo Manager using Docker Compose.

**File:** `/etc/komodo/docker-compose.yml`

```yaml
version: '3.8'

services:
  mongo:
    image: mongo:7
    volumes:
      - ./data/mongo:/data/db
    restart: unless-stopped

  komodo:
    image: ghcr.io/mbecker/komodo:latest
    restart: unless-stopped
    ports:
      - "9120:9120" # Web UI & API
    depends_on:
      - mongo
    environment:
      - KOMODO_DATABASE_ADDRESS=mongo:27017
      - KOMODO_DATABASE_USERNAME=root       # If auth enabled on mongo
      - KOMODO_DATABASE_PASSWORD=password   # If auth enabled on mongo
      # Core config
      - KOMODO_DOMAIN=https://komodo.internal
      # Disable internal SSL since Traefik handles it
      - KOMODO_SSL_ENABLED=false 
    volumes:
      - ./data/komodo-repo:/repo # Storage for cloned git repos
```

**Deploy:**
```bash
docker compose up -d
```

### Step 5: Install Komodo Periphery Agents [COMPLETED]

**Update:** Installed Agent on `app-stack` (`192.168.1.44`) to manage application deployments. Removed agent from Home Server (`192.168.1.33`).

On your **existing** App and Observability LXCs (the targets), install the agent.

1.  **Generate API Key:** In Komodo UI -> User Settings -> Create API Key.
2.  **Deploy Agent:**

    ```bash
    docker run -d --name komodo-periphery \
      --restart unless-stopped \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -e KOMODO_HOST=https://komodo.internal \
      -e KOMODO_API_KEY=YOUR_GENERATED_KEY \
      ghcr.io/mbecker/komodo-periphery:latest
    ```

### Step 5.1: Configure Docker Clients (Insecure Registry) [COMPLETED]

**Update:** Configured `insecure-registries` on `gitops-registry` (`.42`) and `app-stack` (`.44`) to trust `harbor.internal` (via `.33`).

Since `harbor.internal` uses self-signed certificates (or no valid public cert), all Docker clients (Runners, App LXC, Observability LXC) must be configured to trust it.

**On EVERY client machine (including your CI Runner):**

1.  Edit/Create `/etc/docker/daemon.json`:
    ```bash
    sudo nano /etc/docker/daemon.json
    ```
2.  Add the insecure-registries key:
    ```json
    {
      "insecure-registries" : ["harbor.internal"]
    }
    ```
    *(If the file already exists, just add this key to the existing JSON object).*
3.  Restart Docker:
    ```bash
    sudo systemctl restart docker
    ```

## Phase 3: Integration and Refactoring Existing Workflows [COMPLETED]

### Step 6: Update the "App Stack" Workflow (Source Repo 1) [COMPLETED]

This GitHub Action runs on your **self-hosted runner** which has access to `harbor.internal`.

**Repo:** `MikeLockz/el-dorado-tanstack`
**File:** `.github/workflows/deploy-self-hosted.yml` (Renamed to "Build and Push")

**Changes Implemented:**
1.  **Tagging Strategy:** Uses `sha-${{ github.sha }}` as the primary immutable tag.
2.  **Push:** Pushes to Harbor (`harbor.internal`).
3.  **GitOps Trigger:** Automatically updates `stacks/el-dorado.toml` in the Config Repo (`lockdev-gitops-registry`) with the new tag.

### Step 7: Configure Komodo Resource (GitOps) [COMPLETED]

In your **Observability/Config Repository**, define the stack.

**Repo:** `MikeLockz/lockdev-gitops-registry`
**File:** `stacks/el-dorado.toml`

```toml
[stack]
name = "el-dorado"
host = "infra-lxc-01"

[service.web]
image = "harbor.internal/el-dorado/web"
tag = "latest" # Updated by CI
restart = "unless-stopped"
ports = ["8080:8080"]
# ... env vars ...

[service.server]
image = "harbor.internal/el-dorado/server"
tag = "latest" # Updated by CI
restart = "unless-stopped"
ports = ["3001:3000"]
# ... env vars ...
```

## End State Verification

1.  **Network:** `ping harbor.internal` from your runner resolves to the Traefik IP.
2.  **Docker:** `docker pull harbor.internal/myproject/myapp` works on the App LXC.
3.  **Komodo:** The Komodo UI shows the "production-app" stack as "Healthy" and syncs changes when the Config Repo is updated.