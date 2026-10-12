#!/bin/bash
# Prov Script para k3s Control Plane (Servidor)
# Script de instalación y configuración del nodo maestro k3s
# Uso: ./provision-server.sh <NODE_IP>

set -eu

NODE_IP="$1"

# Recogemos la interfaz activa de manera dinamica para sacar siempre el nombre de la interfaz correcta asociada a la IP
IFACE=$(ip -o -4 addr show | awk '{print $2, $4}' | grep "$NODE_IP" | cut -d' ' -f1) && [ -n "$IFACE" ] || { echo "ERROR: no interface has IP $NODE_IP"; exit 1; }
echo "Usando interfaz $IFACE para $NODE_IP"

# Detener k3s si ya está en ejecución para asegurar un reinicio limpio
if systemctl is-active --quiet k3s 2>/dev/null; then
  echo "Deteniendo el servicio k3s existente..."
  systemctl stop k3s
  sleep 2
fi

# Crear directorio de configuración de rancher/k3s
mkdir -p /etc/rancher/k3s

# Generar archivo de configuración desde plantilla
cat > /etc/rancher/k3s/config.yaml <<EOF
node-ip: $NODE_IP
flannel-iface: $IFACE
write-kubeconfig-mode: '644'
EOF

echo "Instalando el servidor k3s..."
curl -sfL https://get.k3s.io | sh -s - server

# Explicitamente iniciar el servicio k3s
echo "Iniciando el servicio k3s..."
systemctl restart k3s
sleep 3

# Esperar a que la API esté completamente lista
echo "Esperando a que el servidor API de k3s esté listo (esto puede tardar 30-60 segundos)..."
for i in $(seq 1 180); do
  if /usr/local/bin/k3s kubectl get nodes &>/dev/null 2>&1; then
    echo "El servidor API está respondiendo correctamente"
    break
  fi
  if [ $((i % 10)) -eq 0 ]; then
    echo "Esperando... ($i/180 seconds)"
  fi
  sleep 1
done

echo "Esperando el archivo node-token..."
for i in $(seq 1 60); do
  if [ -f /var/lib/rancher/k3s/server/node-token ]; then
    echo "Node token encontrado!"
    break
  fi
  echo "Esperando el token... ($i/60)"
  sleep 1
done

if [ ! -f /var/lib/rancher/k3s/server/node-token ]; then
  echo "ERROR: TOKEN no encontrado"
  systemctl status k3s
  journalctl -u k3s -n 100
  exit 1
fi

# Copiar el token a la carpeta compartida para que los nodos worker puedan acceder a él
mkdir -p /tokens
cp /var/lib/rancher/k3s/server/node-token /tokens/node-token
chmod 644 /tokens/node-token
echo "Token copiado a /tokens/node-token"

echo ""
echo "Comprobando el clúster k3s..."
/usr/local/bin/k3s kubectl get nodes -o wide
echo "El nodo servidor está listo!"
