# 💻 Script de création de VM Debian 12 pour Proxmox VE

Ce script Bash permet de créer une machine virtuelle Debian 12 « Cloud-Init Ready » sur Proxmox VE, avec configuration automatique du mot de passe root, de l'image disque, des paramètres réseau, et de la langue française.

---

## 📦 Fonctionnalités

- Téléchargement de l'image officielle Debian 12 Cloud
- Création de la VM avec Cloud-Init (accès root uniquement)
- Redimensionnement du disque (défini par l'utilisateur)
- Prise en charge des stockages `dir`, `lvm`, `zfs`, etc.
- Langue système et clavier configurés en **français**
- Détection automatique des bridges réseau et stockages disponibles
- Interface interactive (pas de configuration en dur)

---

## ✅ Prérequis

- Proxmox VE (6.x ou supérieur)
- Le stockage doit accepter les **images** (format `qcow2`)
- Le bridge réseau (vmbr0 par défaut) doit être configuré

---

## 🚀 Installation et exécution

Exécuter directement le script avec `bash` : ```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/H1ok4r3d/VM/main/vm-debian.sh)"```
