# n8n Distributed Deployment Guide

This repository contains the Docker Compose configurations to deploy a scalable, multi-host n8n setup. It uses Traefik as a reverse proxy for automatic SSL and Docker Swarm to create a network that allows services running on different servers to communicate securely.

---

## Final Architecture

* **VPS 1 (Main/Manager):** Runs the Traefik Reverse Proxy and the main n8n application instance.
* **VPS 2 (Worker):** Runs the n8n worker service.
* **VPS 3 (Database):** Runs the PostgreSQL database.
* **VPS 4 (Cache):** Runs the Redis instance.

*Note: You can combine services onto fewer VPSs if you wish, but this guide assumes a fully distributed four-server setup.*

---

## Prerequisites

Before you begin, make sure you have the following:

1.  **Four VPSs:** Each running a modern Linux distribution (like Ubuntu 20.04 or later).
2.  **Docker & Docker Compose:** Installed on all four VPSs.
3.  **DNS A Record:** A DNS `A` record for your chosen domain (e.g., `n8n.your-domain.com`) pointing to the public IP address of your **Main VPS (VPS 1)**. This is required for Traefik to successfully obtain an SSL certificate.
4.  **This Git Repository:** Cloned onto each of the four servers.

---

## Step 1: Prepare the Configuration File

Your `.env` file contains all the critical configuration. Create a file named `.env` in the root of this repository on **each of your four VPSs**. The content should be identical on all servers.

Use the `.env.template` file (if one exists) as a guide.

```env
# .env file
# Make sure to replace placeholder values

# Domain and SSL
SUBDOMAIN=n8n
DOMAIN_NAME=your-domain.com
SSL_EMAIL=your-email@your-domain.com

# Postgres
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=a-very-secure-password
POSTGRES_NON_ROOT_USER=n8n_user
POSTGRES_NON_ROOT_PASSWORD=a-different-secure-password

# n8n Basic Auth
N8N_BASIC_AUTH_USER=your-n8n-user
N8N_BASIC_AUTH_PASSWORD=another-secure-password

# Timezone
GENERIC_TIMEZONE=America/New_York
TZ=America/New_York

# ------------------------------------------------------------------
# Optional: Binary Data Storage (Uncomment and configure one option)
# ------------------------------------------------------------------

# Option 1: AWS S3
#N8N_BINARY_DATA_STORAGE="s3"
#N8N_S3_BUCKET_NAME="your-s3-bucket-name"
#N8N_S3_REGION="your-s3-bucket-region"
#N8N_S3_ACCESS_KEY_ID="your-access-key-id"
#N8N_S3_SECRET_ACCESS_KEY="your-secret-access-key"
# For S3-compatible storage like MinIO, add the endpoint URL:
#N8N_S3_ENDPOINT="[https://your-minio-endpoint.com](https://your-minio-endpoint.com)"

# Option 2: Google Cloud Storage (GCS)
#N8N_BINARY_DATA_STORAGE="gcs"
#N8N_GCS_BUCKET_NAME="your-gcs-bucket-name"
# See the "Configuring Binary Data Storage" section for GCS setup
#N8N_GCS_KEY_FILE_PATH="/path/to/your/google-credentials.json"
```

**Security Note:** The `.env` file is listed in `.gitignore` and should never be committed to your repository.

---

## Step 2: Set Up the Docker Swarm

The swarm allows containers on different machines to communicate.

1.  **SSH into your Main VPS (VPS 1).** This will be our "manager" node.
2.  **Initialize the Swarm:**
    ```bash
    docker swarm init
    ```
3.  **Copy the Join Token:** The previous command will output a `docker swarm join` command. Copy the entire line. It will look like this:
    ```
    docker swarm join --token SWMTKN-1-xxxxxxxx... <MANAGER_IP>:<PORT>
    ```
4.  **Join the Swarm from Other Nodes:**
    * SSH into **VPS 2 (Worker)** and paste the join command.
    * SSH into **VPS 3 (Database)** and paste the join command.
    * SSH into **VPS 4 (Cache)** and paste the join command.

All four servers are now part of the same cluster.

---

## Step 3: Create the Overlay Network

This special network will span all machines in the swarm. This only needs to be done once from the **manager node**.

1.  **On your Main VPS (VPS 1):**
    ```bash
    docker network create --driver overlay n8n-network
    ```

---

## Step 4: Deploy Your Services

It's time to bring your services online. The order is important. On each VPS, navigate to the correct directory before running the command.

1.  **Deploy PostgreSQL on VPS 3:**
    * SSH into VPS 3 and navigate to the `data-postgres/` directory.
    * Run the deployment command:
        ```bash
        docker-compose up -d
        ```

2.  **Deploy Redis on VPS 4:**
    * SSH into VPS 4 and navigate to the `data-redis/` directory.
    * Run the deployment command:
        ```bash
        docker-compose up -d
        ```

3.  **Deploy the Proxy on VPS 1:**
    * SSH into your Main VPS (VPS 1) and navigate to the `proxy-traefik/` directory.
    * Run the deployment command:
        ```bash
        docker-compose up -d
        ```

4.  **Deploy the Main n8n App on VPS 1:**
    * On your Main VPS (VPS 1), navigate to the `n8n-main/` directory.
    * Run the deployment command:
        ```bash
        docker-compose up -d
        ```

5.  **Deploy the n8n Worker on VPS 2:**
    * SSH into your Worker VPS (VPS 2) and navigate to the `n8n-worker/` directory.
    * Run the deployment command:
        ```bash
        docker-compose up -d
        ```

---

## Step 5: Verify the Deployment

After a few moments for the proxy to acquire SSL certificates, your setup should be complete.

* You can run `docker ps` on each machine to see the respective containers running.
* Navigate to your domain (`https://n8n.your-domain.com`). You should see the n8n login screen, protected by the basic authentication you configured.

You now have a fully distributed, scalable n8n deployment!

---

## Scaling the Workers

If you need to handle more concurrent workflows, you can easily scale up the number of worker services.

1.  **SSH into any node in your Docker Swarm** (the manager node, VPS 1, is a good choice).
2.  **Navigate to the `n8n-worker/` directory** within your cloned repository.
3.  **Run the scale command:**
    ```bash
    # This example scales to 3 workers. Change the number as needed.
    docker-compose up -d --scale n8n-worker=3
    ```

Docker Swarm will automatically create the additional worker containers and distribute them across the available VPSs in your swarm. You don't need to specify which machine they run on. You can scale down by running the same command with a lower number.

---

## Configuring Binary Data Storage (Optional but Recommended)

By default, binary data (files) from workflows is stored on the local filesystem of the worker that processes it. In a multi-host environment, it's highly recommended to use a centralized object store so all components have access to the same files.

### Option 1: AWS S3 or S3-Compatible Storage

1.  Add the following variables to your root `.env` file and fill in your details:
    ```env
    N8N_BINARY_DATA_STORAGE="s3"
    N8N_S3_BUCKET_NAME="your-s3-bucket-name"
    N8N_S3_REGION="your-s3-bucket-region"
    N8N_S3_ACCESS_KEY_ID="your-access-key-id"
    N8N_S3_SECRET_ACCESS_KEY="your-secret-access-key"
    # For S3-compatible storage like MinIO, add the endpoint URL:
    # N8N_S3_ENDPOINT="[https://your-minio-endpoint.com](https://your-minio-endpoint.com)"
    ```
2.  Redeploy the `n8n-main` and `n8n-worker` services for the changes to take effect.

### Option 2: Google Cloud Storage (GCS)

Configuring GCS requires mounting a service account key file into the n8n containers.

1.  **Create and download a Service Account JSON key** from your Google Cloud project with permissions to write to your GCS bucket.
2.  **Copy the key file** to the `n8n-main` and `n8n-worker` directories on their respective VPSs. For example, save it as `google-credentials.json`.
3.  **Add the GCS variables** to your root `.env` file:
    ```env
    N8N_BINARY_DATA_STORAGE="gcs"
    N8N_GCS_BUCKET_NAME="your-gcs-bucket-name"
    # This path is inside the container
    N8N_GCS_KEY_FILE_PATH="/app/google-credentials.json"
    ```
4.  **Modify two files** to mount the key file into the containers:
    * In `n8n-main/docker-compose.yml`, add a `volumes` directive to the `n8n-main` service:
        ```yaml
        services:
          n8n-main:
            #... existing configuration ...
            volumes:
              - ./google-credentials.json:/app/google-credentials.json:ro
        ```
    * In `n8n-worker/docker-compose.yml`, add a similar `volumes` directive to the `n8n-worker` service:
        ```yaml
        services:
          n8n-worker:
            #... existing configuration ...
            # You must add this volume mount to mount the credentials file
            volumes:
              - ./google-credentials.json:/app/google-credentials.json:ro
              - ./n8n-worker-data:/home/node/.n8n
        ```
5.  Redeploy the `n8n-main` and `n8n-worker` services for the changes to take effect.

---

Copyright © 2025 TILabs. All Rights Reserved.

Licensed under the [MIT](LICENSE) license.
