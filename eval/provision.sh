#!/bin/bash
# Provisions the evaluation VM (Debian 13). Run as root by Vagrant.
#   provision.sh system <keyboard-layout>
#   provision.sh virtualization
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"

system_stage() {
    local layout="$1"

    apt-get update

    # grub-pc can ask where to install GRUB during a full upgrade.  In a
    # headless VirtualBox VM that prompt has no terminal and dpkg fails.
    # Select the physical disk containing the root filesystem automatically.
    ROOT_SOURCE="$(findmnt -n -o SOURCE /)"
    ROOT_DISK="$(lsblk -nps -o PKNAME "$ROOT_SOURCE" | tail -n1)"
    if [[ -z "$ROOT_DISK" || ! -b "$ROOT_DISK" ]]; then
        ROOT_DISK=""
        cat <<'EOF' | debconf-set-selections
grub-pc grub-pc/install_devices_empty boolean true
EOF
    else
        cat <<EOF | debconf-set-selections
grub-pc grub-pc/install_devices string $ROOT_DISK
grub-pc grub-pc/install_devices_empty boolean false
EOF
    fi

    apt-get -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" full-upgrade -y

    apt-get install -y \
        xfce4 xfce4-terminal lightdm firefox-esr \
        git curl ca-certificates gnupg jq rsync \
        linux-headers-amd64 build-essential

    # Since kernel 6.12, KVM grabs AMD-V/VT-x as soon as it is loaded,
    # and VirtualBox then refuses to start VMs. KVM is not used here.
    cat > /etc/modprobe.d/blacklist-kvm.conf <<'EOF'
blacklist kvm_amd
blacklist kvm_intel
EOF

    # Keyboard layout used by Xorg.
    sed -i "s/^XKBLAYOUT=.*/XKBLAYOUT=\"$layout\"/" /etc/default/keyboard

    # Log the vagrant user straight into the desktop.
    groupadd -f autologin
    usermod -aG autologin vagrant
    mkdir -p /etc/lightdm/lightdm.conf.d
    cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf <<'EOF'
[Seat:*]
autologin-user=vagrant
autologin-session=xfce
EOF
    systemctl set-default graphical.target
}

virtualization_stage() {
    install -d -m 0755 /etc/apt/keyrings

    curl -fsSL https://www.virtualbox.org/download/oracle_vbox_2016.asc \
        | gpg --dearmor --yes -o /etc/apt/keyrings/oracle-virtualbox.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/oracle-virtualbox.gpg] https://download.virtualbox.org/virtualbox/debian $CODENAME contrib" \
        > /etc/apt/sources.list.d/virtualbox.list

    curl -fsSL https://apt.releases.hashicorp.com/gpg \
        | gpg --dearmor --yes -o /etc/apt/keyrings/hashicorp.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $CODENAME main" \
        > /etc/apt/sources.list.d/hashicorp.list

    apt-get update
    apt-get install -y "linux-headers-$(uname -r)" virtualbox-7.2 vagrant
    usermod -aG vboxusers vagrant

    # The package builds the vboxdrv module; build it again if that failed.
    systemctl is-active --quiet vboxdrv || /sbin/vboxconfig

    if ! grep -qE 'svm|vmx' /proc/cpuinfo; then
        echo "WARNING: no AMD-V/VT-x in the VM, nested virtualization is off." >&2
        echo "         p1 and p2 will not start. Check --nested-hw-virt on the host." >&2
    fi

    VBoxManage --version
    vagrant --version
    df -h /
}

case "${1:-}" in
    system)         system_stage "${2:-us}" ;;
    virtualization) virtualization_stage ;;
    *)              echo "usage: $0 system <layout> | virtualization" >&2; exit 1 ;;
esac
