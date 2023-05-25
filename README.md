# orange-ipv6
 IPv6 Orange pour EdgeOS

# Fonctionnement
## dhclient 4


## Distribution du préfixe


## Démarrage
 Le script `install-dhclient-orange-ipv6.sh` :
 - installe les règles `mangle POSTROUTING` de `ip6tables` pour ajouter le tag Class of Service 6 et l'en-tête IPv6 DSCP CS6 sur les paquets DHCPv6, NDP et MLDv2,
 - enregistre et active l'unit file pour démarrer dhclient si le fichier n'existe pas dans `/etc/systemd/system/dhclient-orange-ipv6@.service`.
 - enregistre l'unit file annexe pour le service de surveillance du lien dans `/etc/systemd/system/orange-ipv6-uplink-mon@.service`.

## Log
 Les différents scripts sortent des messages dans syslog : facility `daemon`, nom `DHCPv6 Orange` et sévérité info à error.

# Installation
 Tous les fichiers appatiennent à l'utilisateur `ubnt` et au groupe `vyattacfg`. (comportement par défaut)
 
 1. Ajouter les règles de firewall spécifiques pour le DHCPv6. \
    à détailler
 2. Dans `post-config.d/install-dhclient-orange-ipv6.sh`, modifier la première ligne pour renseigner l'interface WAN. Cette action peut aussi être faite directement sur le routeur (après l'étape 5). \
    Exemple : `INTERFACE="eth1.832"`
 3. Dans `orange-dhcp/dhclient-orange-ipv6.conf` (fichier de configuration de dhclient 4), renseigner le nom de l'interface (WAN) et compléter les options DHCP. Les valeurs sont identiques à l'IPv4. (voir [Références](#références)) Cette action peut aussi être faite directement sur le routeur (après l'étape 5).
 4. Copier les fichiers contenus dans `orange-dhcp` vers `/config/user-data/orange-dhcp/` \
    Ce chemin exact est obligatoire.
 5. Copier les fichiers contenus dans `post-config.d` vers `/config/scripts/post-config.d/` \
    Rendre le script de démarrage exécutable : \
    `:/config/scripts/post-config.d/# chmod +x *-orange-ipv6.sh`
 6. Redémarrer le routeur après avoir configuré les SLA sur les interfaces : [Usage](#usage)

 Le script `log-dhclient-orange-ipv6.sh` (à copier dans `/config/user-data/`) peut être utilisé pour voir les entrées de journal spécifiques à cet outil.

# Usage


# Références
- Travail basé sur ce topic : https://lafibre.info/remplacer-livebox/tuto-er-6p-v2-0-6-cisco-sg350-28p-nettv-sans-livebox/
- https://lafibre.info/remplacer-livebox/en-cours-remplacer-sa-livebox-par-un-routeur-ubiquiti-edgemax
- https://lafibre.info/remplacer-livebox/ubiquiti-er-ipv6-dhcp6-en-2-x
- https://lafibre.info/remplacer-livebox/durcissement-du-controle-de-loption-9011-et-de-la-conformite-protocolaire

# To do list
 - [ ] Compléter le README
 - [x] Détection de la perte de communication
 - [x] Support CoS 6 complet
 - [x] Meilleur unit file pour pourvoir release le bail DHCP correctement
