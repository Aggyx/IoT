# Vayamos más lejos !

Ahora vamos a configurar varios contenedores directamente dentro de nuestro servidor virtual
Vamos a usar el modulo incorporado de traefik proxy para enrutar la petición según el host al contenedor correcto.

# Guía de Arquitectura Vagrant + k3s

## Descripción General de la Arquitectura de Composición

Patrón de Kubernetes cluster-as-code usando Vagrant para orquestar la infraestructura como código y k3s como la distribución Kubernetes ligera.

### Comparación de Proyectos: p1 vs p2

| Aspecto | p1 | p2 |
|--------|-----|-----|
| **Nodos** | 2 (Servidor + Worker) | 1 (Solo Servidor) |
| **Complejidad** | Alta (configuración distribuida) | Baja (nodo único) |
| **Caso de Uso** | Prueba multi-nodo similar a producción | Desarrollo y prueba de despliegues simples |
| **Aplicaciones** | Gestionadas por separado (no en script) | Auto-desplegadas vía manifiestos |
| **Compartición de Token** | Sincronización de carpeta `.tokens/node-token` | No necesario |

---

## Comprensión de la Estructura de Vagrantfile

```ruby
Vagrant.configure("2") do |config|    # DSL Ruby para configuración de VM
  config.vm.box = "cloud-image/debian-13"  # Imagen base del SO

  # Máquina 1: Servidor
  config.vm.define "gabriferS" do |server|
    server.vm.hostname = "gabriferS"
    server.vm.network "private_network", ip: "192.168.56.110"
    server.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
    end
    server.vm.provision "shell", path: "scripts/provision-server.sh"
  end

  # Máquina 2: Worker (solo p1)
  config.vm.define "smagninySW" do |worker|
    # Estructura similar con IP diferente
  end
end
```

### Conceptos Clave:

**1. `config.vm.define`** crea configuraciones separadas de VM
   - Cada bloque se convierte en una máquina independiente
   - Se puede referenciar la configuración de otras máquinas definidas

**2. `config.vm.network`** es la configuración de red
   ```ruby
   "private_network", ip: "192.168.56.110"  # Red interna, IP fija
   ```
   - Las máquinas se comunican a través de esta red privada
   - El host no puede acceder directamente a las VMs en esta red

**3. `config.vm.provider`** es la configuración del hipervisor (VirtualBox aquí)
   ```ruby
   vb.memory = 1024    # RAM en MB
   vb.cpus = 1         # Núcleos de CPU
   ```

**4. `config.vm.synced_folder`** comparte directorios entre el host y la VM
   - p1 sincroniza la carpeta `.tokens` para compartir el token de nodo k3s
   - p2 desactiva la sincronización por defecto
   ```ruby
   config.vm.synced_folder ".tokens", "/tokens", create: true
   ```

**5. `config.vm.provision`** ejecuta scripts durante `vagrant up`
   - Se ejecutan en el orden definido
   - Pueden fallar en el aprovisionamiento completo si el script sale con error

---

## Configuración de Proxy e Ingress (Traefik)

### Diagrama de Capa de Arquitectura

```
Capa 1: CONTROLADOR DE INGRESS TRAEFIK
        Escucha en puerto 80 internamente

Capa 2: Reglas de Enrutamiento (Host / Ruta)
        Host app1.com
        Host app2.com
        Ruta /* (predeterminado)

Capa 3: Servicios
        Servicio app1 en puerto 80
        Servicio app2 en puerto 80
        Servicio app3 en puerto 80

Capa 4: Pods
        1 réplica para app1
        3 réplicas para app2 (redundancia)
        1 réplica para app3
```

### Cómo Funciona el Enrutamiento de Traefik

**Recursos de Kubernetes involucrados:**
1. **Deployments** - Define pods y réplicas
2. **Services** - Expone pods con una IP estable (ClusterIP)
3. **IngressRoute** - Regla de enrutamiento personalizada de Traefik

**Flujo de solicitudes:**
```
Solicitud: GET http://app1.com/
Paso 1: Traefik escuchando en puerto 80
Paso 2: Coincide Host app1.com con prioridad 100
Paso 3: Reenvía a Servicio app1 en puerto 80
Paso 4: El Servicio selecciona pod con etiqueta app: app1
Paso 5: Contenedor del pod escucha en puerto 5678
Paso 6: Respuesta devuelta
```

### Sistema de Prioridades

```yaml
app1.com     prioridad 100  se verifica primero
app2.com     prioridad 100  se verifica primero
/* default   prioridad 1    alternativa más baja
```

Cuando llega una solicitud:
- Se verifican todas las reglas con prioridad más alta primero
- Si hay coincidencia, se enruta
- Si no hay coincidencia, se intenta el siguiente nivel de prioridad
- El capturador predeterminado es la prioridad 1

---

## Problemas Solucionados en la Configuración

### Problema 1: Incrementar memoria y vCPU
### Problema 2: CRD de Traefik No Está Listo

**Lo que estaba sucediendo:**
```
k3s kubectl get ingressroute  
Error: el servidor no tiene el tipo de recurso "ingressroute"
```

**Por qué:** Traefik se instala vía Helm y registra su Definición de Recurso Personalizado (IngressRoute). Esto tarda tiempo. El script verificaba antes de que estuviera listo.

**Solución** Esperar a que esté listo


## Mejores Prácticas Aplicadas

### 1. **Scripts Defensivos**
```bash
set -eu  # Salir en error, error en variables indefinidas
# Siempre verificar precondiciones antes de proceder
if [ ! -f /var/lib/rancher/k3s/server/node-token ]; then
  echo "ERROR: TOKEN no encontrado"
  exit 1
fi
```

### 2. **Descubrimiento Dinámico**
```bash
# No codificar nombres de interfaz; descubrirlos
IFACE=$(ip -o -4 addr show | awk '{print $2, $4}' | grep "$NODE_IP" | cut -d' ' -f1)
```

### 3. **Esperar Dependencias**
```bash
# Usar bucles de sondeo con verificaciones explícitas
for i in $(seq 1 300); do
  if k3s kubectl get crd ingressroutes.traefik.io &>/dev/null 2>&1; then
    break
  fi
  sleep 1
done
```

### 4. **Aplicación Explícita de Manifiestos**
```bash
# No confiar solo en auto-despliegue; aplicar explícitamente
k3s kubectl apply -f "$MANIFEST_DIR/ingress.yaml"
```

### 5. **Verificación de Estado**
```bash
echo "Estado de Pods:"
k3s kubectl get pods -A

echo "Estado de IngressRoute:"
k3s kubectl get ingressroute -A
```

## Pruebas de la Configuración

```bash
# Inicia el clúster
cd p2
vagrant up gabriferS

# SSH en él
vagrant ssh gabriferS

# Prueba el enrutamiento
sudo -i

# Verifica servicios
k3s kubectl get svc
# app1    ClusterIP 10.43.x.x  80/TCP
# app2    ClusterIP 10.43.x.x  80/TCP
# app3    ClusterIP 10.43.x.x  80/TCP

# Verifica ingressroutes
k3s kubectl get ingressroute
# NAME           AGE
# app1           30s
# app2           30s
# app3-default   30s

# Prueba desde dentro del pod de Traefik
k3s kubectl exec -it deployment/traefik -n kube-system -- /bin/sh
# curl http://app1.com/
# curl http://app2.com/
# curl http://app3.local/
```

---

## Resumen

| Concepto | Qué es | Por qué |
|---------|--------|--------|
| **Vagrantfile** | Infraestructura como código para VMs | Configuración reproducible y portátil |
| **k3s** | Kubernetes ligero | Aprovisionamiento rápido, bajo uso de recursos |
| **Traefik** | Controlador de ingress (proxy) | Enrutar tráfico HTTP a servicios |
| **IngressRoute** | Recurso personalizado de Traefik | Definir reglas de enrutamiento (Host/Ruta) |
| **Services** | Punto de acceso estable para pods | Los pods son efímeros; Services proporcionan DNS |
| **Deployments** | Gestionar réplicas de pods | Garantizar número deseado de pods en ejecución |
| **Synced Folders** | Compartir directorios host-VM | Compartir token, sincronizar código |
| **Provisioning** | Ejecutar scripts de configuración | Instalar k3s, desplegar apps, configurar red |

# Fuentes
[Referencia API (todos los campos, todas las versiones)](https://kubernetes.io/docs/reference/kubernetes-api/)
[Conceptos básicos de cargas de trabajo](https://kubernetes.io/docs/concepts/workloads/)
[Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
[Deployments](https://kubernetes.io/docs/concepts/workloads/deployments/)
[Services](https://kubernetes.io/docs/concepts/services-networking/service/)
[Conceptos de Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
[Hoja de trucos YAML / estructura explicada](https://kubernetes.io/docs/concepts/overview/working-with-objects/kubernetes-objects/)
[Auto-despliegue de manifiestos k3s](https://docs.k3s.io/installation/k3s-install#auto-deploying-manifests) (también página [Add-On y Manifiestos](https://docs.k3s.io/helm))
[CRD de IngressRoute de Traefik](https://doc.traefik.io/traefik/providers/kubernetes-crd/)
[Internos de Service y kube-proxy](https://kubernetes.io/docs/concepts/services-networking/service/#virtual-ips-and-service-proxies)
[Endpoints/EndpointSlice](https://kubernetes.io/docs/concepts/services-networking/endpoints/)
[ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)











