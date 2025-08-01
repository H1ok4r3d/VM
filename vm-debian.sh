#!/usr/bin/env bash

# Script de création VM Debian 12 - Configuration Française
# Repository: https://github.com/H1ok4r3d/VM
# Auteur: H1ok4r3d
# License: MIT
# 
# Usage depuis GitHub:
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/H1ok4r3d/VM/main/vm-debian.sh)"

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
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
DISK_SIZE="20G"
CORE_COUNT=$(nproc)  # Utilise tous les cœurs disponibles
RAM_SIZE="2048"      # 2048 MB par défaut
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
  
  # Rediriger vers /dev/tty pour les interactions
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
  if command -v ip >/dev/null 2>&1; then
    ip link show | grep -E '^[0-9]+: vmbr[0-9]+' | awk -F': ' '{print "  - "$2}' | cut -d'@' -f1
  else
    echo -e "  - vmbr0 (défaut)"
  fi
  echo -n "Bridge réseau (défaut: vmbr0): "
  read bridge_input
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
      echo -n "Choisir le stockage (1-${#STORAGE_LIST[@]}, défaut: 1): "
      read storage_choice
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
    echo -n "Mot de passe root: "
    read -s ROOT_PASSWORD
    echo
    echo -n "Confirmer le mot de passe: "
    read -s ROOT_PASSWORD_CONFIRM
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
  echo -n "Taille du disque en GB (défaut: 20): "
  read disk_input
  DISK_SIZE="${disk_input:-20}G"
  
  # Résumé de la configuration
  echo -e "\n${BGN}=== RÉSUMÉ DE LA CONFIGURATION ===${CL}"
  echo -e "ID VM: ${BL}$VMID${CL}"
  echo -e "Nom d'hôte: ${BL}$HN${CL}"
  echo -e "Bridge: ${BL}$BRG${CL}"
  echo -e "Stockage: ${BL}$STORAGE${CL}"
  echo -e "Taille disque: ${BL}$DISK_SIZE${CL}"
  echo -e "CPU: ${BL}$CORE_COUNT cœurs (maximum disponible)${CL}"
  echo -e "RAM: ${BL}$RAM_SIZE MB${CL}"
  echo -e "MAC: ${BL}$GEN_MAC${CL}"
  echo -e "BIOS: ${BL}SeaBIOS (défaut)${CL}"
  echo -e "Langue: ${BL}Français${CL}"
  echo -e "Clavier: ${BL}Français${CL}"
  echo -e "Utilisateur: ${BL}Root uniquement${CL}"
  
  echo -e "\n"
  echo -n "Confirmer la création de la VM ? (o/N): "
  read confirm
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
  
  # Création de la VM avec BIOS par défaut (SeaBIOS)
  qm create $VMID \
    -agent 1 \
    -tablet 0 \
    -localtime 1 \
    -cores $CORE_COUNT \
    -memory $RAM_SIZE \
    -name $HN \
    -net0 virtio,bridge=$BRG,macaddr=$GEN_MAC \
    -onboot 1 \
    -ostype l26 \
    -scsihw virtio-scsi-pci
  
  if [ $? -ne 0 ]; then
    msg_error "Échec de la création de la VM"
    exit 1
  fi
  
  # Import du disque avec gestion d'erreur
  msg_info "Import du disque système"
  if ! qm importdisk $VMID "${FILE}" $STORAGE --format qcow2 >/dev/null 2>&1; then
    msg_error "Échec de l'import du disque"
    qm destroy $VMID --purge >/dev/null 2>&1
    exit 1
  fi
  
  # Attacher le disque importé
  msg_info "Configuration du disque principal"
  if ! qm set $VMID --scsi0 ${STORAGE}:vm-${VMID}-disk-0,discard=on,ssd=1 >/dev/null 2>&1; then
    msg_error "Échec de la configuration du disque principal"
    qm destroy $VMID --purge >/dev/null 2>&1
    exit 1
  fi
  
  # Ajouter le disque Cloud-init
  msg_info "Configuration Cloud-init"
  if ! qm set $VMID --ide2 ${STORAGE}:cloudinit >/dev/null 2>&1; then
    msg_error "Échec de la configuration Cloud-init"
    qm destroy $VMID --purge >/dev/null 2>&1
    exit 1
  fi
  
  # Configuration du boot et série
  qm set $VMID \
    --boot order=scsi0 \
    --serial0 socket >/dev/null 2>&1
  
  msg_ok "VM créée avec l'ID: $VMID"
}

function configure_cloud_init() {
  msg_info "Configuration Cloud-init (français)"
  
  # Configuration Cloud-init basique sans fichier personnalisé
  qm set $VMID \
    --ciuser root \
    --cipassword "$ROOT_PASSWORD" \
    --searchdomain local \
    --nameserver 8.8.8.8 >/dev/null 2>&1
  
  # Création d'un script de post-installation pour la localisation
  local SNIPPET_DIR="/var/lib/vz/snippets"
  mkdir -p "$SNIPPET_DIR"
  
  # Script de post-installation pour configurer le français
  local POST_INSTALL_SCRIPT="${SNIPPET_DIR}/post-install-${VMID}.sh"
  
  cat > "$POST_INSTALL_SCRIPT" << 'EOF'
#!/bin/bash
# Script de post-installation pour configuration française

# Configuration locale
export DEBIAN_FRONTEND=noninteractive

# Installation des paquets nécessaires
apt-get update -q
apt-get install -y locales keyboard-configuration console-setup locales-all

# Configuration locale française
sed -i '/^# fr_FR.UTF-8 UTF-8/s/^# //' /etc/locale.gen
locale-gen
update-locale LANG=fr_FR.UTF-8 LC_ALL=fr_FR.UTF-8

# Configuration clavier français
echo 'XKBLAYOUT="fr"' > /etc/default/keyboard
echo 'XKBVARIANT=""' >> /etc/default/keyboard
echo 'XKBOPTIONS=""' >> /etc/default/keyboard

# Configuration console
echo 'CHARMAP="UTF-8"' > /etc/default/console-setup
echo 'CODESET="Lat15"' >> /etc/default/console-setup
echo 'FONTFACE="TerminusBold"' >> /etc/default/console-setup
echo 'FONTSIZE="16"' >> /etc/default/console-setup

# Configuration timezone
timedatectl set-timezone Europe/Paris

# Application des changements
dpkg-reconfigure -f noninteractive locales
dpkg-reconfigure -f noninteractive keyboard-configuration
dpkg-reconfigure -f noninteractive console-setup
setupcon

# Nettoyage
rm -f /root/post-install.sh

echo "Configuration française terminée!"
EOF
  
  chmod +x "$POST_INSTALL_SCRIPT"
  
  msg_ok "Cloud-init configuré avec script de post-installation"
}

function finalize_vm() {
  msg_info "Finalisation de la VM"
  
  # Redimensionner le disque si nécessaire
  if [[ "${DISK_SIZE}" != "20G" ]]; then
    msg_info "Redimensionnement du disque à ${DISK_SIZE}"
    # Avec timeout pour éviter les blocages
    timeout 30 qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null 2>&1 || {
      msg_warn "Timeout lors du redimensionnement - le disque sera redimensionné au premier démarrage"
    }
  fi
  
  # Description de la VM
  local DESCRIPTION="VM Debian 12 - Configuration Française
Créée le: $(date '+%d/%m/%Y à %H:%M')
Script: https://github.com/H1ok4r3d/VM
BIOS: SeaBIOS (défaut)
CPU: ${CORE_COUNT} cœurs
RAM: ${RAM_SIZE} MB
Disque: ${DISK_SIZE}
Langue: Français
Clavier: Français  
Utilisateur: root uniquement

Post-installation:
1. Se connecter en SSH ou console
2. Exécuter: bash /var/lib/vz/snippets/post-install-${VMID}.sh

Notes:
- L'agent QEMU sera disponible après installation des guest tools
- Première connexion: root avec le mot de passe défini"
  
  qm set "$VMID" -description "$DESCRIPTION" >/dev/null
  
  msg_ok "VM finalisée"
  
  # Demander si on démarre la VM
  echo -e "\n"
  echo -n "Démarrer la VM maintenant ? (o/N): "
  read start_vm
  if [[ "$start_vm" =~ ^[oO]$ ]]; then
    msg_info "Démarrage de la VM"
    qm start $VMID
    
    # Attendre quelques secondes avant de vérifier le statut
    sleep 3
    
    if qm status $VMID | grep -q "running"; then
      msg_ok "VM démarrée avec succès"
      
      echo -e "\n${BGN}=== VM CRÉÉE AVEC SUCCÈS ===${CL}"
      echo -e "ID: ${BL}$VMID${CL}"
      echo -e "Nom: ${BL}$HN${CL}"
      echo -e "BIOS: ${BL}SeaBIOS (défaut)${CL}"
      echo -e "CPU: ${BL}$CORE_COUNT cœurs${CL}"
      echo -e "RAM: ${BL}$RAM_SIZE MB${CL}"
      echo -e "Disque: ${BL}$DISK_SIZE${CL}"
      echo -e "Utilisateur: ${BL}root${CL}"
      echo -e "Console: ${BL}qm terminal $VMID${CL}"
      
      echo -e "\n${INFO}${BOLD}PROCHAINES ÉTAPES:${CL}"
      echo -e "1. Attendre que la VM termine son démarrage (1-2 minutes)"
      echo -e "2. Se connecter: ${BL}qm terminal $VMID${CL}"
      echo -e "3. Configurer le français: ${BL}bash /var/lib/vz/snippets/post-install-${VMID}.sh${CL}"
      echo -e "4. Connexion: utilisateur ${BL}root${CL} avec le mot de passe défini"
      
      echo -e "\n${WARN}Note: L'agent QEMU sera disponible après installation des guest tools${CL}"
    else
      msg_error "Problème lors du démarrage - vérifiez les logs"
      echo -e "Vérification: ${BL}qm status $VMID${CL}"
    fi
  else
    echo -e "\n${BGN}VM créée mais non démarrée.${CL}"
    echo -e "Pour démarrer: ${BL}qm start $VMID${CL}"
    echo -e "Pour configurer le français après démarrage:"
    echo -e "${BL}bash /var/lib/vz/snippets/post-install-${VMID}.sh${CL}"
  fi
}

function show_usage() {
  echo -e "\n${INFO}Usage depuis GitHub:${CL}"
  echo -e "  ${BL}bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/H1ok4r3d/VM/main/vm-debian.sh)\"${CL}"
  echo -e "\n${INFO}Ou en root:${CL}"
  echo -e "  ${BL}sudo bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/H1ok4r3d/VM/main/vm-debian.sh)\"${CL}"
}

function main() {
  header_info
  
  echo -e "\n${INFO}Ce script va créer une VM Debian 12 avec:${CL}"
  echo -e "  • BIOS par défaut (SeaBIOS)"
  echo -e "  • Configuration post-installation pour le français"
  echo -e "  • Utilisateur root uniquement"
  echo -e "  • Configuration Cloud-init basique"
  echo -e "  • CPU: Utilisation maximale ($(nproc) cœurs)"
  echo -e "  • RAM: 2048 MB par défaut"
  
  echo -e "\n"
  echo -n "Continuer ? (o/N): "
  
  # Forcer le flush et attendre l'entrée
  exec < /dev/tty
  read continue_script
  
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
