#!/usr/bin/env bash

# Script de création VM Debian 12 - Configuration Française
# Repository: https://github.com/H1ok4r3d/VM
# Auteur: H1ok4r3d
# License: MIT
# 
# Usage depuis GitHub:
# bash <(curl -fsSL https://raw.githubusercontent.com/H1ok4r3d/VM/main/vm-debian.sh)

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
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
DISK_SIZE="20G"
CORE_COUNT="2"
RAM_SIZE="2048"
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
    echo -e "\n${INFO}Utilisation depuis GitHub:${CL}"
    echo -e "  ${BL}curl -fsSL https://raw.githubusercontent.com/H1ok4r3d/VM/main/vm-debian.sh | sudo bash${CL}"
    echo -e "\nSortie..."
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
    echo -e "\n${INFO}Ce script doit être exécuté sur un serveur Proxmox VE${CL}"
    exit 1
  fi
  
  msg_ok "Toutes les dépendances sont présentes"
}

function pve_check() {
  msg_info "Vérification de Proxmox VE"
  
  if ! command -v pveversion >/dev/null 2>&1; then
    msg_error "Proxmox VE n'est pas détecté"
    exit 1
  fi
  
  local PVE_VER
  PVE_VER="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"
  
  if [[ "$PVE_VER" =~ ^8\.([0-9]+) ]] || [[ "$PVE_VER" =~ ^9\.([0-9]+) ]]; then
    msg_ok "Proxmox VE $PVE_VER détecté"
  else
    msg_error "Version Proxmox VE non supportée: $PVE_VER"
    echo -e "\n${INFO}Versions supportées: 8.x ou 9.x${CL}"
    exit 1
  fi
}

function check_internet() {
  msg_info "Vérification de la connexion Internet"
  
  if ! curl -fsSL --connect-timeout 5 https://cloud.debian.org >/dev/null 2>&1; then
    msg_error "Impossible de se connecter à Internet"
    echo -e "\n${INFO}Connexion Internet requise pour télécharger l'image Debian${CL}"
    exit 1
  fi
  
  msg_ok "Connexion Internet disponible"
}

function get_valid_nextid() {
  local try_id
  try_id=$(pvesh get /cluster/nextid)
  while true; do
    if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
      try_id=$((try_id + 1))
      continue
    fi
    if lvs --noheadings -o lv_name 2>/dev/null | grep -qE "(^|[-_])${try_id}($|[-_])"; then
      try_id=$((try_id + 1))
      continue
    fi
    break
  done
  echo "$try_id"
}

function get_vm_settings() {
  header_info
  
  # ID de la VM
  local default_vmid=$(get_valid_nextid)
  while true; do
    echo -e "\n${INFO}${BOLD}Configuration de la VM${CL}\n"
    
    read -p "ID de la VM (défaut: $default_vmid): " VMID
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
  read -p "Nom d'hôte (défaut: debian-fr): " hostname_input
  HN=${hostname_input:-debian-fr}
  HN=$(echo ${HN,,} | tr -d ' ')
  
  # Bridge réseau
  echo -e "\n${INFO}Bridges réseau disponibles:${CL}"
  if command -v ip >/dev/null 2>&1; then
    ip link show | grep -E '^[0-9]+: vmbr[0-9]+' | awk -F': ' '{print "  - "$2}' | cut -d'@' -f1
  else
    echo -e "  - vmbr0 (défaut)"
  fi
  read -p "Bridge réseau (défaut: vmbr0): " bridge_input
  BRG=${bridge_input:-vmbr0}
  
  # Validation du bridge
  if ! ip link show "$BRG" >/dev/null 2>&1; then
    msg_warn "Le bridge $BRG n'existe pas, mais on continue..."
  fi
  
  # Choix du stockage
  echo -e "\n${INFO}Stockages disponibles:${CL}"
  local STORAGE_LIST=()
  local storage_count=0
  
  while read -r line; do
    if [ $storage_count -eq 0 ]; then
      storage_count=1
      continue  # Skip header
    fi
    TAG=$(echo $line | awk '{print $1}')
    TYPE=$(echo $line | awk '{print $2}')
    USED=$(echo $line | awk '{print $3}')
    AVAIL=$(echo $line | awk '{print $4}')
    TOTAL=$(echo $line | awk '{print $5}')
    
    # Convertir en format lisible
    AVAIL_HR=$(echo $AVAIL | numfmt --from-unit=K --to=iec --format %.1f)
    TOTAL_HR=$(echo $TOTAL | numfmt --from-unit=K --to=iec --format %.1f)
    
    echo -e "  $storage_count. ${BL}$TAG${CL} - Type: $TYPE - Libre: ${AVAIL_HR}B / ${TOTAL_HR}B"
    STORAGE_LIST+=("$TAG")
    ((storage_count++))
  done < <(pvesm status -content images)
  
  if [ ${#STORAGE_LIST[@]} -eq 0 ]; then
    msg_error "Aucun stockage disponible pour les images VM"
    exit 1
  elif [ ${#STORAGE_LIST[@]} -eq 1 ]; then
    STORAGE=${STORAGE_LIST[0]}
    echo -e "\n${INFO}Stockage sélectionné automatiquement: ${BL}$STORAGE${CL}"
  else
    while true; do
      read -p "Choisir le stockage (1-${#STORAGE_LIST[@]}, défaut: 1): " storage_choice
      storage_choice=${storage_choice:-1}
      
      if [[ "$storage_choice" =~ ^[0-9]+$ ]] && [ "$storage_choice" -ge 1 ] && [ "$storage_choice" -le ${#STORAGE_LIST[@]} ]; then
        STORAGE=${STORAGE_LIST[$((storage_choice-1))]}
        break
      fi
      msg_error "Choix invalide. Entrez un nombre entre 1 et ${#STORAGE_LIST[@]}"
    done
  fi
  
  # Mot de passe root
  while true; do
    echo -e "\n${INFO}Configuration du mot de passe root${CL}"
    read -s -p "Mot de passe root: " ROOT_PASSWORD
    echo
    read -s -p "Confirmer le mot de passe: " ROOT_PASSWORD_CONFIRM
    echo
    
    if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONFIRM" ]; then
      if [ ${#ROOT_PASSWORD} -lt 6 ]; then
        msg_error "Le mot de passe doit contenir au moins 6 caractères"
        continue
      fi
      break
    else
      msg_error "Les mots de passe ne correspondent pas"
    fi
  done
  
  # Configuration avancée optionnelle
  echo -e "\n${INFO}Configuration avancée (optionnel)${CL}"
  read -p "Taille du disque en GB (défaut: 20): " disk_input
  DISK_SIZE="${disk_input:-20}G"
  
  read -p "Nombre de cœurs CPU (défaut: 2): " cpu_input
  CORE_COUNT=${cpu_input:-2}
  
  read -p "RAM en MB (défaut: 2048): " ram_input
  RAM_SIZE=${ram_input:-2048}
  
  # Résumé de la configuration
  echo -e "\n${BGN}=== RÉSUMÉ DE LA CONFIGURATION ===${CL}"
  echo -e "ID VM: ${BL}$VMID${CL}"
  echo -e "Nom d'hôte: ${BL}$HN${CL}"
  echo -e "Bridge: ${BL}$BRG${CL}"
  echo -e "Stockage: ${BL}$STORAGE${CL}"
  echo -e "Taille disque: ${BL}$DISK_SIZE${CL}"
  echo -e "CPU: ${BL}$CORE_COUNT cœurs${CL}"
  echo -e "RAM: ${BL}$RAM_SIZE MB${CL}"
  echo -e "MAC: ${BL}$GEN_MAC${CL}"
  echo -e "Langue: ${BL}Français${CL}"
  echo -e "Clavier: ${BL}Français${CL}"
  echo -e "Utilisateur: ${BL}Root uniquement${CL}"
  
  echo -e "\n"
  read -p "Confirmer la création de la VM ? (o/N): " confirm
  if [[ ! "$confirm" =~ ^[oO]$ ]]; then
    echo -e "\n${CROSS}Création annulée${CL}"
    exit 0
  fi
}

function select_storage() {
  # Cette fonction n'est plus nécessaire car le stockage est déjà sélectionné
  # dans get_vm_settings(), mais on la garde pour la compatibilité
  if [ -z "${STORAGE:-}" ]; then
    msg_error "Erreur: aucun stockage sélectionné"
    exit 1
  fi
  msg_ok "Stockage validé: $STORAGE"
}

function download_debian_image() {
  msg_info "Téléchargement de l'image Debian 12"
  
  local URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
  local FILE="debian-12-genericcloud-amd64.qcow2"
  
  cd "$TEMP_DIR"
  
  if [ -f "$FILE" ]; then
    msg_ok "Image déjà présente: $FILE"
    return
  fi
  
  if ! curl -fsSL -o "$FILE" "$URL"; then
    msg_error "Échec du téléchargement de l'image Debian"
    exit 1
  fi
  
  msg_ok "Image téléchargée: $FILE"
}

function create_vm() {
  msg_info "Création de la VM Debian 12"
  
  local FILE="$TEMP_DIR/debian-12-genericcloud-amd64.qcow2"
  
  # Déterminer le type de stockage
  local STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
  local DISK_EXT=".qcow2"
  local DISK_REF="$VMID/"
  local DISK_IMPORT="-format qcow2"
  
  case $STORAGE_TYPE in
    btrfs)
      DISK_EXT=".raw"
      DISK_IMPORT="-format raw"
      ;;
  esac
  
  local DISK0="vm-${VMID}-disk-0${DISK_EXT}"
  local DISK1="vm-${VMID}-disk-1${DISK_EXT}"
  local DISK0_REF="${STORAGE}:${DISK_REF}${DISK0}"
  local DISK1_REF="${STORAGE}:${DISK_REF}${DISK1}"
  
  # Création de la VM
  qm create $VMID \
    -agent 1 \
    -tablet 0 \
    -localtime 1 \
    -bios ovmf \
    -cores $CORE_COUNT \
    -memory $RAM_SIZE \
    -name $HN \
    -net0 virtio,bridge=$BRG,macaddr=$GEN_MAC \
    -onboot 1 \
    -ostype l26 \
    -scsihw virtio-scsi-pci
  
  # Allocation et import du disque
  pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
  qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT} 1>&/dev/null
  
  # Configuration des disques
  qm set $VMID \
    -efidisk0 ${DISK0_REF},efitype=4m \
    -scsi0 ${DISK1_REF},discard=on,ssd=1,size=${DISK_SIZE} \
    -scsi1 ${STORAGE}:cloudinit \
    -boot order=scsi0 \
    -serial0 socket >/dev/null
  
  msg_ok "VM créée avec l'ID: $VMID"
}

function configure_cloud_init() {
  msg_info "Configuration Cloud-init (français)"
  
  # Génération de la configuration utilisateur
  local USER_DATA=$(cat <<EOF
#cloud-config
locale: fr_FR.UTF-8
keyboard:
  layout: fr
timezone: Europe/Paris
package_upgrade: true
packages:
  - locales-all
  - keyboard-configuration
  - console-setup
ssh_pwauth: true
disable_root: false
chpasswd:
  list: |
    root:${ROOT_PASSWORD}
  expire: false
runcmd:
  - localectl set-locale LANG=fr_FR.UTF-8
  - localectl set-keymap fr
  - setupcon
  - dpkg-reconfigure -f noninteractive locales
  - dpkg-reconfigure -f noninteractive keyboard-configuration
  - systemctl restart systemd-logind
final_message: "VM Debian 12 configurée avec succès!"
EOF
)
  
  # Déterminer le répertoire des snippets
  local SNIPPET_DIR="/var/lib/vz/snippets"
  if [ "$STORAGE" != "local" ]; then
    local STORAGE_PATH=$(pvesm path ${STORAGE}: 2>/dev/null | head -n1)
    if [ -n "$STORAGE_PATH" ]; then
      SNIPPET_DIR="${STORAGE_PATH%/}/snippets"
    fi
  fi
  
  # Créer le répertoire si nécessaire
  mkdir -p "$SNIPPET_DIR"
  
  # Écriture du fichier user-data
  echo "$USER_DATA" > "${SNIPPET_DIR}/user-data-${VMID}.yml"
  
  # Application de la configuration Cloud-init
  qm set $VMID --cicustom "user=${STORAGE}:snippets/user-data-${VMID}.yml" >/dev/null
  
  msg_ok "Cloud-init configuré (français, root uniquement)"
}

function finalize_vm() {
  msg_info "Finalisation de la VM"
  
  # Redimensionnement du disque si nécessaire
  qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null 2>&1
  
  # Description de la VM
  local DESCRIPTION="VM Debian 12 - Configuration Française
Créée le: $(date '+%d/%m/%Y à %H:%M')
Script: https://github.com/H1ok4r3d/VM
Langue: Français
Clavier: Français  
Utilisateur: root uniquement"
  
  qm set "$VMID" -description "$DESCRIPTION" >/dev/null
  
  msg_ok "VM finalisée"
  
  # Demander si on démarre la VM
  echo -e "\n"
  read -p "Démarrer la VM maintenant ? (o/N): " start_vm
  if [[ "$start_vm" =~ ^[oO]$ ]]; then
    msg_info "Démarrage de la VM"
    qm start $VMID
    msg_ok "VM démarrée"
    
    echo -e "\n${BGN}=== VM CRÉÉE AVEC SUCCÈS ===${CL}"
    echo -e "ID: ${BL}$VMID${CL}"
    echo -e "Nom: ${BL}$HN${CL}"
    echo -e "Utilisateur: ${BL}root${CL}"
    echo -e "Console: ${BL}qm terminal $VMID${CL}"
    echo -e "\n${INFO}La VM va démarrer et configurer automatiquement le français.${CL}"
    echo -e "${INFO}Première connexion: utilisateur 'root' avec le mot de passe défini.${CL}"
  else
    echo -e "\n${BGN}VM créée mais non démarrée.${CL}"
    echo -e "Pour démarrer: ${BL}qm start $VMID${CL}"
  fi
}

function show_usage() {
  echo -e "\n${INFO}Usage depuis GitHub:${CL}"
  echo -e "  ${BL}curl -fsSL https://raw.githubusercontent.com/H1ok4r3d/VM/main/vm-debian.sh | bash${CL}"
  echo -e "\n${INFO}Ou en root:${CL}"
  echo -e "  ${BL}curl -fsSL https://raw.githubusercontent.com/H1ok4r3d/VM/main/vm-debian.sh | sudo bash${CL}"
}

function main() {
  header_info
  
  echo -e "\n${INFO}Ce script va créer une VM Debian 12 avec:${CL}"
  echo -e "  • Langue française par défaut"
  echo -e "  • Clavier français"
  echo -e "  • Utilisateur root uniquement"
  echo -e "  • Configuration Cloud-init automatique"
  
  echo -e "\n"
  read -p "Continuer ? (o/N): " continue_script
  if [[ ! "$continue_script" =~ ^[oO]$ ]]; then
    echo -e "\n${CROSS}Script annulé${CL}"
    show_usage
    exit 0
  fi
  
  check_root
  check_dependencies
  pve_check
  check_internet
  get_vm_settings
  select_storage
  
  download_debian_image
  create_vm
  configure_cloud_init
  finalize_vm
  
  echo -e "\n${CM}${GN}Création terminée avec succès!${CL}"
  echo -e "\n${INFO}Repository: ${BL}https://github.com/H1ok4r3d/VM${CL}\n"
}

# Lancement du script principal
main "$@"
