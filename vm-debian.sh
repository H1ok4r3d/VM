#!/usr/bin/env bash

# Script de création VM Debian 12 - Configuration Française
# Repository: https://github.com/H1ok4r3d/VM
# Auteur: H1ok4r3d
# License: MIT

# Mode debug si argument --debug
if [[ "$1" == "--debug" ]]; then
  set -x
  DEBUG=true
else
  DEBUG=false
fi

# Fonctions de messages
function header_info {
  clear
  cat <<"EOF"
   ____       _     _              ______              __      __  __  __ 
  / __ \___  | |__ (_) __ _ _ __   |  ____|             \ \    / / |  \/  |
 / / / / _ \ | '_ \| |/ _` | '_ \  | |__ _ __   __ _ _ __ \ \  / /  | |\/| |
/ /_/ /  __/ | |_) | | (_| | | | | |  __| '__| / _` | '_ \ \  / /   | |  | |
\____/ \___| |_.__/|_|\__,_|_| |_| |_|  |_|    \__,_| | | |  \/    |_|  |_|
                                                      |_| |_|               

        === Création VM Debian 12 - Configuration Française ===
                       Depuis GitHub Repository
EOF
}

YW="\033[33m"; BL="\033[36m"; RD="\033[01;31m"; BGN="\033[4;92m"; GN="\033[1;92m"; DGN="\033[32m"; CL="\033[m"; BOLD="\033[1m"
TAB="  "; CM="${TAB}✔️${TAB}${CL}"; CROSS="${TAB}❌${TAB}${CL}"; INFO="${TAB}💡${TAB}${CL}"; WARN="${TAB}⚠️${TAB}${CL}"

GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
DISK_SIZE="20G"
CORE_COUNT=$(nproc)
RAM_SIZE="2048"
HN="debian-fr"
TEMP_DIR=$(mktemp -d)

set -e
trap cleanup EXIT
function cleanup() { [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"; }

function msg_info() { echo -ne "${TAB}${YW}$1..."; }
function msg_ok()   { echo -e "\r${CM}${GN}$1${CL}"; }
function msg_error(){ echo -e "\r${CROSS}${RD}$1${CL}"; }
function msg_warn() { echo -e "${WARN}${YW}$1${CL}"; }

function check_root() {
  if [[ "$(id -u)" -ne 0 ]]; then msg_error "Ce script doit être exécuté en tant que root"; exit 1; fi
}

function check_dependencies() {
  msg_info "Vérification des dépendances"
  for cmd in curl pvesh qm pvesm; do command -v $cmd >/dev/null || { msg_error "$cmd manquant"; exit 1; }; done
  msg_ok "Toutes les dépendances sont présentes"
}

function get_valid_nextid() {
  local id=$(pvesh get /cluster/nextid)
  while [ -e "/etc/pve/qemu-server/${id}.conf" ]; do id=$((id+1)); done
  echo "$id"
}

function get_vm_settings() {
  header_info
  exec < /dev/tty
  default_vmid=$(get_valid_nextid)
  echo -n "ID de la VM (défaut: $default_vmid): "; read VMID; VMID=${VMID:-$default_vmid}
  echo -n "Nom d'hôte (défaut: debian-fr): "; read hostname_input; HN=${hostname_input:-debian-fr}; HN=${HN,,}
  echo -n "Bridge réseau (défaut: vmbr0): "; read bridge_input; BRG=${bridge_input:-vmbr0}

  echo "Stockages disponibles:"; mapfile -t STORAGES < <(pvesm status -content images | awk 'NR>1 {print $1}')
  for i in "${!STORAGES[@]}"; do echo "  $((i+1)). ${STORAGES[$i]}"; done
  echo -n "Choix (1-${#STORAGES[@]}, défaut: 1): "; read s; s=${s:-1}; STORAGE=${STORAGES[$((s-1))]}

  while true; do
    echo -n "Mot de passe root: "; read -s ROOT_PASSWORD; echo
    echo -n "Confirmer: "; read -s confirm; echo
    [[ "$ROOT_PASSWORD" == "$confirm" && ${#ROOT_PASSWORD} -ge 6 ]] && break || msg_error "Erreur de mot de passe"
  done

  echo -n "Taille disque (GB, défaut: 20): "; read d; DISK_SIZE="${d:-20}G"
  echo -e "\n${BGN}=== RÉSUMÉ DE LA CONFIGURATION ===${CL}"
  echo -e "ID VM: $VMID\nNom d'hôte: $HN\nBridge: $BRG\nStockage: $STORAGE\nTaille disque: $DISK_SIZE"
  echo -n "\nConfirmer ? (o/N): "; read confirm; [[ "$confirm" =~ ^[oO]$ ]] || exit 0
}

function download_debian_image() {
  msg_info "Téléchargement image Debian"
  local FILE="$TEMP_DIR/debian-12-genericcloud-amd64.qcow2"
  curl -fsSL -o "$FILE" "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2" || {
    msg_error "Échec du téléchargement"; exit 1; }
  msg_ok "Image téléchargée"
}

function create_vm() {
  msg_info "Création de la VM"
  local FILE="$TEMP_DIR/debian-12-genericcloud-amd64.qcow2"

  qm create $VMID -name $HN -memory $RAM_SIZE -cores $CORE_COUNT -net0 virtio,bridge=$BRG,macaddr=$GEN_MAC \
    -agent 1 -ostype l26 -scsihw virtio-scsi-pci -onboot 1 >/dev/null

  qm importdisk $VMID "$FILE" $STORAGE --format qcow2 >/dev/null

  IMPORTED_DISK=$(qm config $VMID | grep '^unused0:' | awk '{print $2}')
  if [ -z "$IMPORTED_DISK" ]; then
    msg_error "Aucun disque importé détecté"
    qm destroy $VMID --purge >/dev/null
    exit 1
  fi

  msg_info "Configuration du disque principal"
  qm set $VMID --scsi0 ${IMPORTED_DISK},discard=on,ssd=1 >/dev/null || {
    msg_error "Échec disque principal"; qm destroy $VMID --purge >/dev/null; exit 1; }

  qm set $VMID --ide2 ${STORAGE}:cloudinit >/dev/null
  qm set $VMID --boot order=scsi0 --serial0 socket >/dev/null
  msg_ok "VM créée avec l'ID: $VMID"
}

function configure_cloud_init() {
  msg_info "Configuration Cloud-init"
  qm set $VMID --ciuser root --cipassword "$ROOT_PASSWORD" --searchdomain local --nameserver 8.8.8.8 >/dev/null
  msg_ok "Cloud-init configuré"
}

function finalize_vm() {
  msg_info "Finalisation"
  qm resize $VMID scsi0 $DISK_SIZE >/dev/null 2>&1 || true
  DESCRIPTION="VM Debian 12
Créée via script GitHub
Utilisateur: root"
  qm set $VMID -description "$DESCRIPTION" >/dev/null
  msg_ok "Finalisation complète"
  echo -n "Démarrer la VM maintenant ? (o/N): "; read d; [[ "$d" =~ ^[oO]$ ]] && qm start $VMID && msg_ok "VM démarrée"
}

function main() {
  header_info
  check_root
  check_dependencies
  get_vm_settings
  download_debian_image
  create_vm
  configure_cloud_init
  finalize_vm
}

main "$@"
