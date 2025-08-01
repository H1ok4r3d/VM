#!/usr/bin/env bash

# Script de création de VM Debian 12 Cloud-Init pour Proxmox
# Version optimisée avec gestion automatique des VMID, CPU et paramètres par défaut
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
                 Version Optimisée - Paramètres Automatiques
EOF
}

# Fonctions utilitaires
function msg_info() { echo -e "  \e[36m➤\e[0m $1"; }
function msg_ok() { echo -e "  \e[32m✔️\e[0m $1"; }
function msg_error() { echo -e "  \e[31m✖️\e[0m $1" >&2; exit 1; }

# Vérification des dépendances
for cmd in qm wget; do
  command -v $cmd >/dev/null 2>&1 || msg_error "$cmd n'est pas installé."
done

# Fonction pour trouver le premier VMID disponible
function find_available_vmid() {
  local start_vmid=${1:-100}
  while qm list | awk '{print $1}' | grep -q "^${start_vmid}$"; do
    ((start_vmid++))
  done
  echo $start_vmid
}

header_info

# --- Confirmation initiale ---
read -p $'\nÊtes-vous sûr de vouloir créer une nouvelle VM ? (o/N): ' CREATE_CONFIRM
[[ "$CREATE_CONFIRM" =~ ^[Oo]$ ]] || exit 0

# --- Configuration de base ---
DEFAULT_VMID=$(find_available_vmid 100)
read -p $'\nID de la VM (défaut: premier disponible à partir de 100 - actuel: '$DEFAULT_VMID$'): ' VMID
VMID=${VMID:-$DEFAULT_VMID}

read -p "Nom d'hôte (défaut: debian-fr): " VMNAME
VMNAME=${VMNAME:-debian-fr}

# --- Configuration matérielle ---
CPU_CORES=$(nproc --all)
RAM_SIZE=2048
DISK_SIZE=20
SCSI_CONTROLLER="virtio-scsi-pci"
BIOS="seabios"
FIREWALL=1

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

read -p "Taille du disque en GB (défaut: $DISK_SIZE): " CUSTOM_DISK_SIZE
DISK_SIZE=${CUSTOM_DISK_SIZE:-$DISK_SIZE}

read -p "Nombre de cœurs CPU (max disponible: $CPU_CORES, défaut: $((CPU_CORES/2))): " CUSTOM_CPU_CORES
CPU_CORES=${CUSTOM_CPU_CORES:-$((CPU_CORES/2))}

# --- Résumé ---
echo -e "\n=== RÉSUMÉ DE LA CONFIGURATION ==="
echo "ID VM: $VMID (automatique)"
echo "Nom d'hôte: $VMNAME"
echo "Bridge: $BRIDGE"
echo "Stockage: $STORAGE"
echo "Taille disque: ${DISK_SIZE}G"
echo "CPU: $CPU_CORES cœurs/$CPU_CORES vCPU"
echo "RAM: ${RAM_SIZE} MB"
echo "Contrôleur SCSI: $SCSI_CONTROLLER"
echo "BIOS: $BIOS"
echo "Firewall: $FIREWALL"
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
  --memory $RAM_SIZE \
  --cores $CPU_CORES \
  --net0 virtio,bridge="$BRIDGE",firewall=$FIREWALL \
  --ostype l26 \
  --scsihw $SCSI_CONTROLLER \
  --bios $BIOS \
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
msg_info "Configuration SSH et mot de passe root"
cat <<EOF > /tmp/vm-${VMID}-cloudinit.yaml
#cloud-config
package_update: true
packages:
  - openssh-server
  - qemu-guest-agent
users:
  - name: root
    lock_passwd: false
    plain_text_passwd: "$ROOT_PASSWORD"
    sudo: ALL=(ALL) NOPASSWD:ALL
chpasswd:
  expire: true
runcmd:
  - systemctl enable --now ssh
  - systemctl enable --now qemu-guest-agent
  - sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
  - systemctl restart sshd
EOF

qm set $VMID --cicustom "user=local:snippets/vm-${VMID}-cloudinit.yaml" >/dev/null
msg_ok "Configuration SSH appliquée"

# --- Configuration du disque ---
msg_info "Importation du disque"
qm importdisk "$VMID" /tmp/debian-12.qcow2 "$STORAGE" >/dev/null || msg_error "Échec de l'importation"
msg_ok "Disque importé avec succès"

msg_info "Configuration du stockage"
IMPORTED_DISK=$(qm config "$VMID" | grep "^unused0:" | awk '{print $2}')
[ -z "$IMPORTED_DISK" ] && msg_error "Disque non détecté"

qm set "$VMID" --scsi0 "${IMPORTED_DISK},discard=on,ssd=1" >/dev/null
qm resize "$VMID" scsi0 "${DISK_SIZE}G" >/dev/null
msg_ok "Disque configuré (${DISK_SIZE}GB)"

# --- Configuration réseau ---
msg_info "Configuration réseau"
qm set "$VMID" \
  --searchdomain local \
  --nameserver 1.1.1.1 \
  --ipconfig0 ip=dhcp >/dev/null
msg_ok "Réseau configuré"

# --- Option de démarrage ---
read -p $'\nVoulez-vous démarrer la VM maintenant ? (o/N): ' START_VM
if [[ "$START_VM" =~ ^[Oo]$ ]]; then
  msg_info "Démarrage de la VM $VMID"
  qm start "$VMID" >/dev/null || msg_error "Échec du démarrage"
  
  # Attente de l'adresse IP
  msg_info "Attente de l'adresse IP..."
  for i in {1..10}; do
    VM_IP=$(qm guest cmd "$VMID" network-get-interfaces | grep -oP '(?<=ip-address: )\d+\.\d+\.\d+\.\d+' | head -1)
    [ -n "$VM_IP" ] && break
    sleep 3
  done
  
  if [ -n "$VM_IP" ]; then
    msg_ok "VM démarrée avec succès - IP: $VM_IP"
    echo -e "\nConnexion SSH:"
    echo "ssh root@$VM_IP"
    echo "Mot de passe: root (à changer immédiatement)"
  else
    msg_info "VM démarrée mais adresse IP non obtenue automatiquement"
  fi
fi

# --- Nettoyage ---
rm -f /tmp/debian-12.qcow2
mv "/tmp/vm-${VMID}-cloudinit.yaml" "/var/lib/vz/snippets/" 2>/dev/null || true

echo -e "\n=== CRÉATION TERMINÉE AVEC SUCCÈS ==="
echo -e "Pour vous connecter plus tard:\n  ssh root@<IP_VM>\nMot de passe: root"
