#!/bin/vbash

# Copyright (C) 2022 toine512 <me@toine512.fr>
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

INTERFACE="<INTERFACE>.832"

if [ ! -f "/etc/systemd/system/dhclient-orange-ipv6@.service" ]; then
	chmod +x /config/user-data/orange-dhcp/dhclient-orange-ipv6.pl
	cp /config/user-data/orange-dhcp/dhclient-orange-ipv6@.service /etc/systemd/system/dhclient-orange-ipv6@.service
	systemctl enable dhclient-orange-ipv6@$INTERFACE
	systemctl start dhclient-orange-ipv6@$INTERFACE &
	logger -p daemon.info -t "DHCPv6 Orange" "Service installé pour l'interface $INTERFACE."
fi
