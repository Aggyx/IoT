# Vayamos más lejos !

Ahora vamos a configurar varios contenedores directamente dentro de nuestro servidor virtual
Vamos a usar el modulo incorporado de traefik proxy para enrutar la petición según el host al contenedor correcto.

## Configuración y arranque

El Vagrantfile define directamente la IP `192.168.56.110`, RAM
`2048` MB y `2` CPUs, y pasa la IP como argumento al script de
aprovisionamiento. El script conserva el puerto API predeterminado `6443`,
las rutas del token y el modo `644` del kubeconfig.
No se usan archivos de entorno y la carpeta `confs/` queda vacía.

La caja Debian 12 se importa, no se construye desde un Dockerfile.
Se fija `debian/bookworm64` a `12.20250126.1` para VirtualBox/amd64;
`12.20260519.1` solo está publicada para libvirt.
La URL configurada devuelve metadatos JSON de Vagrant.
HCP Vagrant [cerrará el 31 de diciembre de 2026](https://developer.hashicorp.com/hcp/docs/vagrant/hcp-vagrant-eol):
será necesario conservar/republicar la caja y sus metadatos antes del cierre.

```bash
# Requiere Vagrant y VirtualBox. Detén p1 primero: comparte la IP .110.
cd p1 && vagrant halt && cd ../p2
vagrant validate
vagrant box add debian/bookworm64 --box-version 12.20250126.1 --provider virtualbox
vagrant up gabriferS --provider=virtualbox
vagrant ssh gabriferS -c "sudo k3s kubectl get nodes -o wide"
```

El aprovisionamiento espera el CRD establecido, el rollout de Traefik
y los tres Deployments; después comprueba por HTTP los hosts app1/app2,
un host desconocido y la IP directa. Cualquier error aborta el script.
Para parámetros k3s usa `vagrant provision`; para IP/RAM/CPU,
`vagrant reload --provision`.

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
  config.vm.box = "debian/bookworm64"  # Imagen base del SO
  config.vm.box_url = "https://vagrantcloud.com/api/v2/vagrant/debian/bookworm64"
  config.vm.box_version = "12.20250126.1"

  # Servidor de p2
  config.vm.define "gabriferS" do |server|
    server.vm.hostname = "gabriferS"
    server.vm.network "private_network", ip: "192.168.56.110"
    server.vm.provider "virtualbox" do |vb|
      vb.memory = 2048
      vb.cpus = 2
    end
    server.vm.provision "shell",
      path: "scripts/provision-server.sh", args: ["192.168.56.110"]
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
   - El host puede acceder a las VMs mediante la red privada host-only de VirtualBox

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

### IngressRoute frente a Ingress oficial

La API oficial es **`networking.k8s.io/v1`**, no `networking.k8s.iot`.
Traefik es el controlador/proxy; `Ingress` e `IngressRoute` son dos
formas de configurarlo. k3s instala Traefik por defecto y puede procesar ambas.

| Aspecto | Ingress | IngressRoute |
|---------|---------|--------------|
| API | `networking.k8s.io/v1`, estable de Kubernetes | `traefik.io/v1alpha1`, CRD de Traefik |
| Dependencia | Requiere un controlador de Ingress | Requiere Traefik, sus CRDs y proveedor Kubernetes CRD |
| Reglas | Hosts, paths y `pathType` estándar | Expresiones Traefik como `Host()` y `PathPrefix()` |
| Prioridad | Sin campo estándar de prioridad numérica | `routes[].priority` explícita |
| Extensiones | Normalmente anotaciones específicas del controlador | Middlewares, entryPoints y servicios ponderados como campos/recursos |
| Portabilidad | Mayor para las reglas estándar; las anotaciones pueden limitarla | Acoplamiento a Traefik; migrar exige reescribir las rutas |
| Inspección | `kubectl get ingress` | `kubectl get ingressroutes.traefik.io` |

**Defensa de la estrategia actual:** el laboratorio ya usa Traefik integrado
en k3s. Sus CRDs permiten expresar directamente los hosts con prioridad
`100` y el fallback `PathPrefix('/')` con prioridad `1`, sin anotaciones
para controlar esa prioridad. La decisión favorece claridad y demostración
de las reglas del proxy, no mayor portabilidad.

**Límite importante:** para este caso sencillo, Ingress estándar también
puede expresar hosts y `spec.defaultBackend` para app3. IngressRoute no
es una necesidad técnica. Si el enunciado exige explícitamente un recurso
`kind: Ingress`, esta solución no cumple ese requisito y hay que cambiarla.
Si solo exige enrutamiento HTTP, demuestra el comportamiento y explica
la dependencia de Traefik. Kubernetes mantiene Ingress estable pero ha
congelado su API y recomienda Gateway API para nuevas funcionalidades;
eso no hace que IngressRoute sea la API oficial de reemplazo.

Ejemplo equivalente de Ingress estándar (solo referencia; no aplicarlo
junto a las IngressRoutes actuales para evitar routers duplicados):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: apps
spec:
  ingressClassName: traefik
  defaultBackend:
    service:
      name: app3
      port:
        number: 80
  rules:
    - host: app1.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app1
                port:
                  number: 80
    - host: app2.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app2
                port:
                  number: 80
```

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

# Muestra las reglas completas y sus prioridades
k3s kubectl get ingressroutes.traefik.io -n default -o yaml
k3s kubectl describe ingressroutes.traefik.io app1 -n default
k3s kubectl get crd ingressroutes.traefik.io
k3s kubectl get deployment traefik -n kube-system
k3s kubectl get svc traefik -n kube-system
k3s kubectl get deployment app1 app2 app3
k3s kubectl get endpointslices -l kubernetes.io/service-name=app2

# Es normal que esto no muestre las IngressRoutes: son otro tipo de recurso
k3s kubectl get ingress -A
```

Desde el host, sin modificar DNS ni `/etc/hosts`:

```bash
curl --fail --resolve app1.com:80:192.168.56.110 http://app1.com/ # app1
curl --fail --resolve app2.com:80:192.168.56.110 http://app2.com/ # app2
curl --fail -H 'Host: unknown.example' http://192.168.56.110/    # app3
curl --fail http://192.168.56.110/                             # app3
```

`--resolve` mantiene el host HTTP correcto y fuerza la conexión a la VM.
Abrir app1.com directamente sin DNS local puede contactar el sitio público,
no el clúster. Para mostrarlo en el navegador, configura localmente
`192.168.56.110 app1.com app2.com` en `/etc/hosts` y visita esos hosts.
Los tres pods de app2 se demuestran con el Deployment y sus EndpointSlices;
respuestas idénticas `app2` por sí solas no prueban balanceo entre réplicas.

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








