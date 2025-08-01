#!/usr/bin/env bash

# Script de création de VM Debian 12 Cloud-Init pour Proxmox
# Version GitHub - Configuration Française AZERTY
# Auteur: Thierry AZZARO (Hiok4r3d)

set -euo pipefail

# Fonction pour afficher l'en-tête
function header_info() {
  clear
  cat <<"EOF"
   ____       _     _              ______              __      __  __  __ 
  / __ \___  | |__ (_) __ _ _ __   |  ____|             \ \    / / |  \/  |
 / / / / _ \ | '_ \| |/ _` | '_ \  | |__ _ __   __ _ _ __ \ \  / /  | |\/| |
/ /_/ /  __/ | |_) | | (_| | | | | |  __| '__| / _` | '_ \ \  / /   | |  | |
\____/ \___| |_.__/|_|\__,_|_| |_| |_|  |_|    \__,_| | | |  \/    |_|  |_|
                                                      |_| |_|               
        === Création VM Debian 12 - Configuration Française ===
                 Version GitHub - AZERTY - Cloud-Init
EOF
}

# Fonctions de message
function msg_info() {
  echo -e "  \e[36m➤\e[0m $1"
}
function msg_ok() {
  echo -e "  \e[32m✔️\e[0m $1"
}
function msg_error() {
  echo -e "  \e[31m✖️\e[0m $1" >&2
  exit 1
}

# Vérification des dépendances
for cmd in qm wget; do
  if ! command -v $cmd >/dev/null 2>&1; then
    msg_error "$cmd n'est pas installé. Installation requise."
  fi
done

header_info

# --- Confirmation initiale ---
read -p $'\nÊtes-vous sûr de vouloir créer une nouvelle VM ? (o/N): ' CREATE_CONFIRM
[[ "$CREATE_CONFIRM" =~ ^[Oo]$ ]] || exit 0

# --- Configuration de base ---
read -p $'\nID de la VM (défaut: 107): ' VMID
VMID=${VMID:-107}

read -p "Nom d'hôte (défaut: debian-fr): " VMNAME
VMNAME=${VMNAME:-debian-fr}

# --- Sélection du réseau ---
echo -e "\n  💡  Bridges réseau disponibles:"
mapfile -t BRIDGES < <(ls /sys/class/net | grep vmbr)
for i in "${!BRIDGES[@]}"; do
  echo "  $((i+1)). ${BRIDGES[$i]}"
done
read -p "Sélectionnez le bridge réseau (1-${#BRIDGES[@]}, défaut: 1): " BRIDGE_NUM
BRIDGE_NUM=${BRIDGE_NUM:-1}
BRIDGE=${BRIDGES[$((BRIDGE_NUM-1))]}

# --- Sélection du stockage ---
echo -e "\n  💡  Stockages disponibles:"
STORAGES=$(pvesm status -content images | awk 'NR>1 {printf "%d. %s - Type: %s - Libre: %s / %s\n", NR-1, $1, $2, $4, $3}')
echo "$STORAGES"
read -p "Choisir le stockage (1-$(echo "$STORAGES" | wc -l), défaut: 1): " STORAGE_ID
STORAGE_ID=${STORAGE_ID:-1}
STORAGE=$(echo "$STORAGES" | sed -n "${STORAGE_ID}p" | awk '{print $2}')

# --- Configuration système ---
echo -e "\n  💡  Configuration du mot de passe root"
ROOT_PASSWORD="root"
msg_info "Mot de passe par défaut: root (changement obligatoire au premier login)"

read -p "Taille du disque en GB (défaut: 20): " DISK_SIZE
DISK_SIZE=${DISK_SIZE:-20}

# --- Résumé ---
echo -e "\n=== RÉSUMÉ DE LA CONFIGURATION ==="
echo "ID VM: $VMID"
echo "Nom d'hôte: $VMNAME"
echo "Bridge: $BRIDGE"
echo "Stockage: $STORAGE"
echo "Taille disque: ${DISK_SIZE}G"
echo "CPU: 4 cœurs"
echo "RAM: 2048 MB"
echo "Clavier: AZERTY Français"
echo "Mot de passe: root (à changer au 1er login)"
read -p $'\nConfirmer la création ? (o/N): ' CONFIRM
[[ "$CONFIRM" =~ ^[Oo]$ ]] || exit 0

# --- Téléchargement de l'image ---
msg_info "Téléchargement de l'image Debian 12 Cloud"
IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
wget -q --show-progress $IMG_URL -O /tmp/debian-12.qcow2 || msg_error "Échec du téléchargement"
msg_ok "Image téléchargée avec succès"

# --- Création de la VM ---
msg_info "Création de la VM $VMID"
qm create $VMID \
  --name "$VMNAME" \
  --memory 2048 \
  --cores 4 \
  --net0 virtio,bridge="$BRIDGE" \
  --ostype l26 \
  --scsihw virtio-scsi-pci \
  --ide2 "${STORAGE}:cloudinit" \
  --boot order=scsi0 \
  --serial0 socket \
  --vga serial0 \
  --ciuser root \
  --cipassword "$ROOT_PASSWORD" \
  --keyboard fr \
  --agent enabled=1 >/dev/null || msg_error "Échec de la création de la VM"
msg_ok "VM créée avec succès"

# --- Configuration Cloud-Init ---
msg_info "Configuration du changement obligatoire de mot de passe"
qm set $VMID --sshkeys /dev/null >/dev/null  # Force le changement de mot de passe
msg_ok "Sécurité configurée (changement mot de passe obligatoire)"

msg_info "Importation du disque"
qm importdisk "$VMID" /tmp/debian-12.qcow2 "$STORAGE" >/dev/null || msg_error "Échec de l'importation"
msg_ok "Disque importé avec succès"

msg_info "Configuration du stockage"
IMPORTED_DISK=$(qm config "$VMID" | grep "^unused0:" | awk '{print $2}')
[ -z "$IMPORTED_DISK" ] && msg_error "Disque non détecté"

qm set "$VMID" --scsi0 "${IMPORTED_DISK},discard=on,ssd=1" >/dev/null
qm resize "$VMID" scsi0 "${DISK_SIZE}G" >/dev/null
msg_ok "Disque configuré (${DISK_SIZE}GB)"

msg_info "Configuration réseau et cloud-init"
qm set "$VMID" \
  --searchdomain local \
  --nameserver 1.1.1.1 \
  --ipconfig0 ip=dhcp >/dev/null

# Configuration du fuseau horaire via cloud-init
cat <<EOF > /tmp/vm-${VMID}-cloudinit.yaml
#cloud-config
timezone: Europe/Paris
locale: fr_FR.UTF-8
keyboard:
  layout: fr
  variant: azerty
EOF
qm set "$VMID" --cicustom "user=local:snippets/vm-${VMID}-cloudinit.yaml" >/dev/null
msg_ok "Configuration Cloud-Init appliquée"

# --- Nettoyage ---
rm -f /tmp/debian-12.qcow2
[ -f "/tmp/vm-${VMID}-cloudinit.yaml" ] && mv "/tmp/vm-${VMID}-cloudinit.yaml" "/var/lib/vz/snippets/"

msg_ok "VM $VMID '$VMNAME' prête à l'emploi !"
msg_info "Connexion SSH: root@IP_VM - Mot de passe: root (à changer)"
echo -e "\n=== CRÉATION TERMINÉE AVEC SUCCÈS ==="
