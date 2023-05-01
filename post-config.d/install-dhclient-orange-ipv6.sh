#!/bin/vbash

# Copyright (C) 2023 toine512 <me@toine512.fr>
#
# **** License ****
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
# **** End License ****

## Configurer ici
INTERFACE="<INTERFACE>.832"

## TAGS
# DHCPv6
ip6tables -t mangle -I POSTROUTING -o $INTERFACE -p udp --sport dhcpv6-client --dport dhcpv6-server -j CLASSIFY --set-class 0:6
ip6tables -t mangle -I POSTROUTING -o $INTERFACE -p udp --sport dhcpv6-client --dport dhcpv6-server -j DSCP --set-dscp-class CS6
# NDP RS (133/0)
ip6tables -t mangle -I POSTROUTING -o $INTERFACE -p icmpv6 --icmpv6-type router-solicitation -j CLASSIFY --set-class 0:6
ip6tables -t mangle -I POSTROUTING -o $INTERFACE -p icmpv6 --icmpv6-type router-solicitation -j DSCP --set-dscp-class CS6
# NDP NS (135/0)
ip6tables -t mangle -I POSTROUTING -o $INTERFACE -p icmpv6 --icmpv6-type neighbour-solicitation -j CLASSIFY --set-class 0:6
ip6tables -t mangle -I POSTROUTING -o $INTERFACE -p icmpv6 --icmpv6-type neighbour-solicitation -j DSCP --set-dscp-class CS6
# NDP NA (136/0)
ip6tables -t mangle -I POSTROUTING -o $INTERFACE -p icmpv6 --icmpv6-type neighbour-advertisement -j CLASSIFY --set-class 0:6
ip6tables -t mangle -I POSTROUTING -o $INTERFACE -p icmpv6 --icmpv6-type neighbour-advertisement -j DSCP --set-dscp-class CS6
# MLDv2 Report (143/0)
ip6tables -t mangle -I POSTROUTING -o $INTERFACE -p icmpv6 --icmpv6-type 143/0 -j CLASSIFY --set-class 0:6
ip6tables -t mangle -I POSTROUTING -o $INTERFACE -p icmpv6 --icmpv6-type 143/0 -j DSCP --set-dscp-class CS6

logger -p daemon.info -t "DHCPv6 Orange" "Règles ip6tables mangle CoS 6 et DSCP CS6 installées pour l'interface $INTERFACE."

## Installation (1 fois)
if [ ! -f "/etc/systemd/system/dhclient-orange-ipv6@.service" ]; then
	chmod +x /config/user-data/orange-dhcp/dhclient-orange-ipv6.pl
	cp /config/user-data/orange-dhcp/dhclient-orange-ipv6@.service /etc/systemd/system/dhclient-orange-ipv6@.service
	systemctl enable dhclient-orange-ipv6@$INTERFACE
	systemctl start dhclient-orange-ipv6@$INTERFACE &
	logger -p daemon.warning -t "DHCPv6 Orange" "Service installé pour l'interface $INTERFACE."
fi
