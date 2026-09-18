# IoT
Jugando con máquinas con Vagrant, K8s, K3s y K3d.

## Inicio

Al empezar un proyecto con vagrant tenemos que escoger la imagen que deseamos utilizar, el enunciado dice que tiene que ser una imagen pequeña que use pocos recursos, al comparar distribución alpine es la más ligera y su última versión es la 3.24, por suerte encontramos una vagrant box para esta distribución en "cloud-image/alpine-3.24".

## Estructura

config
 ├── vm.box             → Qué imagen?
 ├── vm.hostname        → Qué hostname?
 ├── vm.network         → Como configuramos la red?
 ├── vm.provision       → Qué debemos virtualizar?
 ├── vm.synced_folder   → Qué volumen montamos?
 ├── vm.provider        → Cúantos recursos usamos?
 └── ssh                → Servicios de conexión ?

 Vagrantfile
│
├── Vagrant directives
│   ├── vm.box
│   ├── vm.hostname
│   ├── vm.network
│   └── vm.provider
│
└── Provisioning
    └── Alpine commands
        ├── apk
        ├── rc-update
        └── rc-service

# Directivas 
config.vm.box	            Base VM image
config.vm.define	        Multi-machine environments
config.vm.hostname	        Guest hostname
config.vm.network	        NAT/private/public/forwarded networking
config.vm.provision	        Automated configuration
config.vm.synced_folder	    Host ↔ guest files
config.vm.provider	        VirtualBox-specific configuration
config.ssh.*	            Vagrant's SSH connection
config.vagrant.plugins	    Vagrant plugins
config.vm.post_up_message	Display useful information after up

# Flujo de funcionamiento de Vagrant
up         → create/start
halt       → stop
reload     → reboot + apply VM config
provision  → run provisioning again
ssh        → enter VM
status     → inspect VM state
validate   → check Vagrantfile
destroy    → delete VM

# Source
[Vagrantfile docs](https://developer.hashicorp.com/vagrant/docs/vagrantfile?utm_source=chatgpt.com)
[Vagrant tuto](https://developer.hashicorp.com/vagrant/tutorials/get-started)
[Provisioning](https://developer.hashicorp.com/vagrant/docs/provisioning)
[Shell Prov](https://developer.hashicorp.com/vagrant/docs/provisioning/shell)
[Multi-machine](https://developer.hashicorp.com/vagrant/docs/multi-machine)
[sources](https://developer.hashicorp.com/vagrant/docs/vagrantfile/machine_settings%23config-vm-hostname)