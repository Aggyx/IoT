#!/bin/bash
# ProvScript para k3s Worker Node (Agente)
# Script de instalación y configuración del nodo worker k3s
# Uso: ./provision-worker.sh <NODE_IP> <SERVER_IP>

set -eu

apt-get update && apt-get install -y curl 

NODE_IP="$1"
SERVER_IP="$2"

echo "Configuración del nodo worker: NODE_IP=$NODE_IP, SERVER_IP=$SERVER_IP"

# Detectar interfaz de red asociada a la IP del nodo
IFACE=$(ip -o -4 addr show | awk '{print $2, $4}' | grep "$NODE_IP" | cut -d' ' -f1)
[ -n "$IFACE" ] || { echo "ERROR: no se encontró interfaz con IP $NODE_IP"; exit 1; }
echo "Usando interfaz $IFACE para $NODE_IP"

# Crear directorio de configuración de rancher/k3s
mkdir -p /etc/rancher/k3s

# Generar archivo de configuración del agente
cat > /etc/rancher/k3s/config.yaml <<EOF
node-ip: $NODE_IP
flannel-iface: $IFACE
EOF

echo "Esperando el token del servidor k3s desde $SERVER_IP..."
for i in $(seq 1 180); do
  if [ -s /tokens/node-token ]; then
    echo "Token encontrado!"
    break
  fi
  if [ $((i % 20)) -eq 0 ]; then
    echo "Esperando el token... ($i/180)"
  fi
  sleep 1
done

if [ ! -s /tokens/node-token ]; then
  echo "ERROR: TOKEN no esta en /tokens"
  ls -la /tokens/ || true
  exit 1
fi

TOKEN=$(cat /tokens/node-token)

echo "Token recibido, iniciando el agente k3s..."
curl -sfL https://get.k3s.io | \
  K3S_URL="https://${SERVER_IP}:6443" \
  K3S_TOKEN="$TOKEN" \
  sh -

sleep 5

NODE_NAME=$(hostname | tr '[:upper:]' '[:lower:]')
echo "Esperando a que el nodo $NODE_NAME se registre..."
for i in $(seq 1 120); do
  if [ -f /var/lib/rancher/k3s/agent/kubelet.kubeconfig ]; then
    export KUBECONFIG=/var/lib/rancher/k3s/agent/kubelet.kubeconfig
    if /usr/local/bin/kubectl get node "$NODE_NAME" >/dev/null 2>&1; then
      echo "Nodo $NODE_NAME registrado!"
      break
    fi
  fi
  if [ $((i % 20)) -eq 0 ]; then
    echo "Esperando a que el nodo se registre... ($i/120)"
  fi
  sleep 1
done

export KUBECONFIG=/var/lib/rancher/k3s/agent/kubelet.kubeconfig
if ! /usr/local/bin/kubectl get node "$NODE_NAME" >/dev/null 2>&1; then
  echo "ERROR: el nodo $NODE_NAME no se registró en el servidor"
  exit 1
fi

echo "Instalación completada del agente k3s"

