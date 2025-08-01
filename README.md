# 🖥️ Script de Création de VM Debian 12 pour Proxmox VE

![Debian](https://www.debian.org/logos/openlogo-nd-100.png)
![Proxmox](https://www.proxmox.com/images/proxmox/Proxmox_logo_standard_hex_400px.png)

## 🔍 Description

Ce script Bash permet de créer automatiquement une **VM Debian 12 Cloud-Init** prête à l'emploi sur **Proxmox VE**, avec :

- Téléchargement automatique de l'image officielle Debian Cloud
- Clavier configuré en **AZERTY (fr-latin1)**
- Mot de passe root initial défini à `root`, avec **changement obligatoire au premier login**
- Configuration réseau, stockage et ressources assistée via des menus interactifs
- **Cloud-Init personnalisé** incluant SSH, agent QEMU, configuration root, etc.

---

## ⚠️ Sécurité : Accès Root Uniquement

**Par défaut :**
```bash
Utilisateur : root
Mot de passe : root
```

- 🔐 Le mot de passe doit être changé à la première connexion (imposé via `cloud-init`)
- 🚫 Aucun utilisateur standard n'est créé automatiquement
- 🔥 L'accès SSH root est activé pour l'installation **mais doit être désactivé ensuite**

---

## 🧰 Fonctionnalités Techniques

| Composant              | Valeur par défaut       | Personnalisable |
|------------------------|-------------------------|------------------|
| Langue                 | fr_FR.UTF-8             | ❌              |
| Clavier                | fr-latin1 (AZERTY)      | ❌              |
| BIOS                   | SeaBIOS                 | ❌              |
| Contrôleur SCSI        | virtio-scsi-pci         | ❌              |
| Firewall réseau        | Activé (`vmbrX`)        | ✅              |
| Disque                 | 20 GB                   | ✅              |
| CPU / RAM              | Détection automatique   | ✅              |
| Stockage               | Tout backend PVE        | ✅              |

---

## 🌐 Réseau

- Détection automatique des interfaces réseau (`vmbrX`)
- Configuration DHCP par défaut
- DNS configuré sur `1.1.1.1`

---

## 💾 Prérequis

### Matériel / Logiciel

| Ressource    | Requis minimum         |
|--------------|------------------------|
| Proxmox VE   | v7.x ou supérieur      |
| CPU          | 2 cœurs                |
| RAM          | 2048 MB                |
| Disque       | 20 GB                  |

### Outils nécessaires

- `qm` (outil CLI Proxmox)
- `wget`
- `curl` (optionnel pour installation en une ligne)

---

## 🚀 Installation

### ✅ Méthode rapide

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/H1ok4r3d/VM/main/vm-debian.sh)"
```

### 🛠 Méthode manuelle

```bash
wget https://raw.githubusercontent.com/H1ok4r3d/VM/main/vm-debian.sh
chmod +x vm-debian.sh
./vm-debian.sh
```

---

## 🔒 Sécurisation après installation

1. 🔐 **Changer le mot de passe root** (imposé)
2. 👤 **Créer un utilisateur standard** :
    ```bash
    adduser monuser
    usermod -aG sudo monuser
    ```
3. 🔧 **Désactiver SSH root si production** :
    ```bash
    nano /etc/ssh/sshd_config
    # Modifier :
    PermitRootLogin no
    PasswordAuthentication no  # si clés SSH utilisées
    systemctl restart sshd
    ```

---

## ✅ Bonnes pratiques

### À FAIRE

- Créer un utilisateur non-root avec `sudo`
- Activer l’authentification par clé SSH
- Mettre à jour Debian régulièrement

### À ÉVITER

- Garder le mot de passe root par défaut
- Laisser l’accès SSH root activé en production
- Utiliser ce script tel quel en environnement critique sans modifications

---

## 🐛 Dépannage

### ❌ SSH inaccessible ?

```bash
systemctl status ssh
iptables -L -n
journalctl -u ssh --no-pager
```

### ❌ VM ne démarre pas ?

```bash
# Vérifier la config cloud-init
qm config <VMID> | grep cicustom
cat /var/lib/vz/snippets/vm-<VMID>-cloudinit.yaml
```

---

## 🤝 Contribuer

Contributions bienvenues !

- Ouvrir une **Issue** pour signaler un bug ou suggérer une amélioration
- Envoyer une **Pull Request** avec vos modifications

---

## 📜 Licence

Ce projet est sous licence **MIT**. Voir [LICENSE](./LICENSE).

Auteur : Thierry AZZARO (Hiok4r3d)  
Dernière mise à jour : **01/08/2025**
