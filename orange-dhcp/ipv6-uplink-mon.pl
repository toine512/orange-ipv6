#!/usr/bin/perl

# Copyright (C) 2023 toine512 <me@toine512.fr>
#
# **** License ****
#  Unless other terms apply to a specific section,
#  this program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
# **** End License ****

use strict;
use warnings;
use feature qw(say);
use Sys::Syslog qw(:standard :macros);

die "Le nom de l'interface à surveiller doit être donné en paramètre !" unless defined($ARGV[0]);

#say `/sbin/ip -6 -c neigh show to fe80::ba0:bab dev $ARGV[0]`;

my @valid = ("reachable", "none", "probe", "delay");
foreach(@valid) {
	exit 0 if length(`/sbin/ip -6 neigh show to fe80::ba0:bab dev $ARGV[0] nud $_`);
}

openlog('DHCPv6 Orange', '', LOG_DAEMON);
syslog(LOG_WARNING, "Perte du lien IPv6, recyclage du DHCPv6 sur l'interface $ARGV[0].");
closelog();

system("systemctl --no-block --no-pager restart dhclient-orange-ipv6\@$ARGV[0].service");