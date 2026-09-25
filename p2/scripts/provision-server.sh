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

# Copiar el token a la carpeta compartida para que los nodos worker puedan acceder a él aunque no tengamos nodos workers
mkdir -p /tokens
cp /var/lib/rancher/k3s/server/node-token /tokens/node-token
chmod 644 /tokens/node-token
echo "Token copiado a /tokens/node-token"

echo ""
echo "Comprobando el clúster k3s..."
/usr/local/bin/k3s kubectl get nodes -o wide
echo "El nodo servidor está listo!"

# Auto-deploy: k3s vigila el directorio de manifiestos
# y aplica/reconcilia todo lo que se coloque aquí.
MANIFEST_DIR=/var/lib/rancher/k3s/server/manifests/apps
mkdir -p "$MANIFEST_DIR"

# ---------------- app1 ----------------
# selector nos permite asociar el Service con los pods correctos mediante etiquetas
# template/metadata nos permite definir etiquetas y otras configuraciones para los pods generados por el Deployment
# El contenedor define la imagen y los argumentos que se ejecutarán dentro del pod
cat > "$MANIFEST_DIR/app1.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app1
spec:
  replicas: 1
  selector:
    matchLabels: { app: app1 }
  template:
    metadata:
      labels: { app: app1 }
    spec:
      containers:
        - name: app1
          image: hashicorp/http-echo:1.0
          args: ["-text", "app1", "-listen", ":5678"]
---
apiVersion: v1
kind: Service
metadata:
  name: app1
spec:
  selector: { app: app1 }
  ports:
    - port: 80
      targetPort: 5678
EOF

# ---------------- app2 (3 replicas redundantes) ----------------
cat > "$MANIFEST_DIR/app2.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app2
spec:
  replicas: 3            # three redundant copies
  selector:
    matchLabels: { app: app2 }
  template:
    metadata:
      labels: { app: app2 }
    spec:
      containers:
        - name: app2
          image: hashicorp/http-echo:1.0
          args: ["-text", "app2", "-listen", ":5678"]
---
apiVersion: v1
kind: Service
metadata:
  name: app2
spec:
  selector: { app: app2 }
  ports:
    - port: 80
      targetPort: 5678
EOF

# ---------------- app3 (default) ----------------
cat > "$MANIFEST_DIR/app3.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app3
spec:
  replicas: 1
  selector:
    matchLabels: { app: app3 }
  template:
    metadata:
      labels: { app: app3 }
    spec:
      containers:
        - name: app3
          image: hashicorp/http-echo:1.0
          args: ["-text", "app3", "-listen", ":5678"]
---
apiVersion: v1
kind: Service
metadata:
  name: app3
spec:
  selector: { app: app3 }
  ports:
    - port: 80
      targetPort: 5678
EOF

echo "Esperando a que Traefik se inicialice (puede tardar más de 60 segundos)..."
for i in $(seq 1 300); do
  if k3s kubectl get crd ingressroutes.traefik.io &>/dev/null 2>&1; then
    echo "Los CRD de Traefik están listos"
    break
  fi
  if [ $((i % 30)) -eq 0 ]; then
    echo "Esperando a los CRD de Traefik... ($i/300 segundos)"
  fi
  sleep 1
done

¡echo "Esperando a que los pods de Traefik se levanten..."
for i in $(seq 1 120); do
  TRAEFIK_READY=$(k3s kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -c Running || true)
  if [ "$TRAEFIK_READY" -gt 0 ]; then
    echo "Traefik corriendo"
    break
  fi
  if [ $((i % 20)) -eq 0 ]; then
    echo "Esperando a los pods de Traefik... ($i/120 segundos)"
  fi
  sleep 1
done

# ---------------- Enrutamiento de Traefik basado en host ----------------
cat > "$MANIFEST_DIR/ingress.yaml" <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: app1
  namespace: default
spec:
  entryPoints: [web]
  routes:
    - match: Host(`app1.com`)
      kind: Rule
      priority: 100
      services:
        - name: app1
          port: 80
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: app2
  namespace: default
spec:
  entryPoints: [web]
  routes:
    - match: Host(`app2.com`)
      kind: Rule
      priority: 100
      services:
        - name: app2
          port: 80
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: app3-default
  namespace: default
spec:
  entryPoints: [web]
  routes:
    - match: PathPrefix(`/`)
      kind: Rule
      priority: 1            # lowest priority = fallback
      services:
        - name: app3
          port: 80
EOF

echo "Aplicando manifiestos..."
k3s kubectl apply -f "$MANIFEST_DIR/app1.yaml"
k3s kubectl apply -f "$MANIFEST_DIR/app2.yaml"
k3s kubectl apply -f "$MANIFEST_DIR/app3.yaml"
k3s kubectl apply -f "$MANIFEST_DIR/ingress.yaml"

echo ""
echo "Esperando a que los pods se levanten..."
sleep 30

echo ""
echo "Estado de los Pods:"
k3s kubectl get pods -A

echo ""
echo "Estado de los IngressRoute:"
k3s kubectl get ingressroute -A

echo ""
echo "Cluster levantado!"