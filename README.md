# n8n Distributed Deployment Guide

This repository contains the Docker Compose configurations to deploy a scalable, multi-host n8n setup. It uses Traefik as a reverse proxy for automatic SSL and Docker Swarm to create a network that allows services running on different servers to communicate securely. This setup is designed for production use, leveraging named volumes for data persistence and reliability.

---

## Final Architecture

* **VPS 1 (Main/Manager):** Runs the Traefik Reverse Proxy and the main n8n application instance.
* **VPS 2 (Worker):** Runs the n8n worker service.
* **VPS 3 (Database):** Runs the PostgreSQL database.
* **VPS 4 (Cache):** Runs the Redis instance.

* **(Optional) Additional VPSs:** Can be added to the swarm to scale workers further.

*Note: You can combine services onto fewer VPSs if you wish, but this guide assumes a fully distributed four-server setup.*

---

## Prerequisites

Before you begin, make sure you have the following:

1.  **Multiple VPSs:** Each running a modern Linux distribution (like Ubuntu 22.04 or later).
2.  **Docker & Docker Compose:** Installed on all VPSs.
3.  **DNS A Record:** A DNS `A` record for your chosen domain (e.g., `n8n.your-domain.com`) pointing to the public IP address of your **Main VPS (VPS 1)**. This is critical for Traefik to successfully obtain an SSL certificate.
4.  **This Git Repository:** Cloned onto each of the servers that will run a service.

---

## Step 1: Prepare the Configuration File

On your **manager node (VPS 1)**, create a file named `.env` in the root of this repository. The `docker stack deploy` command will use this file for all services. Copy `.env.example` and rename it to `.env` to start.

**Security Note:** The `.env` file is listed in `.gitignore` and must never be committed to your repository.

---

## Step 2: Secure the Swarm with a Firewall (Recommended)

For production, it is critical to ensure that the required Docker Swarm ports are only accessible by other nodes in your cluster. This prevents unauthorized access to your swarm's management plane.

The following ports must be open for communication **between all your swarm nodes**:
* **TCP port `2377`:** For cluster management communication.
* **TCP and UDP port `7946`:** For communication among nodes.
* **UDP port `4789`:** For the overlay network traffic.

The easiest way to setup firewall for `docker swarm` is by running `./scripts/create_docker_swarm_ufw_app_profile.sh` file to create ufw app profile on Ubuntu, then you can use the app profile to allow connection.

```bash
sudo ufw allow from IP_OF_VPS to any app "Docker Swarm"
```

Or, here is an example using `ufw` (Uncomplicated Firewall) on Ubuntu. **You must run these commands on every VPS**, replacing the placeholder IPs with your actual server IPs.

**First, get the public IP address for each of your nodes:**
* **VPS-1 (Manager):** `IP_OF_VPS_1`
* **VPS-2 (Worker):** `IP_OF_VPS_2`
* **VPS-3 (Database):** `IP_OF_VPS_3`
* **VPS-4 (Cache):** `IP_OF_VPS_4`

**Example: Commands to run on VPS-1 (Manager)**
```bash
# Allow traffic from the other nodes
sudo ufw allow from IP_OF_VPS_2 to any port 2377 proto tcp
sudo ufw allow from IP_OF_VPS_2 to any port 7946
sudo ufw allow from IP_OF_VPS_2 to any port 4789 proto udp

sudo ufw allow from IP_OF_VPS_3 to any port 2377 proto tcp
sudo ufw allow from IP_OF_VPS_3 to any port 7946
sudo ufw allow from IP_OF_VPS_3 to any port 4789 proto udp

sudo ufw allow from IP_OF_VPS_4 to any port 2377 proto tcp
sudo ufw allow from IP_OF_VPS_4 to any port 7946
sudo ufw allow from IP_OF_VPS_4 to any port 4789 proto udp

# After adding all rules, reload the firewall
sudo ufw reload
```
**Important:** You must repeat this process on all other nodes. For example, on **VPS-2**, you would add rules to allow traffic *from* `IP_OF_VPS_1`, `IP_OF_VPS_3`, and `IP_OF_VPS_4`.

---

## Step 3: Set Up the Docker Swarm

The swarm allows containers on different machines to communicate securely.

1.  **SSH into your Main VPS (VPS 1).** This will be our "manager" node.
2.  **Initialize the Swarm:**
    ```bash
    docker swarm init
    ```
3.  **Copy the Join Token:** The previous command will output a `docker swarm join` command. Copy the entire line. It will look like this:
    ```
    docker swarm join --token SWMTKN-1-xxxxxxxx... <MANAGER_IP>:<PORT>
    ```
4.  **Join Worker Nodes:** SSH into all other VPSs (2, 3, 4, etc.) and run the join command you just copied.
    * SSH into **VPS 2 (Worker)** and paste the join command.
    * SSH into **VPS 3 (Database)** and paste the join command.
    * SSH into **VPS 4 (Cache)** and paste the join command.
    * Repeat for any additional VPSs you want to add to the cluster.

---

## Step 4: Create the Encrypted Overlay Network

This special network will span all machines in the swarm, encrypting all application traffic between them. This only needs to be done **once** from the **manager node**.

1.  **On your Main VPS (VPS 1):**

First, you need to make sure the MTU size of your network you want to use using `ip a` or `ipconfig`. This is the example output of `ip a`:

    ```txt
    2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000 # <<<< See this line there is MTU size right here and it says the size of MTU of this network is 1500.
        link/ether xx:xx:xx:xx:xx:xx brd ff:ff:ff:ff:ff:ff
        altname enp0s18
        inet 192.168.1.432/22 brd 192.168.1.255 scope global eth0
        valid_lft forever preferred_lft forever
        inet6 xxxx:xxxx:xxxx:xxxx::1/64 scope global
        valid_lft forever preferred_lft forever
        inet6 xxxx::xxxx:xxxx:xxxx:xxxx/64 scope link
        valid_lft forever preferred_lft forever
    ```

After that, you can create the overlay network that will span over docker swarm nodes.

    ```bash
    # If the MTU size is 1500
    docker network create --driver overlay --opt encrypted --attachable n8n-network

    # If you ecounter context deadline exceeded issue and use wireguard or you use the network , you can use this instead
    docker network create \
        --driver overlay \
        --opt encrypted \
        --attachable \
        --opt com.docker.network.driver.mtu=1420 \
        n8n-network
    ```

---

## Step 5: Deploy Your Services

It's time to bring your application to life. All of the following commands must be run from the **manager node (VPS 1)** and from the **root directory** of this repository.

We will deploy all services into a single "stack" named `n8n`.

```bash
# Navigate to the root of your repository on the manager node
cd /path/to/your/n8n-deployment/

# Deploy each component to the 'n8n' stack
docker stack deploy -c data-postgres/docker-compose.yml n8n
docker stack deploy -c data-redis/docker-compose.yml n8n
docker stack deploy -c proxy-traefik/docker-compose.yml n8n
docker stack deploy -c n8n-main/docker-compose.yml n8n
docker stack deploy -c n8n-worker/docker-compose.yml n8n
```
*Note: Using the same stack name (`n8n`) merges all services into one logical application, allowing them to communicate seamlessly.*

---

## Step 6: Verify the Deployment

1.  **Check Service Status:** From the manager node, run:
    ```bash
    docker service ls
    ```
    You should see a list of all your services (e.g., `n8n_postgres`, `n8n_traefik`, `n8n_n8n-main`). Check the `REPLICAS` column. `1/1` means the service is running correctly.

2.  **Inspect a Specific Service:** To see where a service is running, use:
    ```bash
    # Example for the n8n-main service
    docker service ps n8n_n8n-main
    ```

3.  **Check n8n UI:** Navigate to your domain (`https://n8n.your-domain.com`). After a moment for SSL certificate generation, you should see the n8n login screen.

---

## Troubleshooting & Advanced Setup

### Issue: "context deadline exceeded" Error

If your `docker-compose up` command fails with a `context deadline exceeded` error, it means the nodes cannot communicate over the required ports. This is almost always due to a **firewall managed by your cloud provider** that is blocking the traffic before it reaches your server's `ufw` firewall.

**If you cannot modify your cloud provider's firewall rules, the best solution is to create a VPN tunnel between your nodes using WireGuard.**

### Alternative Setup: Using WireGuard VPN

Follow these steps **instead of Step 3 (Configure Firewall Rules)** if you need to bypass your cloud provider's network restrictions.

#### 1. Install WireGuard
Run this on **every VPS** in your cluster.
```bash
sudo apt update && sudo apt install wireguard -y
```

#### 2. Generate Keys for Each VPS
On **each VPS**, generate a unique key pair.
```bash
cd /etc/wireguard/ && umask 077
wg genkey > private.key
wg pubkey < private.key > public.key
```
**Action:** Note down the `public.key` from every server.

#### 3. Configure WireGuard
Decide on a private IP scheme (e.g., `10.0.0.1` for manager, `10.0.0.2` for worker, etc.).

**On VPS-1 (Manager), create `/etc/wireguard/wg0.conf`:**
```ini
[Interface]
Address = 10.0.0.1/24
PrivateKey = <PASTE_PRIVATE_KEY_OF_VPS_1>
ListenPort = 51820

# --- Peer for each worker node ---
[Peer]
PublicKey = <PASTE_PUBLIC_KEY_OF_A_WORKER_VPS>
Endpoint = <PUBLIC_IP_OF_VPS_1>:51820
AllowedIPs = <PRIVATE_IP_OF_WORKER>/32
PersistentKeepalive = 25
```

**On each Worker VPS, create `/etc/wireguard/wg0.conf`:**
```ini
[Interface]
Address = <PRIVATE_IP_FOR_THIS_WORKER>/24
PrivateKey = <PASTE_PRIVATE_KEY_OF_THIS_VPS>
ListenPort = 51820

[Peer]
PublicKey = <PASTE_PUBLIC_KEY_OF_VPS_1_MANAGER>
Endpoint = <PUBLIC_IP_OF_VPS_1>:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

#### 4. Enable IP Forwarding on Manager
On **VPS-1 (Manager)**, edit `/etc/sysctl.conf`, uncomment `net.ipv4.ip_forward=1`, and run `sudo sysctl -p`.

#### 5. Enable WireGuard and Update `ufw`
On **all VPSs**:
```bash
sudo ufw allow 51820/udp
sudo wg-quick up wg0
sudo systemctl enable wg-quick@wg0
sudo ufw reload
```

#### 6. Allow docker ports on wireguard's private IP
on **all VPSs**:
```bash
sudo ufw allow from WIREGUARD_PRIVATE_IP to any port 2377 proto tcp
sudo ufw allow from WIREGUARD_PRIVATE_IP to any port 7946
sudo ufw allow from WIREGUARD_PRIVATE_IP to any port 4789 proto udp
```

#### 7. Re-Initialize Swarm over WireGuard
You must now create your swarm using the private WireGuard IPs.
- On Manager: `docker swarm init --advertise-addr 10.0.0.1`
- Use the new join token on all workers.

---

### Scaling the Workers

To handle more workflows, you can easily scale up the worker service.
```bash
# This example scales to 3 workers. Change the number as needed.
docker service scale n8n_n8n-worker=3
```

### Updating a Service
If you make a change to a `.env` variable or a `docker-compose.yml` file, simply re-run the `docker stack deploy` command for that component. Swarm will automatically apply the changes in a rolling-update fashion.
```bash
# Example: Re-deploying n8n-main after an .env change
docker stack deploy -c n8n-main/docker-compose.yml n8n
```

---

## Configuring Binary Data Storage (Optional but Recommended)

By default, binary data (files) from workflows is stored temporarily. For a production environment, you must use a centralized object store so all components have access to the same files. Choose one of the options below.

### Option 1: AWS S3 or S3-Compatible Storage

1.  Uncomment and fill in the S3 variables in your root `.env` file.
2.  Redeploy the `n8n-main` and `n8n-worker` services for the changes to take effect:
    ```bash
    # On VPS 1 in n8n-main/
    docker compose up -d --force-recreate

    # On VPS 2 in n8n-worker/
    docker compose up -d --force-recreate
    ```

### Option 2: Google Cloud Storage (GCS)

Configuring GCS requires mounting a service account key file into the n8n containers.

1.  **Create and download a Service Account JSON key** from your Google Cloud project with permissions to write to your GCS bucket.
2.  **Copy the key file** to the `n8n-main` directory on VPS 1 and the `n8n-worker` directory on VPS 2. For example, save it as `google-credentials.json` in both locations.
3.  **Uncomment and fill in the GCS variables** in your root `.env` file.
4.  **Modify two files** to mount the key file into the containers:
    * In `n8n-main/docker-compose.yml`, add a `volumes` directive to the `n8n-main` service:
        ```yaml
        services:
          n8n-main:
            #... existing configuration ...
            volumes:
              - ./google-credentials.json:/app/google-credentials.json:ro
              - n8n_main_logs:/logs
        ```
    * In `n8n-worker/docker-compose.yml`, add a similar `volumes` directive to the `n8n-worker` service (note that this file already has a volumes section, so just add the new line):
        ```yaml
        services:
          n8n-worker:
            #... existing configuration ...
            volumes:
              - n8n_worker_data:/home/node/.n8n
              - ./google-credentials.json:/app/google-credentials.json:ro
              - n8n_worker_logs:/logs
        ```
5.  Redeploy the `n8n-main` and `n8n-worker` services for the changes to take effect as shown in the S3 instructions.

---

Copyright © 2025 TILabs. All Rights Reserved.

Licensed under the [MIT](LICENSE) license.
