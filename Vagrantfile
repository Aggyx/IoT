# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
#Vagrant.configure("2") do |config|
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://vagrantcloud.com/search.
  #config.vm.box = "cloud-image/alpine-3.24"
  
  # Disable automatic box update checking. If you disable this, then
  # boxes will only be checked for updates when the user runs
  # `vagrant box outdated`. This is not recommended.
  # config.vm.box_check_update = false

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine. In the example below,
  # accessing "localhost:8080" will access port 80 on the guest machine.
  # NOTE: This will enable public access to the opened port
  # config.vm.network "forwarded_port", guest: 80, host: 8080

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine and only allow access
  # via 127.0.0.1 to disable public access
  # config.vm.network "forwarded_port", guest: 80, host: 8080, host_ip: "127.0.0.1"

  # Create a private network, which allows host-only access to the machine
  # using a specific IP.
  # config.vm.network "private_network", ip: "192.168.33.10"

  # Create a public network, which generally matched to bridged network.
  # Bridged networks make the machine appear as another physical device on
  # your network.
  # config.vm.network "public_network"

  # Share an additional folder to the guest VM. The first argument is
  # the path on the host to the actual folder. The second argument is
  # the path on the guest to mount the folder. And the optional third
  # argument is a set of non-required options.
  # config.vm.synced_folder "../data", "/vagrant_data"

  # Disable the default share of the current code directory. Doing this
  # provides improved isolation between the vagrant box and your host
  # by making sure your Vagrantfile isn't accessible to the vagrant box.
  # If you use this you may want to enable additional shared subfolders as
  # shown above.
  # config.vm.synced_folder ".", "/vagrant", disabled: true

  # Provider-specific configuration so you can fine-tune various
  # backing providers for Vagrant. These expose provider-specific options.
  # Example for VirtualBox:
  #
  # config.vm.provider "virtualbox" do |vb|
  #   # Display the VirtualBox GUI when booting the machine
  #   vb.gui = true
  #
  #   # Customize the amount of memory on the VM:
  #   vb.memory = "1024"
  # end
  #
  # View the documentation for the provider you are using for more
  # information on available options.

  # Enable provisioning with a shell script. Additional provisioners such as
  # Ansible, Chef, Docker, Puppet and Salt are also available. Please see the
  # documentation for more information about their specific syntax and use.
  # config.vm.provision "shell", inline: <<-SHELL
  #   apt-get update
  #   apt-get install -y apache2
  # SHELL
#end

# ================================================================================

Vagrant.configure("2") do |config|

  config.vm.box = "cloud-image/debian-13"


  # Por defecto, la carpeta actual no se comparte con la máquina virtual.
  # La carpeta .tokens se comparte para pasar el token de unión de k3s del servidor al agente.
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.synced_folder ".tokens", "/tokens", create: true

  # Reemplazar le par de llaves inseguro
  config.ssh.insert_key = true

  # ------------------------------------------------------------
  # Server — k3s CONTROL PLANE
  # ------------------------------------------------------------

  config.vm.define "gabriferS" do |server|

    server.vm.hostname = "gabriferS"

    server.vm.network "private_network", ip: "192.168.56.110" # definir IP estática para el servidor k3s

    server.vm.provider "virtualbox" do |vb|
      vb.memory = 1024 # Permitimos 1024 para el servidor k3s
      vb.cpus = 1
    end

    server.vm.provision "shell",
        name: "configure-server",
        args: ["192.168.56.110"], # le paso la IP del servidor k3s al script de provisión por qué no
        inline: <<~SHELL
          set -eu
          NODE_IP="$1"

          # Recogemos la interfaz activa de manera dinamica para sacar siempre el nombre de la interfaz correcta asociada a la IP
          IFACE=$(ip -o -4 addr show | awk '{print $2, $4}' | grep "$NODE_IP" | cut -d' ' -f1) && [ -n "$IFACE" ] || { echo "ERROR: no interface has IP $NODE_IP"; exit 1; }
          echo "##Usando interfaz $IFACE para $NODE_IP"

          # Detener k3s si ya está en ejecución para asegurar un reinicio limpio
          if systemctl is-active --quiet k3s 2>/dev/null; then
            echo "##Deteniendo el servicio k3s existente..."
            systemctl stop k3s
            sleep 2
          fi

          mkdir -p /etc/rancher/k3s
          cat > /etc/rancher/k3s/config.yaml <<EOF
          node-ip: $NODE_IP
          flannel-iface: $IFACE
          write-kubeconfig-mode: '644'
          EOF

          echo "##Instalando el servidor k3s..."
          curl -sfL https://get.k3s.io | sh -s - server

          # Explicitamente iniciar el servicio k3s
          echo "##Iniciando el servicio k3s..."
          systemctl restart k3s
          sleep 3

          # Esperar a que la API esté completamenta lista
          echo "##Esperando a que el servidor API de k3s esté listo (esto puede tardar 30-60 segundos)..."
          for i in $(seq 1 180); do
            if /usr/local/bin/k3s kubectl get nodes &>/dev/null 2>&1; then
              echo "## El servidor API está respondiendo correctamente"
              break
            fi
            if [ $((i % 10)) -eq 0 ]; then
              echo "##Esperando... ($i/180 seconds)"
            fi
            sleep 1
          done

          echo "##Esperando el archivo node-token..."
          for i in $(seq 1 60); do
            if [ -f /var/lib/rancher/k3s/server/node-token ]; then
              echo "## Node token encontrado!"
              break
            fi
            echo "##Esperando el token... ($i/60)"
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
          echo "## Token copiado a /tokens/node-token"

          echo ""
          echo "##Comprobando el clúster k3s..."
          /usr/local/bin/k3s kubectl get nodes -o wide
          echo "## El nodo servidor está listo!"
        SHELL
  end

  # ------------------------------------------------------------
  # ServerWorker — k3s agente
  # ------------------------------------------------------------

  config.vm.define "henriSW" do |serverworker|
    serverworker.vm.hostname = "henriSW"

    serverworker.vm.network "private_network", ip: "192.168.56.111"

    serverworker.vm.provider "virtualbox" do |vb|
      vb.memory = 512
      vb.cpus = 1
    end

    serverworker.vm.provision "shell",
      name: "configure-serverworker",
      args: ["192.168.56.111", "192.168.56.110"],
      inline: <<~SHELL
        set -eu
        NODE_IP="$1"
        SERVER_IP="$2"

        echo "Configuración del nodo worker: NODE_IP=$NODE_IP, SERVER_IP=$SERVER_IP"

        IFACE=$(ip -o -4 addr show | awk '{print $2, $4}' | grep "$NODE_IP" | cut -d' ' -f1)
        [ -n "$IFACE" ] || { echo "ERROR: no se encontró interfaz con IP $NODE_IP"; exit 1; }
        echo "##Usando interfaz $IFACE para $NODE_IP"

        mkdir -p /etc/rancher/k3s
        cat > /etc/rancher/k3s/config.yaml <<EOF
        node-ip: $NODE_IP
        flannel-iface: $IFACE
        EOF

        echo "##Esperando el token del servidor k3s desde $SERVER_IP..."
        for i in $(seq 1 180); do
          if [ -f /tokens/node-token ]; then
            echo "## Token encontrado!"
            break
          fi
          if [ $((i % 20)) -eq 0 ]; then
            echo "##Esperando el token... ($i/180)"
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

        # Detener k3s si ya está en ejecución
        if systemctl is-active --quiet k3s-agent 2>/dev/null; then
          echo "##Deteniendo el agente k3s existente..."
          systemctl stop k3s-agent
          sleep 2
        fi

        echo "##Token recibido, iniciando el agente k3s..."
        curl -sfL https://get.k3s.io | \
          K3S_URL="https://${SERVER_IP}:6443" \
          K3S_TOKEN="$TOKEN" \
          sh -

        echo "##Esperando a que el agente k3s esté listo..."
        sleep 5
        echo "##Esperando a que el nodo se registre en el servidor..."
        for i in $(seq 1 120); do
          if /usr/local/bin/k3s-agent kubectl get nodes 2>/dev/null | grep -q "$(hostname)"; then
            echo "##Nodo registrado!"
            break
          fi
          if [ $((i % 20)) -eq 0 ]; then
            echo "##Esperando a que el nodo se registre... ($i/120)"
          fi
          sleep 1
        done

        echo "##Instalación completada del agente k3s"
      SHELL
  end

end