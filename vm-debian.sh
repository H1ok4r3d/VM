#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Modifié par Thierry AZZARO (Hiok4r3d) pour Proxmox Debian 12
# Script de création de VM Debian Cloud-Init en français

set -euo pipefail

# Fonction pour afficher les entêtes
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
                       Depuis GitHub Repository
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
}

# Vérifie que qm et wget sont installés
for cmd in qm wget; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo "Erreur : $cmd n'est pas installé." >&2
    exit 1
  fi
done

header_info

# --- Confirmation de création ---
read -p $'\nÊtes-vous sûr de vouloir créer une nouvelle VM ? (o/N): ' CREATE_CONFIRM
[[ "$CREATE_CONFIRM" =~ ^[Oo]$ ]] || exit 0

# --- Configuration initiale ---
read -p $'\nID de la VM (défaut: 107): ' VMID
VMID=${VMID:-107}

read -p "Nom d'hôte (défaut: debian-fr): " VMNAME
VMNAME=${VMNAME:-debian-fr}

# --- Bridge réseau ---
echo -e "\n  💡  Bridges réseau disponibles:"
mapfile -t BRIDGES < <(ls /sys/class/net | grep vmbr)
for i in "${!BRIDGES[@]}"; do
  echo "  $((i+1)). ${BRIDGES[$i]}"
done
read -p "Sélectionnez le bridge réseau (1-${#BRIDGES[@]}, défaut: 1): " BRIDGE_NUM
BRIDGE_NUM=${BRIDGE_NUM:-1}
BRIDGE=${BRIDGES[$((BRIDGE_NUM-1))]}

# --- Stockage ---
echo -e "\n  💡  Stockages disponibles:"
STORAGES=$(pvesm status -content images | awk 'NR>1 {printf "%d. %s - Type: %s - Libre: %s / %s\n", NR-1, $1, $2, $4, $3}')
echo "$STORAGES"
read -p "Choisir le stockage (1-$(echo "$STORAGES" | wc -l), défaut: 1): " STORAGE_ID
STORAGE_ID=${STORAGE_ID:-1}
STORAGE=$(echo "$STORAGES" | sed -n "${STORAGE_ID}p" | awk '{print $2}')

# --- Mot de passe root ---
echo -e "\n  💡  Configuration du mot de passe root"
ROOT_PASSWORD="root"
msg_info "Mot de passe root par défaut : root (changement obligatoire au premier login)"

# --- Taille disque ---
echo -e "\n  💡  Configuration avancée (optionnel)"
read -p "Taille du disque en GB (défaut: 20): " DISK_SIZE
DISK_SIZE=${DISK_SIZE:-20}

# --- Résumé ---
echo -e "\n=== RÉSUMÉ DE LA CONFIGURATION ==="
echo "ID VM: $VMID"
echo "Nom d'hôte: $VMNAME"
echo "Bridge: $BRIDGE"
echo "Stockage: $STORAGE"
echo "Taille disque: ${DISK_SIZE}G"
echo "CPU: 4 cœurs (maximum disponible)"
echo "RAM: 2048 MB"
echo "MAC: Générée aléatoirement"
echo "BIOS: SeaBIOS (défaut)"
echo "Langue: Français"
echo "Clavier: Français (AZERTY)"
echo "Utilisateur: Root uniquement"
echo "Mot de passe: root (à changer au premier login)"
read -p $'\nConfirmer la création de la VM ? (o/N): ' CONFIRM
[[ "$CONFIRM" =~ ^[Oo]$ ]] || exit 0

# --- Création de la VM ---
msg_info "Téléchargement de l'image Debian Cloud"
IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
wget -q --show-progress $IMG_URL -O /tmp/debian-12.qcow2
msg_ok "Image téléchargée"

msg_info "Création de la VM $VMID"
qm create $VMID \
  --name $VMNAME \
  --memory 2048 \
  --cores 4 \
  --net0 virtio,bridge=$BRIDGE \
  --ostype l26 \
  --scsihw virtio-scsi-pci \
  --ide2 ${STORAGE}:cloudinit \
  --boot order=scsi0 \
  --serial0 socket \
  --vga serial0 \
  --ciuser root \
  --cipassword "$ROOT_PASSWORD" \
  --timezone Europe/Paris \
  --keyboard fr \
  --agent enabled=1 >/dev/null
msg_ok "VM créée"

# Configuration pour forcer le changement de mot de passe au premier login
msg_info "Configuration du changement obligatoire de mot de passe"
qm set $VMID --cipassword "$ROOT_PASSWORD" >/dev/null
qm set $VMID --sshkeys /dev/null >/dev/null  # Supprime toute clé SSH existante
msg_ok "Changement de mot de passe obligatoire configuré (min 8 caractères)"

msg_info "Importation du disque"
qm importdisk $VMID /tmp/debian-12.qcow2 $STORAGE >/dev/null
msg_ok "Disque importé"

msg_info "Configuration du disque principal"
IMPORTED_DISK=$(qm config $VMID | grep "^unused0:" | awk '{print $2}')
if [ -z "$IMPORTED_DISK" ]; then
  msg_error "Aucun disque importé détecté dans la configuration de la VM"
  qm destroy $VMID --purge >/dev/null 2>&1
  exit 1
fi

qm set $VMID --scsi0 ${IMPORTED_DISK},discard=on,ssd=1 >/dev/null
qm resize $VMID scsi0 ${DISK_SIZE}G >/dev/null
msg_ok "Disque principal configuré et redimensionné à ${DISK_SIZE}G"

msg_info "Application de la configuration Cloud-Init"
qm set $VMID --ciuser root --cipassword "$ROOT_PASSWORD" \
  --searchdomain local --nameserver 1.1.1.1 --ipconfig0 ip=dhcp >/dev/null
msg_ok "Configuration Cloud-Init appliquée"

# Nettoyage
rm -f /tmp/debian-12.qcow2

msg_ok "VM Debian 12 prête à être démarrée !"
msg_info "Au premier login, vous devrez changer le mot de passe root (minimum 8 caractères)"
