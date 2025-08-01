# 💻 Script de création de VM Debian 12 pour Proxmox VE

Ce script Bash permet de créer une machine virtuelle Debian 12 « Cloud-Init Ready » sur Proxmox VE avec une configuration optimisée pour un usage francophone.

## 🚀 Nouveautés et améliorations

- **Gestion intelligente des VMID** : Trouve automatiquement le premier ID disponible
- **Configuration matérielle optimale** :
  - Détection automatique des cœurs CPU disponibles
  - BIOS SeaBIOS par défaut
  - Contrôleur SCSI VirtIO par défaut
  - Firewall activé (=1) sur l'interface réseau
- **Sécurité renforcée** :
  - Mot de passe root temporaire (changé au premier login)
  - Configuration automatique de SSH sécurisé
  - Expiration du mot de passe forcée
- **Robustesse améliorée** :
  - Vérification des conflits de VMID/CTID
  - Double tentative de démarrage
  - Gestion des erreurs complète

## 📦 Fonctionnalités principales

- Téléchargement de l'image officielle Debian 12 Cloud
- Création de la VM avec Cloud-Init (accès root)
- Configuration automatique :
  - Taille du disque (20GB par défaut, personnalisable)
  - Nombre de cœurs CPU (détection automatique)
  - Mémoire RAM (2048MB par défaut)
  - Réseau (sélection parmi les bridges disponibles)
  - Stockage (sélection parmi les stockages disponibles)
- Langue système et clavier AZERTY **français**
- Interface interactive intuitive avec valeurs par défaut intelligentes
- Option de démarrage automatique après création

## ✅ Prérequis

- Proxmox VE 7.x ou supérieur
- Un stockage compatible avec les images (format `qcow2`)
- Un bridge réseau configuré
- Packages requis : `wget`, `qm` (inclus dans Proxmox)
- Environnement Bash

## 🛠️ Installation et utilisation

1. Téléchargement et exécution directe :
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/H1ok4r3d/VM/main/vm-debian.sh)"
