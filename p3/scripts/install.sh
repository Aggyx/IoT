#!/bin/bash

# exit on error, on unset variables
# and also if a command in a pipe fails
set -euo pipefail

sudo apt-get update
sudo apt-get install -y curl git ca-certificates

# each tool is installed only if it is not already installed

if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sudo sh
fi

# allow the user to run docker without sudo
sudo usermod -aG docker "$USER"

if ! command -v kubectl >/dev/null 2>&1; then
    curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
    rm -f /tmp/kubectl
fi

if ! command -v k3d >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

docker --version
kubectl version --client
k3d version

echo "Setup complete."
echo "Note: $USER added to the docker group. Re-login for it to take effect."





# we can make the kubectl link dynamic by using:
# ARCH="$(dpkg --print-architecture)" --> but we are always going to use it on Intel amd64, so no need
# KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)", this could be useful.
