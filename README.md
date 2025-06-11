# n8n Distributed Deployment Guide

This repository contains the Docker Compose configurations to deploy a scalable, multi-host n8n setup. It uses Traefik as a reverse proxy for automatic SSL and Docker Swarm to create a network that allows services running on different servers to communicate securely. This setup is designed for production use, leveraging named volumes for data persistence and reliability.

---

## Final Architecture

* **VPS 1 (Main/Manager):** Runs the Traefik Reverse Proxy and the main n8n application instance.
* **VPS 2 (Worker):** Runs the n8n worker service.
* **VPS 3 (Database):** Runs the PostgreSQL database.
* **VPS 4 (Cache):** Runs the Redis instance.

* **(Optional) Additional VPSs:** Can be added to the swarm to scale workers further.
* Note: You can combine services onto fewer VPSs if you wish, but this guide assumes a fully distributed four-server setup.*

---

## Prerequisites

Before you begin, make sure you have the following:

1.  **Multiple VPSs:** Each running a modern Linux distribution (like Ubuntu 22.04 or later).
2.  **Docker & Docker Compose:** Installed on all VPSs.
3.  **DNS A Record:** A DNS `A` record for your chosen domain (e.g., `n8n.your-domain.com`) pointing to the public IP address of your **Main VPS (VPS 1)**. This is critical for Traefik to successfully obtain an SSL certificate.
4.  **This Git Repository:** Cloned onto each of the servers that will run a service.

---

## Step 1: Prepare the Configuration File

Your `.env` file contains all the critical configuration. Create a file named `.env` in the root of this repository on **each server where you will run a service**. The content should be identical on all servers. Copy `.env.example` file and rename it to `.env` to start creating your environment file.

**Security Note:** The `.env` file is listed in `.gitignore` and must never be committed to your repository.

---

## Step 2: Set Up the Docker Swarm

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
4.  **Join the Swarm from Other Nodes:**
    * SSH into **VPS 2 (Worker)** and paste the join command.
    * SSH into **VPS 3 (Database)** and paste the join command.
    * SSH into **VPS 4 (Cache)** and paste the join command.
    * Repeat for any additional VPSs you want to add to the cluster.

---

## Step 3: Create the Encrypted Overlay Network

This special network will span all machines in the swarm, encrypting all application traffic between them. This only needs to be done **once** from the **manager node**.

1.  **On your Main VPS (VPS 1):**
    ```bash
    docker network create --driver overlay --opt encrypted n8n-network
    ```

---

## Step 4: Deploy Your Services

It's time to bring your services online. The order is important. On each respective VPS, navigate into the correct directory from the repository before running the command.

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

After a few moments for the proxy to acquire an SSL certificate, your setup should be complete.

* You can run `docker ps` on each machine to see the respective containers running.
* Navigate to your domain (`https://n8n.your-domain.com`). You should see the n8n login screen, protected by the basic authentication you configured.

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

By default, binary data (files) from workflows is stored temporarily. For a production environment, you must use a centralized object store so all components have access to the same files. Choose one of the options below.

### Option 1: AWS S3 or S3-Compatible Storage

1.  Uncomment and fill in the S3 variables in your root `.env` file.
2.  Redeploy the `n8n-main` and `n8n-worker` services for the changes to take effect:
    ```bash
    # On VPS 1 in n8n-main/
    docker-compose up -d --force-recreate

    # On VPS 2 in n8n-worker/
    docker-compose up -d --force-recreate
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
