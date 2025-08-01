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

# Variables de couleurs
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BOLD=$(echo "\033[1m")

# Variables d'icônes
TAB="  "
CM="${TAB}✔️${TAB}${CL}"
CROSS="${TAB}✖️${TAB}${CL}"
INFO="${TAB}💡${TAB}${CL}"
WARN="${TAB}⚠️${TAB}${CL}"

# Variables par défaut
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
DISK_SIZE="20G"
CORE_COUNT=$(nproc)
RAM_SIZE="2048"
ROOT_PASSWORD="root"
HN="debian-fr"
TEMP_DIR=$(mktemp -d)

set -e

# Nettoyage automatique
trap cleanup EXIT

function cleanup() {
  if [ -d "$TEMP_DIR" ]; then
    cd /
    rm -rf "$TEMP_DIR"
  fi
}

function msg_info() {
  local msg="$1"
  echo -ne "${TAB}${YW}${msg}..."
}

function msg_ok() {
  local msg="$1"
  echo -e "\r${CM}${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "\r${CROSS}${RD}${msg}${CL}"
}

function msg_warn() {
  local msg="$1"
  echo -e "${WARN}${YW}${msg}${CL}"
}

function check_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    msg_error "Ce script doit être exécuté en tant que root"
    exit 1
  fi
}

function check_dependencies() {
  msg_info "Vérification des dépendances"
  local missing_deps=()
  
  for cmd in curl pvesh qm pvesm; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing_deps+=("$cmd")
    fi
  done
  
  if [ ${#missing_deps[@]} -ne 0 ]; then
    msg_error "Dépendances manquantes: ${missing_deps[*]}"
    exit 1
  fi
  
  msg_ok "Dépendances vérifiées"
}

function pve_check() {
  msg_info "Vérification de Proxmox VE"
  
  if ! command -v pveversion >/dev/null 2>&1; then
    msg_error "Proxmox VE n'est pas détecté"
    exit 1
  fi
  
  msg_ok "Proxmox VE détecté"
}

function get_valid_nextid() {
  local try_id
  try_id=$(pvesh get /cluster/nextid)
  while true; do
    if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
      try_id=$((try_id + 1))
      continue
    fi
    break
  done
  echo "$try_id"
}

function get_vm_settings() {
  header_info
  exec < /dev/tty
  
  # ID de la VM
  local default_vmid=$(get_valid_nextid)
  while true; do
    echo -e "\n${INFO}${BOLD}Configuration de la VM${CL}\n"
    echo -n "ID de la VM (défaut: $default_vmid): "
    read VMID
    VMID=${VMID:-$default_vmid}
    
    if [[ ! "$VMID" =~ ^[0-9]+$ ]]; then
      msg_error "L'ID doit être un nombre"
      continue
    fi
    
    if [ -f "/etc/pve/qemu-server/${VMID}.conf" ] || [ -f "/etc/pve/lxc/${VMID}.conf" ]; then
      msg_error "L'ID $VMID est déjà utilisé"
      continue
    fi
    
    break
  done
  
  # Nom d'hôte
  echo -n "Nom d'hôte (défaut: debian-fr): "
  read hostname_input
  HN=${hostname_input:-debian-fr}
  HN=$(echo ${HN,,} | tr -d ' ')
  
  # Bridge réseau
  echo -e "\n${INFO}Bridges réseau disponibles:${CL}"
  ip link show | grep -E '^[0-9]+: vmbr[0-9]+' | awk -F': ' '{print "  - "$2}' | cut -d'@' -f1
  echo -n "Bridge réseau (défaut: vmbr0): "
  read bridge_input
  BRG=${bridge_input:-vmbr0}
  
  # Choix du stockage
  echo -e "\n${INFO}Stockages disponibles:${CL}"
  local STORAGE_LIST=()
  local storage_count=0
  
  while read -r line; do
    if [ $storage_count -eq 0 ]; then
      storage_count=1
      continue
    fi
    TAG=$(echo $line | awk '{print $1}')
    TYPE=$(echo $line | awk '{print $2}')
    AVAIL=$(echo $line | awk '{print $4}')
    TOTAL=$(echo $line | awk '{print $5}')
    
    AVAIL_HR=$(echo $AVAIL | numfmt --from-unit=K --to=iec --format %.1f 2>/dev/null || echo $AVAIL)
    TOTAL_HR=$(echo $TOTAL | numfmt --from-unit=K --to=iec --format %.1f 2>/dev/null || echo $TOTAL)
    
    echo -e "  $storage_count. ${BL}$TAG${CL} - Type: $TYPE - Libre: ${AVAIL_HR}B / ${TOTAL_HR}B"
    STORAGE_LIST+=("$TAG")
    ((storage_count++))
  done < <(pvesm status -content images)
  
  if [ ${#STORAGE_LIST[@]} -eq 0 ]; then
    msg_error "Aucun stockage disponible"
    exit 1
  elif [ ${#STORAGE_LIST[@]} -eq 1 ]; then
    STORAGE=${STORAGE_LIST[0]}
    echo -e "\n${INFO}Stockage sélectionné: ${BL}$STORAGE${CL}"
  else
    while true; do
      echo -n "Choisir le stockage (1-${#STORAGE_LIST[@]}, défaut: 1): "
      read storage_choice
      storage_choice=${storage_choice:-1}
      
      if [[ "$storage_choice" =~ ^[0-9]+$ ]] && [ "$storage_choice" -ge 1 ] && [ "$storage_choice" -le ${#STORAGE_LIST[@]} ]; then
        STORAGE=${STORAGE_LIST[$((storage_choice-1))]}
        break
      fi
      msg_error "Choix invalide"
    done
  fi
  
  # Taille du disque
  echo -e "\n${INFO}Configuration avancée:${CL}"
  echo -n "Taille du disque en GB (défaut: 20): "
  read disk_input
  DISK_SIZE="${disk_input:-20}G"
  
  # Résumé
  echo -e "\n${BGN}=== RÉSUMÉ ===${CL}"
  echo -e "ID VM: ${BL}$VMID${CL}"
  echo -e "Nom: ${BL}$HN${CL}"
  echo -e "Bridge: ${BL}$BRG${CL}"
  echo -e "Stockage: ${BL}$STORAGE${CL}"
  echo -e "Disque: ${BL}$DISK_SIZE${CL}"
  echo -e "CPU: ${BL}$CORE_COUNT cœurs${CL}"
  echo -e "RAM: ${BL}$RAM_SIZE MB${CL}"
  echo -e "Password: ${BL}root${CL}"
  
  echo -e "\n"
  echo -n "Créer la VM ? (o/N): "
  read confirm
  if [[ ! "$confirm" =~ ^[oO]$ ]]; then
    echo "Annulé"
    exit 0
  fi
}

function download_image() {
  msg_info "Téléchargement de l'image Debian 12"
  
  local URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
  local FILE="debian-12-genericcloud-amd64.qcow2"
  
  cd "$TEMP_DIR"
  
  if [ -f "$FILE" ]; then
    msg_ok "Image déjà présente"
    return
  fi
  
  if ! curl -fsSL -o "$FILE" "$URL"; then
    msg_error "Échec du téléchargement"
    exit 1
  fi
  
  msg_ok "Image téléchargée"
}

function create_vm() {
  msg_info "Création de la VM"
  
  # Création VM basique
  qm create $VMID \
    --agent 1 \
    --cores $CORE_COUNT \
    --memory $RAM_SIZE \
    --name "$HN" \
    --net0 virtio,bridge=$BRG,macaddr=$GEN_MAC \
    --ostype l26 \
    --scsihw virtio-scsi-pci >/dev/null 2>&1
  
  if [ $? -ne 0 ]; then
    msg_error "Échec création VM"
    exit 1
  fi
  
  msg_ok "VM créée"
}

function import_disk() {
  msg_info "Import du disque"
  
  local FILE="$TEMP_DIR/debian-12-genericcloud-amd64.qcow2"
  
  # Import avec capture de sortie
  local import_result
  import_result=$(qm importdisk $VMID "$FILE" $STORAGE --format qcow2 2>&1)
  
  if [ $? -ne 0 ]; then
    msg_error "Échec import disque"
    echo "Erreur: $import_result"
    qm destroy $VMID --purge >/dev/null 2>&1
    exit 1
  fi
  
  msg_ok "Disque importé"
  
  # Attendre que le disque soit disponible
  sleep 2
  
  # Déterminer le nom exact du disque créé
  local disk_name
  disk_name=$(pvesm list $STORAGE | grep "vm-${VMID}-disk" | awk '{print $1}' | head -1)
  
  if [ -z "$disk_name" ]; then
    msg_error "Disque importé non trouvé"
    echo "Disques disponibles dans $STORAGE:"
    pvesm list $STORAGE | grep -E "(vm-${VMID}|unused)"
    qm destroy $VMID --purge >/dev/null 2>&1
    exit 1
  fi
  
  msg_info "Configuration du disque ($disk_name)"
  
  # Essayer d'attacher le disque en SCSI0 d'abord
  if qm set $VMID --scsi0 "${disk_name}" >/dev/null 2>&1; then
    msg_ok "Disque configuré (SCSI)"
    # Définir l'ordre de boot
    qm set $VMID --boot order=scsi0 >/dev/null 2>&1
  # Sinon essayer en VirtIO
  elif qm set $VMID --virtio0 "${disk_name}" >/dev/null 2>&1; then
    msg_ok "Disque configuré (VirtIO)"
    # Définir l'ordre de boot
    qm set $VMID --boot order=virtio0 >/dev/null 2>&1
  # En dernier recours, essayer en IDE
  elif qm set $VMID --ide0 "${disk_name}" >/dev/null 2>&1; then
    msg_ok "Disque configuré (IDE)"
    qm set $VMID --boot order=ide0 >/dev/null 2>&1
  else
    msg_error "Échec configuration disque"
    echo "Impossible d'attacher le disque: $disk_name"
    echo "Configuration actuelle de la VM:"
    qm config $VMID
    qm destroy $VMID --purge >/dev/null 2>&1
    exit 1
  fi
}

function configure_vm() {
  msg_info "Configuration Cloud-init"
  
  # Déterminer le type de disque configuré
  local boot_device
  if qm config $VMID | grep -q "^scsi0:"; then
    boot_device="scsi0"
  elif qm config $VMID | grep -q "^virtio0:"; then
    boot_device="virtio0"
  elif qm config $VMID | grep -q "^ide0:"; then
    boot_device="ide0"
  else
    msg_error "Aucun disque de boot trouvé"
    exit 1
  fi
  
  # Cloud-init configuration
  qm set $VMID \
    --ciuser root \
    --cipassword "$ROOT_PASSWORD" \
    --serial0 socket \
    --boot order=$boot_device >/dev/null 2>&1
  
  if [ $? -ne 0 ]; then
    msg_error "Échec configuration cloud-init"
    exit 1
  fi
  
  # Redimensionner si nécessaire
  if [[ "$DISK_SIZE" != "20G" ]]; then
    msg_info "Redimensionnement disque vers $DISK_SIZE"
    if ! timeout 30 qm resize $VMID $boot_device $DISK_SIZE >/dev/null 2>&1; then
      msg_warn "Timeout ou échec redimensionnement"
    else
      msg_ok "Disque redimensionné"
    fi
  fi
  
  msg_ok "VM configurée"
}

function start_vm() {
  echo -e "\n"
  echo -n "Démarrer la VM ? (o/N): "
  read start_choice
  
  if [[ "$start_choice" =~ ^[oO]$ ]]; then
    msg_info "Démarrage VM"
    qm start $VMID
    sleep 3
    
    if qm status $VMID | grep -q "running"; then
      msg_ok "VM démarrée"
      
      echo -e "\n${BGN}=== SUCCÈS ===${CL}"
      echo -e "VM ID: ${BL}$VMID${CL}"
      echo -e "Nom: ${BL}$HN${CL}"
      echo -e "Console: ${BL}qm terminal $VMID${CL}"
      echo -e "Login: ${BL}root${CL} / ${BL}root${CL}"
    else
      msg_warn "Problème démarrage"
    fi
  else
    echo -e "\n${INFO}VM créée mais non démarrée${CL}"
    echo -e "Démarrer: ${BL}qm start $VMID${CL}"
  fi
}

function main() {
  header_info
  
  echo -e "\n${INFO}Création VM Debian 12 automatisée${CL}"
  echo -e "• CPU: ${BL}$(nproc) cœurs${CL}"
  echo -e "• RAM: ${BL}2048 MB${CL}"
  echo -e "• Login: ${BL}root/root${CL}"
  
  check_root
  check_dependencies  
  pve_check
  get_vm_settings
  download_image
  create_vm
  import_disk
  configure_vm
  start_vm
  
  echo -e "\n${CM}${GN}Terminé !${CL}\n"
}

main "$@"
