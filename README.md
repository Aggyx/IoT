# IoT Kubernetes Cluster with Vagrant and k3s

Jugando con máquinas con Vagrant, K8s, K3s y K3d.

## Inicio

Al empezar un proyecto con vagrant tenemos que escoger la imagen que deseamos utilizar. La elección debe ser una imagen pequeña que use pocos recursos.

**Primera Selección:** Alpine 3.24 (cloud-image/alpine-3.24)

**Selección actual:** Debian 13 (cloud-image/debian-13)

Cambio realizado porque Debian 13 ofrece mejor compatibilidad con k3s, mejor balance entre características y recursos, y comunidad más amplia para troubleshooting.

## Estructura del Vagrantfile

```
config
 ├── vm.box             → Qué imagen?
 ├── vm.hostname        → Qué hostname?
 ├── vm.network         → Como configuramos la red?
 ├── vm.provision       → Qué debemos virtualizar?
 ├── vm.synced_folder   → Qué volumen montamos?
 ├── vm.provider        → Cúantos recursos usamos?
 └── ssh                → Servicios de conexión?

 Vagrantfile
│
├── Global Configuration
│   ├── vm.box
│   ├── vm.synced_folder (.tokens para pipeline del token)
│   └── ssh.insert_key
│
├── gabriferS (Control Plane - k3s server)
│   ├── vm.define
│   ├── vm.hostname
│   ├── vm.network (192.168.56.110)
│   ├── vm.provider (1GB RAM, 1 CPU)
│   └── vm.provision (k3s server setup)
│
└── henriSW (Worker Node - k3s agent)
    ├── vm.define
    ├── vm.hostname
    ├── vm.network (192.168.56.111)
    ├── vm.provider (512MB RAM, 1 CPU)
    └── vm.provision (k3s agent setup)
```

## Directivas Vagrant Utilizadas

| Directiva | Propósito |
|-----------|-----------|
| config.vm.box | Imagen base de la VM |
| config.vm.define | Configuración multi-máquina |
| config.vm.hostname | Hostname del sistema huésped |
| config.vm.network | Configuración de red (privada 192.168.56.x) |
| config.vm.provision | Scripts de provisioning automatizado |
| config.vm.synced_folder | Sincronización de archivos host-guest |
| config.vm.provider | Configuración específica de VirtualBox |
| config.ssh.insert_key | Manejo de claves SSH |

## Flujo de Funcionamiento de Vagrant

```
up         → create/start
halt       → stop
reload     → reboot + apply VM config
provision  → run provisioning again
ssh        → enter VM
status     → inspect VM state
validate   → check Vagrantfile
destroy    → delete VM
```

## Arquitectura de Cluster k3s

```
┌─────────────────────────────────┐
│    gabriferS (Control Plane)    │
│  IP: 192.168.56.110             │
│  Memory: 1GB | CPU: 1           │
│  Role: k3s-server               │
│  Service: k3s.service           │
└────────────────┬────────────────┘
                 │
        ┌────────┴──────────────┐
        │  Token Pipeline       │
        │  (Synced Folder)      │
        │  Flannel Tunnel       │
        │  Network: 10.42.0.x   │
        │
┌────────────────┴─────────────────┐
│     henriSW (Worker Node)        │
│  IP: 192.168.56.111              │
│  Memory: 512MB | CPU: 1          │
│  Role: k3s-agent                 │
│  Service: k3s-agent.service      │
│  Network: 10.42.1.x              │
└──────────────────────────────────┘
```

## Proceso de Instalación k3s

### 1. Instalación del Control Plane (gabriferS - Servidor k3s)

El flujo de instalación del servidor k3s es el siguiente:

```bash
# 1. Configuración de Interfaz de Red
   ├── Detectar interfaz asociada a IP 192.168.56.110
   └── Configurar flannel-iface para networking de pods

# 2. Despliegue del Servidor k3s
   ├── Descargar binario oficial k3s desde GitHub
   ├── Verificar integridad del binario (checksum SHA256)
   ├── Crear servicio systemd: k3s.service
   └── Iniciar servicio explícitamente con systemctl restart k3s

# 3. Verificación de Disponibilidad de API Server
   ├── Polling /usr/local/bin/k3s kubectl get nodes (máx 180 intentos)
   └── Confirmar que API server responde antes de continuar

# 4. Generación del Token de Nodo
   ├── Esperar creación de /var/lib/rancher/k3s/server/node-token
   └── Copiar token a carpeta compartida (/tokens/node-token)

# 5. Verificación del Cluster
   └── Output de k3s kubectl get nodes -o wide (estado del nodo)
```

### 2. Instalación del Worker Node (henriSW - Agente k3s)

El flujo de instalación del agente k3s es el siguiente:

```bash
# 1. Configuración de Interfaz de Red
   ├── Detectar interfaz asociada a IP 192.168.56.111
   └── Crear config de k3s con node-ip y flannel-iface

# 2. Recuperación del Token
   ├── Esperar token desde el control plane (máx 180 intentos)
   ├── Montado en /tokens/node-token (carpeta sincronizada)
   └── Validar que archivo token existe y contiene datos

# 3. Despliegue del Agente k3s
   ├── Descargar binario k3s desde GitHub
   ├── Instalar con K3S_URL=https://192.168.56.110:6443
   ├── Instalar con K3S_TOKEN desde carpeta compartida
   ├── Crear servicio systemd: k3s-agent.service
   └── Instalador de k3s inicia k3s-agent automáticamente

# 4. Registro del Nodo
   ├── Esperar a que nodo se registre con el control plane
   ├── Polling al control plane (máx 120 intentos)
   └── Confirmar que estado del worker es Ready
```

## Configuración de Rancher/k3s

### Configuración del Servidor (/etc/rancher/k3s/config.yaml en gabriferS)

```yaml
node-ip: 192.168.56.110
flannel-iface: enp0s8
write-kubeconfig-mode: '644'
```

**Parámetros Clave:**
- `node-ip`: Vincula k3s a la interfaz de red privada (no a NAT)
- `flannel-iface`: Especifica interfaz de red para overlay network Flannel
- `write-kubeconfig-mode`: Permite acceso kubectl sin sudo

### Configuración del Agente (/etc/rancher/k3s/config.yaml en henriSW)

```yaml
node-ip: 192.168.56.111
flannel-iface: enp0s8
```

Ambos nodos deben especificar la interfaz correcta para habilitar comunicación pod-a-pod a través del tunel Flannel.

## Pipeline del Token - Mecanismo de Seguridad

El token de unión k3s habilita el registro seguro del nodo worker:

### Generación del Token (Nodo Servidor)
```
k3s server inicia → /var/lib/rancher/k3s/server/node-token creado
                  → Contiene: <server-hash>:<agent-secret>
                  → Utilizado para autenticación del agente
```

### Distribución del Token
```
Carpeta Compartida (/tokens) sincronizada por Vagrant
├── Host: .tokens/
└── Guest VM: /tokens/node-token (montado lectura-escritura)
```

### Consumo del Token (Nodo Worker)
```
Worker espera archivo token → Lee contenido del token
                            → Pasa a instalador k3s vía env var K3S_TOKEN
                            → Establece conexión HTTPS segura a server:6443
                            → Se registra con el control plane
```

### Detalles de Seguridad
- Token es específico de la instancia del cluster (generado en primer inicio del servidor)
- Tokens expiran después de 12 horas si el nodo no se conecta
- Validación HTTP/2 mutual TLS con certificados embebidos
- Token almacenado en /var/lib/rancher/k3s/server/node-token (permisos de archivo restringidos)

## Configuración de Networking

### Interfaces Físicas
- `enp0s3`: Interfaz NAT (solo-host, 10.0.2.x)
- `enp0s8`: Interfaz de red privada (192.168.56.x)

### Networking de Kubernetes (Flannel - Overlay Network)
- Service CIDR: 10.43.0.0/16 (default k3s)
- Pod CIDR: 10.42.0.0/16 dividido por nodo
  - Pods en control plane: 10.42.0.0/24
  - Pods en worker node: 10.42.1.0/24
- Encapsulación Flannel: UDP (configurable a VXLAN)
- Interfaz de tunel: flannel.1 (overlay virtual)

## Consideraciones de Performance

- Control plane: mínimo 1GB RAM (k3s requiere ~400MB + sistema)
- Worker node: 512MB RAM suficiente (k3s requiere ~250MB + sistema)
- Cada subred de pods: /24 (253 IPs utilizables por nodo)
- Overhead de Flannel: ~60 bytes por paquete
- Latencia API server: Sub-100ms en red local

## Comandos Operacionales

### Ver estado del cluster
```bash
vagrant ssh gabriferS -c "sudo k3s kubectl get nodes -o wide"
```

### Ver todos los pods
```bash
vagrant ssh gabriferS -c "sudo k3s kubectl get pods -A"
```

### Acceder al Control Plane
```bash
vagrant ssh gabriferS
```

### Acceder al Worker Node
```bash
vagrant ssh henriSW
```

### Ver logs de servicios
```bash
vagrant ssh gabriferS -c "sudo journalctl -u k3s -n 50"
vagrant ssh henriSW -c "sudo journalctl -u k3s-agent -n 50"
```

### Limpiar el cluster
```bash
vagrant destroy
```

## Troubleshooting

### Worker Node no se registra
- Verificar archivo token existe: `ls -la /tokens/node-token`
- Verificar conectividad de red: `ping 192.168.56.110` desde worker
- Revisar logs de k3s-agent: `sudo journalctl -u k3s-agent -n 100`
- Asegurar que API server está listo: `sudo k3s kubectl get nodes`

### Problemas de comunicación entre pods
- Verificar interfaz Flannel: `ip a show flannel.1`
- Chequear que node-ip coincide con output de `ip -4 a`
- Inspeccionar network policies: `sudo k3s kubectl get networkpolicies -A`

### Agotamiento de recursos
- Monitorear memoria: `free -h`
- Chequear procesos en ejecución: `ps aux | grep k3s`
- Habilitar logging verbose: `sudo systemctl status k3s -n 20`

## Referencias

[Documentación Oficial k3s](https://docs.k3s.io/)
[Rancher k3s GitHub](https://github.com/k3s-io/k3s)
[Documentación Vagrant](https://developer.hashicorp.com/vagrant/docs)
[Flannel Networking](https://github.com/flannel-io/flannel)
[Kubernetes Networking](https://kubernetes.io/docs/concepts/services-networking/)
[Setup de Networking k3s](https://docs.k3s.io/networking)

## Fuentes Originales

[Vagrantfile docs](https://developer.hashicorp.com/vagrant/docs/vagrantfile?utm_source=chatgpt.com)
[Vagrant tuto](https://developer.hashicorp.com/vagrant/tutorials/get-started)
[Provisioning](https://developer.hashicorp.com/vagrant/docs/provisioning)
[Shell Prov](https://developer.hashicorp.com/vagrant/docs/provisioning/shell)
[Multi-machine](https://developer.hashicorp.com/vagrant/docs/multi-machine)
[sources](https://developer.hashicorp.com/vagrant/docs/vagrantfile/machine_settings%23config-vm-hostname)