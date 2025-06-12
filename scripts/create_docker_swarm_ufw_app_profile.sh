#!/bin/bash
# This script creates a UFW application profile for Docker Swarm
# to simplify firewall management across cluster nodes.
# Run this script with sudo on each node in your swarm.

# Exit immediately if a command exits with a non-zero status.
set -e

APP_PROFILE_PATH="/etc/ufw/applications.d/docker-swarm"

echo "⚙️  Creating UFW application profile for Docker Swarm..."

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "⚠️  This script needs to be run with sudo."
  echo "   Please run it as: sudo ./setup-ufw-swarm.sh"
  exit 1
fi

# Create the application profile configuration file
tee "${APP_PROFILE_PATH}" > /dev/null <<EOF
[Docker Swarm]
title=Docker Swarm Communication Ports
description=Ports needed for Docker Swarm to function across nodes (TCP 2377, TCP/UDP 7946, UDP 4789)
ports=2377/tcp|7946/tcp|7946/udp|4789/udp
EOF

echo "✅ Profile file created successfully at ${APP_PROFILE_PATH}."

echo "🔄 Updating UFW application profiles..."
ufw app update "Docker Swarm" > /dev/null

echo "🔄 Reloading firewall rules..."
ufw reload > /dev/null

echo ""
echo "🎉 Setup complete!"
echo "You can now easily allow traffic from your other nodes."
echo "ℹ️  Use the following command, replacing the IP address:"
echo ""
echo "   sudo ufw allow from <IP_OF_OTHER_NODE> to any app 'Docker Swarm'"
echo ""
