# Script de Création de VM Debian 12 pour Proxmox VE

![Debian](https://www.debian.org/logos/openlogo-nd-100.png) ![Proxmox](https://www.proxmox.com/images/proxmox/Proxmox_logo_standard_hex_400px.png)

## 🔍 Description

Ce script Bash automatisé permet de déployer rapidement une machine virtuelle Debian 12 optimisée pour Proxmox VE avec :

- Configuration Cloud-Init prête à l'emploi
- Paramètres français par défaut (AZERTY, timezone Europe/Paris)
- Gestion automatique des ressources système

## ⚠️ Avertissement de Sécurité Important

### Authentification Root Unique
- **Seul le compte root** est configuré par défaut
- **Identifiants initiaux** :
  ```bash
  Utilisateur: root
  Mot de passe: root
Aucun utilisateur standard n'est créé automatiquement

Mesures de Sécurité Obligatoires
Changement immédiat du mot de passe au premier login

8 caractères minimum requis pour le nouveau mot de passe

Accès SSH root temporaire - À désactiver après configuration

🛠 Fonctionnalités Techniques
🔧 Configuration Automatique
Composant	Valeur par défaut	Personnalisable
Langue	fr_FR.UTF-8	Non
Clavier	AZERTY Français	Non
BIOS	SeaBIOS	Non
Contrôleur SCSI	virtio-scsi-pci	Non
Firewall	Activé (vmbrX)	Oui
🌐 Réseau
Détection automatique des bridges disponibles

Configuration DHCP par défaut

DNS : 1.1.1.1

💾 Stockage
Support des types :

dir

lvm

zfs

ceph

Taille disque : 20GB (modifiable)

📋 Prérequis Système
Configuration Minimale
Ressource	Spécification
Proxmox VE	Version 7.x ou supérieure
CPU	2 cœurs minimum
RAM	2048 MB minimum
Espace disque	20 GB minimum
Dépendances Requises
wget

qm (outil Proxmox)

curl (pour installation directe)

🚀 Guide d'Installation Rapide
Méthode en Une Ligne
bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/H1ok4r3d/VM/main/vm-debian.sh)"
Méthode Manuel (3 étapes)
bash
wget https://raw.githubusercontent.com/H1ok4r3d/VM/main/vm-debian.sh
chmod +x vm-debian.sh
./vm-debian.sh
🔒 Procédure de Sécurisation Post-Installation
Étape 1 - Connexion Initiale
bash
ssh root@IP_VM
# Le système forcera immédiatement le changement de mot de passe
Étape 2 - Création d'Utilisateur Standard (Recommandé)
bash
adduser nom_utilisateur
usermod -aG sudo nom_utilisateur
Étape 3 - Sécurisation SSH (Optionnel mais Recommandé)
bash
nano /etc/ssh/sshd_config
# Modifier :
# PermitRootLogin no
# PasswordAuthentication no (si utilisation de clés SSH)
systemctl restart sshd
📌 Bonnes Pratiques pour Environnements de Production
✅ À Faire Absolument
Créer un utilisateur standard avec sudo

Configurer l'authentification par clé SSH

Mettre à jour régulièrement le système

❌ À Éviter
Conserver le mot de passe root par défaut

Laisser l'accès root SSH activé à long terme

Utiliser en production sans utilisateur dédié

🐛 Guide de Dépannage
Problème : Connexion SSH Impossible
bash
# Vérifier le service SSH
systemctl status ssh

# Vérifier le firewall
iptables -L -n

# Consulter les logs
journalctl -u ssh --no-pager
Problème : Échec de Démarrage de la VM
bash
# Consulter les logs cloud-init
qm config VMID | grep cicustom
cat /var/lib/vz/snippets/vm-VMID-cloudinit.yaml
🤝 Comment Contribuer
Les contributions sont bienvenues via :

Issues : Pour rapporter des bugs ou demander des fonctionnalités

Pull Requests : Pour proposer des améliorations directes

📜 Licence
MIT License - Voir le fichier LICENSE pour plus de détails

Auteur: Thierry AZZARO (Hiok4r3d)
Dernière Mise à Jour: $(date +%Y-%m-%d)

text

### Comment utiliser ce fichier :

1. **Sauvegarder le README** :
```bash
cat > README.md << 'EOF'
[Coller tout le contenu ci-dessus]
EOF
Formatage recommandé :

Ce fichier utilise la syntaxe Markdown standard

Compatible avec GitHub, GitLab et la plupart des visualiseurs Markdown

Contient des emojis pour une meilleure lisibilité

Personnalisation :

Remplacez les liens vers le dépôt GitHub si nécessaire

Modifiez les informations d'auteur

Ajoutez des sections spécifiques à votre environnement

Ce README fournit une documentation complète avec :

Les avertissements de sécurité bien visibles

Les instructions d'installation détaillées

Les bonnes pratiques pour un usage professionnel

Un guide de dépannage de base
