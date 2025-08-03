#!/usr/bin/env bash

# Script de création VM Debian 12 - Configuration Française avec sécurité renforcée
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
STORAGE_TYPE=""
THIN="discard=on,ssd=1,"
FORMAT=",efitype=4m"
MACHINE=""
DISK_CACHE=""
CPU_TYPE=""
BRG="vmbr0"
VLAN=""
MTU=""

set -e

# Nettoyage automatique
trap cleanup EXIT

function cleanup() {
  if [ -d "$TEMP_DIR" ]; then
    cd /
    rm -rf "$TEMP_DIR"
  fi
}

function cleanup_vmid() {
  if qm status $VMID &>/dev/null; then
    qm stop $VMID &>/dev/null
    qm destroy $VMID &>/dev/null
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
  echo -e "Password: ${BL}Temporaire (changement forcé)${CL}"
  
  echo -e "\n"
  echo -n "Créer la VM ? (o/N): "
  read confirm
  if [[ ! "$confirm" =~ ^[oO]$ ]]; then
    echo "Annulé"
    exit 0
  fi
}

function create_cloud_init_config() {
  msg_info "Création de la configuration Cloud-init"
  
  # Créer le fichier user-data pour cloud-init
  cat > "$TEMP_DIR/user-data" << 'EOF'
#cloud-config
users:
  - name: root
    shell: /bin/bash
    lock_passwd: false
    ssh_pwauth: true
    chpasswd:
      expire: true

# Forcer le changement de mot de passe à la première connexion
runcmd:
  - chage -d 0 root
  - systemctl enable ssh
  - systemctl start ssh
  - apt-get update -qq
  - apt-get install -y -qq curl wget nano vim htop net-tools openssh-server
  - sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - systemctl reload ssh
  - echo "🔐 ATTENTION: Vous devez changer le mot de passe root à la première connexion!" > /etc/motd
  - echo "🔑 Le mot de passe temporaire est: TempPass123!" >> /etc/motd
  - echo "🛠️  Utilisez la commande 'passwd' pour le changer." >> /etc/motd
  - echo "🖥️  VM créée avec le script H1ok4r3d" >> /etc/motd

# Configuration réseau
network:
  config: disabled

# Mise à jour du système
package_update: true
package_upgrade: false

# Localisation française
locale: fr_FR.UTF-8
timezone: Europe/Paris

# Installations de base
packages:
  - curl
  - wget
  - nano
  - vim
  - htop
  - net-tools
  - openssh-server
  - sudo

final_message: |
  🎉 La VM Debian 12 est prête !
  🔐 ATTENTION: Changez le mot de passe root à la première connexion !
  🔑 Mot de passe temporaire: TempPass123!
EOF

  # Créer le fichier meta-data
  cat > "$TEMP_DIR/meta-data" << EOF
instance-id: vm-$VMID-$(date +%s)
local-hostname: $HN
EOF

  msg_ok "Configuration Cloud-init créée"
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
  
  # Déterminer le type de stockage
  STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
  
  case $STORAGE_TYPE in
    nfs | dir)
      DISK_EXT=".qcow2"
      DISK_REF="$VMID/"
      DISK_IMPORT="-format qcow2"
      THIN=""
      ;;
    btrfs)
      DISK_EXT=".raw"
      DISK_REF="$VMID/"
      DISK_IMPORT="-format raw"
      FORMAT=",efitype=4m"
      THIN=""
      ;;
    *)
      DISK_EXT=""
      DISK_REF=""
      DISK_IMPORT=""
      ;;
  esac
  
  # Définir les noms de disques
  DISK0=vm-${VMID}-disk-0${DISK_EXT}
  DISK1=vm-${VMID}-disk-1${DISK_EXT}
  DISK0_REF=${STORAGE}:${DISK_REF}${DISK0}
  DISK1_REF=${STORAGE}:${DISK_REF}${DISK1}
  
  # Création VM basique
  qm create $VMID \
    -agent 1${MACHINE} \
    -tablet 0 \
    -localtime 1 \
    -bios ovmf${CPU_TYPE} \
    -cores $CORE_COUNT \
    -memory $RAM_SIZE \
    -name "$HN" \
    -net0 virtio,bridge=$BRG,macaddr=$GEN_MAC${VLAN}${MTU} \
    -onboot 1 \
    -ostype l26 \
    -scsihw virtio-scsi-pci \
    -tags "community-script,debian12,secure" >/dev/null 2>&1
  
  if [ $? -ne 0 ]; then
    msg_error "Échec création VM"
    exit 1
  fi
  
  msg_ok "VM créée"
}

function import_and_configure_disk() {
  msg_info "Import et configuration du disque"
  
  local FILE="$TEMP_DIR/debian-12-genericcloud-amd64.qcow2"
  
  # Allouer l'espace pour EFI
  pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null || {
    msg_error "Échec allocation EFI"
    cleanup_vmid
    exit 1
  }
  
  # Import du disque principal
  if ! qm importdisk $VMID "$FILE" $STORAGE ${DISK_IMPORT} 1>&/dev/null; then
    msg_error "Échec import disque"
    cleanup_vmid
    exit 1
  fi
  
  msg_ok "Disque importé"
  
  msg_info "Configuration des disques"
  
  # Configuration des disques et cloud-init
  qm set $VMID \
    -efidisk0 ${DISK0_REF}${FORMAT} \
    -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
    -ide2 ${STORAGE}:cloudinit \
    -boot order=scsi0 \
    -serial0 socket >/dev/null 2>&1
  
  if [ $? -ne 0 ]; then
    msg_error "Échec configuration disques"
    cleanup_vmid
    exit 1
  fi
  
  msg_ok "Disques configurés"
}

function configure_vm() {
  msg_info "Configuration Cloud-init de la VM"
  
  # Configuration cloud-init avec notre mot de passe temporaire
  qm set $VMID \
    -ciuser root \
    -cipassword "$ROOT_PASSWORD" \
    -ipconfig0 ip=dhcp \
    -searchdomain local \
    -nameserver 8.8.8.8 >/dev/null 2>&1
  
  if [ $? -ne 0 ]; then
    msg_error "Échec configuration cloud-init"
    cleanup_vmid
    exit 1
  fi
  
  # Ajouter notre configuration cloud-init personnalisée
  if [ -f "$TEMP_DIR/user-data" ]; then
    # Créer un ISO avec notre configuration
    if command -v genisoimage >/dev/null 2>&1; then
      genisoimage -output "$TEMP_DIR/cloud-config.iso" -volid cidata -joliet -rock "$TEMP_DIR/user-data" "$TEMP_DIR/meta-data" >/dev/null 2>&1
    elif command -v mkisofs >/dev/null 2>&1; then
      mkisofs -output "$TEMP_DIR/cloud-config.iso" -volid cidata -joliet -rock "$TEMP_DIR/user-data" "$TEMP_DIR/meta-data" >/dev/null 2>&1
    else
      msg_warn "Pas d'outil ISO disponible, installation basique"
    fi
  fi
  
  # Redimensionner le disque si nécessaire
  if [[ "$DISK_SIZE" != "20G" ]]; then
    msg_info "Redimensionnement disque vers $DISK_SIZE"
    if ! qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null 2>&1; then
      msg_warn "Échec redimensionnement"
    else
      msg_ok "Disque redimensionné"
    fi
  fi
  
  # Ajouter une description à la VM
  local DESCRIPTION=$(cat <<EOF
<div align='center'>
  <h2>🐧 VM Debian 12 Sécurisée</h2>
  <p><strong>Créée avec le script H1ok4r3d</strong></p>
  <p>🔐 <strong>Sécurité renforcée:</strong> Changement de mot de passe obligatoire</p>
  <p>🔑 <strong>Mot de passe temporaire:</strong> TempPass123!</p>
  <p>🖥️ <strong>Hostname:</strong> $HN</p>
  <p>💾 <strong>Stockage:</strong> $STORAGE</p>
  <p>🌐 <strong>Bridge:</strong> $BRG</p>
</div>
EOF
)
  
  qm set "$VMID" -description "$DESCRIPTION" >/dev/null 2>&1
  
  msg_ok "VM configurée"
}

function start_vm() {
  echo -e "\n"
  echo -n "Démarrer la VM maintenant ? (o/N): "
  read start_choice
  
  if [[ "$start_choice" =~ ^[oO]$ ]]; then
    msg_info "Démarrage de la VM"
    qm start $VMID
    
    # Attendre le démarrage
    echo -e "\n${INFO}Attente du démarrage et configuration (90 secondes)...${CL}"
    sleep 90
    
    # Essayer d'obtenir l'IP
    local vm_ip=""
    for i in {1..15}; do
      # Méthode 1: via qm guest
      vm_ip=$(qm guest cmd $VMID network-get-interfaces 2>/dev/null | grep -o '"ip-address":"[^"]*"' | grep -v "127.0.0.1" | head -1 | cut -d'"' -f4 2>/dev/null || echo "")
      
      # Méthode 2: via agent si disponible
      if [[ -z "$vm_ip" ]]; then
        vm_ip=$(qm agent $VMID network-get-interfaces 2>/dev/null | jq -r '.[] | select(.name != "lo") | .["ip-addresses"][]? | select(.["ip-address-type"] == "ipv4") | .["ip-address"]' 2>/dev/null | head -1 || echo "")
      fi
      
      if [[ -n "$vm_ip" && "$vm_ip" != "127.0.0.1" ]]; then
        break
      fi
      sleep 3
    done
    
    if qm status $VMID | grep -q "running"; then
      msg_ok "VM démarrée avec succès"
      
      echo -e "\n${BGN}=== 🎉 VM DEBIAN 12 PRÊTE 🎉 ===${CL}"
      echo -e "┌─────────────────────────────────────────────┐"
      echo -e "│                                             │"
      echo -e "│  🆔 ID VM: ${BL}$VMID${CL}                               │"
      echo -e "│  🏠 Nom: ${BL}$HN${CL}                            │"
      echo -e "│  🌐 IP: ${BL}${vm_ip:-En cours d attribution...}${CL}                     │"
      echo -e "│  💾 Stockage: ${BL}$STORAGE${CL}                        │"
      echo -e "│                                             │"
      echo -e "└─────────────────────────────────────────────┘"
      
      echo -e "\n${RD}🔐 INFORMATIONS DE SÉCURITÉ IMPORTANTES:${CL}"
      echo -e "┌─────────────────────────────────────────────┐"
      echo -e "│  👤 Utilisateur: ${BL}root${CL}                        │"
      echo -e "│  🔑 Mot de passe temporaire: ${BL}$ROOT_PASSWORD${CL}      │"
      echo -e "│  ⚠️  ${RD}CHANGEMENT OBLIGATOIRE À LA 1ère CONNEXION${CL} │"
      echo -e "└─────────────────────────────────────────────┘"
      
      echo -e "\n${INFO}🖥️  Méthodes de connexion:${CL}"
      echo -e "• Console Proxmox: ${BL}VM $VMID > Console${CL}"
      echo -e "• Terminal: ${BL}qm terminal $VMID${CL}"
      if [[ -n "$vm_ip" && "$vm_ip" != *"En cours"* ]]; then
        echo -e "• SSH: ${BL}ssh root@$vm_ip${CL}"
      fi
      
      echo -e "\n${INFO}🛠️  Commandes utiles:${CL}"
      echo -e "• Changer mot de passe: ${BL}passwd${CL}"
      echo -e "• Arrêter VM: ${BL}qm stop $VMID${CL}"
      echo -e "• Redémarrer VM: ${BL}qm reboot $VMID${CL}"
      echo -e "• Statut VM: ${BL}qm status $VMID${CL}"
      
      echo -e "\n${WARN}📋 Première connexion:${CL}"
      echo -e "1. Connectez-vous avec root / $ROOT_PASSWORD"
      echo -e "2. Le système vous forcera à changer le mot de passe"
      echo -e "3. Choisissez un mot de passe sécurisé"
      echo -e "4. Votre VM sera alors prête à l'usage !"
      
    else
      msg_warn "Problème de démarrage détecté"
      echo -e "Vérifiez avec: ${BL}qm status $VMID${CL}"
      echo -e "Logs: ${BL}qm monitor $VMID${CL}"
    fi
  else
    echo -e "\n${INFO}VM créée mais non démarrée${CL}"
    echo -e "Pour démarrer: ${BL}qm start $VMID${CL}"
    echo -e "Mot de passe temporaire: ${BL}$ROOT_PASSWORD${CL}"
    echo -e "${RD}N'oubliez pas de changer le mot de passe à la première connexion !${CL}"
  fi
}

function main() {
  header_info
  
  echo -e "\n${INFO}🚀 Création VM Debian 12 avec sécurité renforcée${CL}"
  echo -e "• CPU: ${BL}$(nproc) cœurs${CL}"
  echo -e "• RAM: ${BL}2048 MB${CL}"
  echo -e "• Sécurité: ${BL}Changement mot de passe obligatoire${CL}"
  echo -e "• Localisation: ${BL}France (fr_FR.UTF-8)${CL}"
  
  check_root
  check_dependencies  
  pve_check
  get_vm_settings
  create_cloud_init_config
  download_image
  create_vm
  import_and_configure_disk
  configure_vm
  start_vm
  
  echo -e "\n${CM}${GN}🎉 Script terminé avec succès ! 🎉${CL}\n"
  echo -e "${INFO}Pour plus d'aide: https://github.com/H1ok4r3d/VM${CL}\n"
}

main "$@"
