#!/usr/bin/env bash
# Temporary local acceptance harness. Delete this file before submission.
# Flow: Mac host -> one Debian VM -> deploy and test P2 inside that VM.
# No nested VM is created and the submitted p2/Vagrantfile is not changed.

set -Eeuo pipefail

readonly NODE_IP="192.168.56.110"
readonly VM_NAME="gabriferS"
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LAB_DIR="${P2_TEST_DIR:-${TMPDIR:-/tmp}/iot-p2-vagrant-test-${UID}}"
readonly MARKER="${LAB_DIR}/.iot-p2-validation-lab"
readonly HOST_OS="$(uname -s)"
readonly HOST_ARCH="$(uname -m)"
readonly LOG_FILE="${REPO_ROOT}/p2-local-test.log"

: >> "$LOG_FILE" || { printf 'Cannot write log file: %s\n' "$LOG_FILE" >&2; exit 1; }
exec > >(tee -a "$LOG_FILE") 2>&1
printf '\n===== P2 local test started: %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"

VM_ATTEMPTED=0
cleanup_on_exit() {
  local exit_status=$?
  trap - EXIT
  if (( exit_status != 0 )); then
    printf '\nFAIL: test exited with status %s\n' "$exit_status"
    if (( VM_ATTEMPTED )); then
      printf 'Cleaning up the disposable test VM...\n'
      if (cd "$LAB_DIR" && vagrant destroy -f "$VM_NAME"); then
        printf 'Test VM destroyed. Log retained at %s\n' "$LOG_FILE"
      else
        printf 'WARNING: automatic destroy failed. Check Vagrant/VirtualBox and run: (cd %q && vagrant destroy -f %s)\n' "$LAB_DIR" "$VM_NAME"
      fi
    fi
  fi
  printf '===== P2 local test ended: %s (exit %s) =====\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$exit_status"
  exit "$exit_status"
}
trap cleanup_on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

case "${HOST_OS}:${HOST_ARCH}" in
  Darwin:arm64|Darwin:aarch64)
    BOX_NAME="bento/debian-13"
    BOX_URL=""
    BOX_VERSION="${DEBIAN13_BOX_VERSION:-202510.26.0}"
    BOX_ARCH="arm64"
    GUEST_ARCH="arm64"
    ;;
  Darwin:x86_64)
    BOX_NAME="cloudsoe/debian-13"
    BOX_URL="https://boxes.cloudsoe.com/cloudsoe/debian-13.json"
    BOX_VERSION="${DEBIAN13_BOX_VERSION:-202611.15.0}"
    BOX_ARCH="amd64"
    GUEST_ARCH="amd64"
    ;;
  *)
    printf 'Unsupported Mac host: %s %s.\n' "$HOST_OS" "$HOST_ARCH" >&2
    exit 1
    ;;
esac

die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }
note() { printf '\n== %s ==\n' "$*"; }

for cmd in vagrant curl awk grep tar; do
  command -v "$cmd" >/dev/null 2>&1 || die "Missing required host command: $cmd"
done

if command -v VBoxManage >/dev/null 2>&1; then
  VBOXMANAGE="$(command -v VBoxManage)"
elif [[ -x /Applications/VirtualBox.app/Contents/MacOS/VBoxManage ]]; then
  VBOXMANAGE="/Applications/VirtualBox.app/Contents/MacOS/VBoxManage"
else
  die "VirtualBox is required. Install it and ensure VBoxManage is available."
fi

note "Mac host and prerequisites"
printf 'macOS: %s\n' "$(sw_vers -productVersion)"
printf 'Architecture: %s\n' "$HOST_ARCH"
printf 'Vagrant: %s\n' "$(vagrant --version)"
vagrant_version="$(vagrant --version | awk '{print $2}')"
if [[ "$BOX_ARCH" == arm64 ]]; then
  vagrant_major="${vagrant_version%%.*}"
  vagrant_rest="${vagrant_version#*.}"
  vagrant_minor="${vagrant_rest%%.*}"
  (( vagrant_major > 2 || (vagrant_major == 2 && vagrant_minor >= 4) )) ||
    die "ARM box selection requires Vagrant 2.4 or newer; found $vagrant_version."
fi

vbox_version="$("$VBOXMANAGE" --version)"
printf 'VirtualBox: %s\n' "$vbox_version"
if [[ "$BOX_ARCH" == arm64 ]]; then
  vbox_numeric="${vbox_version%%r*}"
  vbox_major="${vbox_numeric%%.*}"
  vbox_rest="${vbox_numeric#*.}"
  vbox_minor="${vbox_rest%%.*}"
  (( vbox_major > 7 || (vbox_major == 7 && vbox_minor >= 1) )) ||
    die "Apple Silicon requires VirtualBox 7.1+ for ARM64 guests; found $vbox_version."
fi

if ifconfig | grep -qE "[[:space:]]inet ${NODE_IP}[[:space:]]"; then
  die "${NODE_IP} is already assigned to a host interface. Stop the conflicting VM first."
fi
for project in p1 p2; do
  if [[ -f "$REPO_ROOT/$project/Vagrantfile" ]]; then
    project_status="$(cd "$REPO_ROOT/$project" && vagrant status --machine-readable 2>/dev/null || true)"
    grep -Eq ',state,running$' <<<"$project_status" &&
      die "A VM in $project is already running and uses ${NODE_IP}. Halt it first."
  fi
done

if [[ -e "$LAB_DIR" && ! -f "$MARKER" ]]; then
  [[ -z "$(find "$LAB_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]] ||
    die "Refusing to use non-empty unmarked directory $LAB_DIR. Set P2_TEST_DIR to a new path."
fi
mkdir -p "$LAB_DIR"
touch "$MARKER"

note "Prepare the isolated Debian VM"
BOX_URL_LINE=""
if [[ -n "$BOX_URL" ]]; then
  BOX_URL_LINE="  config.vm.box_url = \"${BOX_URL}\""
fi
cat > "$LAB_DIR/Vagrantfile" <<EOF
Vagrant.configure("2") do |config|
  config.vm.box = "${BOX_NAME}"
  config.vm.box_architecture = "${BOX_ARCH}"
${BOX_URL_LINE}
  config.vm.box_version = "${BOX_VERSION}"
  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.define "${VM_NAME}" do |server|
    server.vm.hostname = "${VM_NAME}"
    server.vm.network "private_network", ip: "${NODE_IP}"
    server.vm.provider "virtualbox" do |vb|
      vb.memory = 3072
      vb.cpus = 2
    end
    server.vm.provision "shell", name: "deploy-and-test-p2",
      path: "test-inside-vm.sh", args: ["${NODE_IP}", "${GUEST_ARCH}"]
  end
end
EOF

cat > "$LAB_DIR/test-inside-vm.sh" <<'GUEST_TEST'
#!/usr/bin/env bash
set -Eeuo pipefail

NODE_IP="${1:?node IP is required}"
EXPECTED_ARCH="${2:?guest architecture is required}"
P2_DIR=/tmp/p2-test/p2

die() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
note() { printf '\n== %s ==\n' "$*"; }
kubectl() { /usr/local/bin/k3s kubectl "$@"; }

note "Check Debian guest and update it to current stable packages"
. /etc/os-release
[[ "$ID" == debian && "$VERSION_CODENAME" == trixie ]] ||
  die "Expected Debian 13 Trixie; found ${PRETTY_NAME:-unknown}."
guest_arch="$(dpkg --print-architecture)"
[[ "$guest_arch" == "$EXPECTED_ARCH" ]] || die "Expected ${EXPECTED_ARCH}; found ${guest_arch}."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get install -y curl
latest_stable="$(curl --fail --silent --show-error --location \
  https://deb.debian.org/debian/dists/stable/Release |
  awk '$1 == "Version:" { print $2; exit }')"
guest_point="$(cat /etc/debian_version | tr -d '\r\n')"
[[ -n "$latest_stable" && "$guest_point" == "$latest_stable" ]] ||
  die "Debian guest is ${guest_point}; current stable repository is ${latest_stable:-unavailable}."
pass "Debian ${guest_point} (${guest_arch}) is current stable"

note "Deploy P2 using its real provisioning script"
[[ -x "$P2_DIR/scripts/provision-server.sh" || -f "$P2_DIR/scripts/provision-server.sh" ]] ||
  die "P2 provisioning script was not uploaded to $P2_DIR."
bash "$P2_DIR/scripts/provision-server.sh" "$NODE_IP"
pass "P2 provisioning script completed"

note "Check the node and Traefik controller"
kubectl wait --for=condition=Ready nodes --all --timeout=240s >/dev/null
kubectl rollout status deployment/traefik -n kube-system --timeout=240s >/dev/null
kubectl get ingressclass traefik >/dev/null
traefik_ports="$(kubectl get service traefik -n kube-system -o jsonpath='{.spec.ports[*].port}')"
grep -qw 80 <<<"$traefik_ports" || die "Traefik Service does not expose port 80: $traefik_ports"
pass "K3s node, Traefik Deployment, IngressClass, and HTTP service are ready"

note "Check all application Deployments and Services"
for app in app1 app2 app3; do
  kubectl rollout status "deployment/${app}" --timeout=240s >/dev/null
  kubectl get service "$app" >/dev/null
  endpoints="$(kubectl get endpoints "$app" -o jsonpath='{.subsets[0].addresses[*].ip}')"
  [[ -n "$endpoints" ]] || die "Service ${app} has no ready endpoints."
  pass "${app} is ready and has a Service endpoint"
done

for app in app1 app3; do
  replicas="$(kubectl get deployment "$app" -o jsonpath='{.spec.replicas} {.status.availableReplicas}')"
  [[ "$replicas" == "1 1" ]] || die "Expected ${app} desired/available replicas '1 1'; got '${replicas}'."
done
app2_replicas="$(kubectl get deployment app2 -o jsonpath='{.spec.replicas} {.status.availableReplicas}')"
[[ "$app2_replicas" == "3 3" ]] || die "Expected app2 desired/available replicas '3 3'; got '${app2_replicas}'."
app2_endpoints="$(kubectl get endpoints app2 -o jsonpath='{.subsets[0].addresses[*].ip}' | awk '{print NF}')"
[[ "$app2_endpoints" == 3 ]] || die "Expected 3 ready app2 endpoints; got ${app2_endpoints}."
pass "Replica counts are correct; app2 has 3 ready endpoints"

note "Check the standard Ingress resource and its routing rules"
ingress_class="$(kubectl get ingress apps -o jsonpath='{.spec.ingressClassName}')"
default_backend="$(kubectl get ingress app3-default -o jsonpath='{.spec.defaultBackend.service.name}')"
default_priority="$(kubectl get ingress app3-default -o jsonpath='{.metadata.annotations.traefik\.ingress\.kubernetes\.io/router\.priority}')"
hosts="$(kubectl get ingress apps -o jsonpath='{range .spec.rules[*]}{.host}{" "}{end}')"
[[ "$ingress_class" == traefik ]] || die "Ingress class should be traefik; got '${ingress_class}'."
[[ "$default_backend" == app3 ]] || die "Ingress default backend should be app3; got '${default_backend}'."
[[ "$default_priority" == 1 ]] || die "Fallback Ingress priority should be 1; got '${default_priority}'."
[[ " $hosts " == *" app1.com "* && " $hosts " == *" app2.com "* ]] ||
  die "Ingress host rules are incomplete: ${hosts}"
pass "Ingress routes app1/app2 hosts and low-priority default Ingress routes to app3"

note "Test HTTP host routing from inside the Debian VM"
assert_route() {
  local host="$1" path="$2" expected="$3" body
  body="$(curl --fail --silent --show-error --max-time 15 \
    --resolve "${host}:80:${NODE_IP}" "http://${host}${path}" | tr -d '\r\n')" ||
      die "HTTP request failed: host=${host}, path=${path}"
  [[ "$body" == "$expected"* ]] || die "${host}${path}: expected '${expected}', received '${body}'."
  pass "${host}${path} returns ${expected}"
}

assert_route app1.com / app1
assert_route app1.com /probe app1
assert_route app2.com / app2
assert_route unknown.example / app3
ip_body="$(curl --fail --silent --show-error --max-time 15 "http://${NODE_IP}/" | tr -d '\r\n')" ||
  die "Request to VM IP failed."
[[ "$ip_body" == app3* ]] || die "Direct IP request should select app3; received '${ip_body}'."
pass "Direct IP request returns app3"

note "P2 acceptance checks completed inside the VM"
kubectl get nodes -o wide
kubectl get deployments,services,ingress
kubectl get endpoints app1 app2 app3
GUEST_TEST
chmod +x "$LAB_DIR/test-inside-vm.sh"

(
  cd "$LAB_DIR"
  vagrant validate
)
pass "Temporary Vagrantfile validates; P2 source Vagrantfile is untouched"

note "Launch one Debian VM, transfer P2, then deploy and test inside it"
VM_ATTEMPTED=1
(
  cd "$LAB_DIR"
  vagrant up "$VM_NAME" --provider=virtualbox --no-provision
  tar -C "$REPO_ROOT" -czf "$LAB_DIR/p2-test.tar.gz" p2
  vagrant upload "$LAB_DIR/p2-test.tar.gz" /tmp/p2-test.tar.gz "$VM_NAME"
  vagrant ssh "$VM_NAME" -c 'sudo mkdir -p /tmp/p2-test && sudo tar -xzf /tmp/p2-test.tar.gz -C /tmp/p2-test'
  vagrant provision "$VM_NAME"
)

note "Verify requests from the Mac host to the VM"
assert_host_route() {
  local host="$1" expected="$2" body
  body="$(curl --fail --silent --show-error --max-time 15 \
    --resolve "${host}:80:${NODE_IP}" "http://${host}/" | tr -d '\r\n')" ||
      die "Mac-to-VM request failed for ${host}; check VirtualBox host-only networking."
  [[ "$body" == "$expected"* ]] || die "Mac request for ${host}: expected ${expected}, received '${body}'."
  pass "Mac host request ${host} returns ${expected}"
}
assert_host_route app1.com app1
assert_host_route app2.com app2
assert_host_route unknown.example app3

note "Result"
printf 'All checks passed. One Debian VM ran the P2 provisioning and acceptance checks.\n'
printf 'VM and files retained at: %s\n' "$LAB_DIR"
printf 'Inspect guest: (cd %q && vagrant ssh %s)\n' "$LAB_DIR" "$VM_NAME"
printf 'Destroy test VM when finished: (cd %q && vagrant destroy %s)\n' "$LAB_DIR" "$VM_NAME"
printf 'Complete run log: %s\n' "$LOG_FILE"
printf 'Delete this temporary harness before submission: %s\n' "$REPO_ROOT/test-p2-local.sh"
VM_ATTEMPTED=0
