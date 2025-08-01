# 💻 Script de création de VM Debian 12 pour Proxmox VE

Ce script Bash permet de créer une machine virtuelle Debian 12 « Cloud-Init Ready » sur Proxmox VE avec une configuration optimisée pour un usage francophone.

## ⚠️ Authentification et sécurité (IMPORTANT)
- **Accès root uniquement** : Aucun autre utilisateur n'est créé par défaut
- **Mot de passe par défaut** : 
  - Identifiant : `root`
  - Mot de passe : `root` (temporaire)
- **Changement obligatoire** : 
  - Vous devrez **impérativement** changer le mot de passe au premier login
  - Le système forcera ce changement avant toute opération
  - Minimum 8 caractères recommandé

## 🚀 Nouveautés et améliorations
- **Gestion intelligente des VMID** : Trouve automatiquement le premier ID disponible
- **Configuration root sécurisée** : Expiration immédiate du mot de passe
- **Détection automatique** des ressources CPU disponibles
- **Firewall activé** par défaut sur l'interface réseau

## 📦 Fonctionnalités principales
- Création VM avec **accès root exclusif**
- Configuration AZERTY **français** par défaut
- Taille du disque personnalisable (20GB par défaut)
- Sélection interactive des bridges réseau et stockages

## ✅ Prérequis
- Proxmox VE 7.x+
- 2GB RAM minimum recommandé
- Droits root sur le serveur Proxmox

## 🛠️ Utilisation
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/H1ok4r3d/VM/main/vm-debian.sh)"
