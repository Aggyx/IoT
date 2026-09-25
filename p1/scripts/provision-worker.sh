#!/bin/bash
# ProvScript para k3s Worker Node (Agente)
# Script de instalación y configuración del nodo worker k3s
# Uso: ./provision-worker.sh <NODE_IP> <SERVER_IP>

set -eu

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
  if [ -f /tokens/node-token ]; then
    echo "Token encontrado!"
    break
  fi
  if [ $((i % 20)) -eq 0 ]; then
    echo "Esperando el token... ($i/180)"
  fi
  sleep 1
done

if [ ! -f /tokens/node-token ]; then
  echo "ERROR: TOKEN no esta en /tokens"
  ls -la /tokens/ || true
  exit 1
fi

TOKEN=$(cat /tokens/node-token)
if [ -z "$TOKEN" ]; then
  echo "ERROR: El archivo de token está vacío"
  exit 1
fi

# Detener k3s-agent si ya está en ejecución
if systemctl is-active --quiet k3s-agent 2>/dev/null; then
  echo "Deteniendo el agente k3s existente..."
  systemctl stop k3s-agent
  sleep 2
fi

echo "Token recibido, iniciando el agente k3s..."
curl -sfL https://get.k3s.io | \
  K3S_URL="https://${SERVER_IP}:6443" \
  K3S_TOKEN="$TOKEN" \
  sh -

# k3s-agent es iniciado automáticamente por el instalador, solo esperar a que esté listo
echo "Esperando a que el agente k3s esté listo..."
sleep 5

echo "Esperando a que el nodo se registre en el servidor..."
for i in $(seq 1 120); do
  if /usr/local/bin/k3s-agent kubectl get nodes 2>/dev/null | grep -q "$(hostname)"; then
    echo "Nodo registrado!"
    break
  fi
  if [ $((i % 20)) -eq 0 ]; then
    echo "Esperando a que el nodo se registre... ($i/120)"
  fi
  sleep 1
done

echo "Instalación completada del agente k3s"
