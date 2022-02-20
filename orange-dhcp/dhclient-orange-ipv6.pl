#!/usr/bin/perl

# Copyright (C) 2022 toine512 <me@toine512.fr>
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
use NetAddr::IP::Lite qw(:lower);
use Math::BigInt;
use lib "/opt/vyatta/share/perl5/";
use Vyatta::Config;
use Vyatta::Interface;
use Vyatta::DhcpPd qw(sysctl_set_ra get_commit_notdone);


my $DHCLIENT_BIN_DIR = '/sbin';


# Le script doit être exécuté par le groupe vyattacfg pour modifier la configuration du routeur. Sinon la configuration change de propriétaire et ne peut plus être modifiée par les moyens habituels.
# Le script s'invoque via sg pour changer de groupe :
# https://stackoverflow.com/questions/922921/set-effective-group-id-of-perl-script
my $vyattacfg_gid = getgrnam('vyattacfg');
if (( 0+$( ) != $vyattacfg_gid) {
	my (@reinvoke) = ($0, map {quotemeta} @ARGV);
	exec('/usr/bin/sg', 'vyattacfg', "@reinvoke");
	die("/usr/bin/sg not found!  Can't change group!");
}


#Globales
my $reason = $ENV{'reason'};
my $interface = new Vyatta::Interface($ENV{'interface'});
die 'Doit être appelé par dhclient3 !' unless defined($reason) and defined($interface);


### SECTION Vyatta::Interface

# Author: Stephen Hemminger <shemminger@vyatta.com>
# Date: 2009
# Description: vyatta interface management

# **** Specific License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2008 Vyatta, Inc.
# All Rights Reserved.
# **** End Specific License ****

my %net_prefix = (
    '^adsl[\d]+$'  => { path => 'adsl',
		      vif => 'vif',    },
    '^bond[\d]+$'  => { path => 'bonding',
		      vif => 'vif', },
    '^br[\d]+$'    => { path => 'bridge',
		      vif => 'vif' },
    '^eth[\d]+$'   => { path => 'ethernet',
		      vif => 'vif', },
    '^lo$'         => { path => 'loopback' },
    '^ml[\d]+$'    => { path => 'multilink',
		      vif => 'vif', },
    '^vtun[\d]+$'  => { path => 'openvpn' },
    '^v6tun[\d]+$' => { path => 'ipv6-tunnel' },
    '^pptpc[\d]+$' => { path => 'pptp-client' },
    '^wan[\d]+$'   => { path => 'serial',
		      vif  => ( 'cisco-hdlc vif', 'ppp vif',
				'frame-relay vif' ), },
    '^tun[\d]+$'   => { path => 'tunnel' },
    '^vti[\d]+$'   => { path => 'vti' },
    '^wlm[\d]+$'   => { path => 'wireless-modem' },
    '^peth[\d]+$'  => { path => 'pseudo-ethernet',
		      vif => 'vif', },
    '^wlan[\d]+$'  => { path => 'wireless', vif => 'vif' },
    '^ifb[\d]+$'   => { path => 'input' },
    '^switch[\d]+$'   => { path => 'switch', vif => 'vif' },
    '^l2tpeth[\d]+$'  => { path => 'l2tpv3' },
    '^l2tpc[\d]+$' => { path => 'l2tp-client' },
);

sub get_all_cfg_interfaces {
  my ($in_active) = @_;
  my $vfunc = ($in_active ? 'listOrigNodes' : 'listNodes');

  my $cfg = new Vyatta::Config;
  my @ret_ifs = ();
  for my $pfx (keys %net_prefix) {
    my ($type, $vif) = ($net_prefix{$pfx}->{path}, $net_prefix{$pfx}->{vif});
    my @vifs = (defined($vif)
                ? ((ref($vif) eq 'ARRAY') ? @{$vif}
                                            : ($vif))
                  : ());
    for my $tif ($cfg->$vfunc("interfaces $type")) {
      push @ret_ifs, { 'name' => $tif, 'path' => "interfaces $type $tif" };
      for my $vpath (@vifs) {
        for my $vnum ($cfg->$vfunc("interfaces $type $tif $vpath")) {
          push @ret_ifs, { 'name' => "$tif.$vnum",
                           'path' => "interfaces $type $tif $vpath $vnum" };
        }
      }
    }
  }

  # now special cases for pppo*/adsl
  for my $eth ($cfg->$vfunc('interfaces ethernet')) {
    for my $ep ($cfg->$vfunc("interfaces ethernet $eth pppoe")) {
      push @ret_ifs, { 'name' => "pppoe$ep",
                       'path' => "interfaces ethernet $eth pppoe $ep" };
    }
  }
  for my $a ($cfg->$vfunc('interfaces adsl')) {
    for my $p ($cfg->$vfunc("interfaces adsl $a pvc")) {
      for my $t ($cfg->$vfunc("interfaces adsl $a pvc $p")) {
        if ($t eq 'classical-ipoa' or $t eq 'bridged-ethernet') {
          # classical-ipoa or bridged-ethernet
          push @ret_ifs,
            { 'name' => $a,
              'path' => "interfaces adsl $a pvc $p $t" };
          next;
        }
        # pppo[ea]
        for my $i ($cfg->$vfunc("interfaces adsl $a pvc $p $t")) {
          push @ret_ifs,
            { 'name' => "$t$i",
              'path' => "interfaces adsl $a pvc $p $t $i" };
        }
      }
    }
  }

  return @ret_ifs;
}
### END SECTION Vyatta::Interface


sub waitfor_commit {
	while (-e get_commit_notdone()) {
		sleep(1);
	}
}

sub compute_subnet {
	my ($ip_prefix, $sla_id, $sla_len) = @_;
	
	my $i_mask = $ip_prefix->masklen();
	my $i_sub_mask = $i_mask + $sla_len;
	
	#Range check
	return if ($sla_len < 0 or $i_sub_mask > 64 or $sla_id < 0 or $sla_id >= 1<<$sla_len);
	
	my $i_sub_prefix = $ip_prefix->bigint() + $sla_id * Math::BigInt->new(2)->bpow(128 - $i_sub_mask);
	return NetAddr::IP::Lite->new6($i_sub_prefix, $i_sub_mask);
}

sub get_sla_id_for_intf {
	my $if_cfg_path = shift;
	
	#See Vyatta::Misc::interface_description()
	my $config = new Vyatta::Config;
	$config->setLevel($if_cfg_path);
	return unless $config->existsOrig('description');
	$config->returnOrigValue('description') =~ /\[o_sla_id=(\d+)\]/i or return;
	#$1 is o_sla_id
	
	return $1;
}

sub get_other_intf_with_sla_id {
	my $origin_intf = $interface->name();
	my @all_intf = get_all_cfg_interfaces(1);
	my @found_intf = ();
	
	foreach(@all_intf) {
		if($_->{'name'} ne $origin_intf) {
			my $sla_id = get_sla_id_for_intf($_->{'path'});
			if(defined $sla_id) {
				push @found_intf, { 'cfg_path' => $_->{'path'}, 'sla_id' => $sla_id };
			}
		}
	}
	
	return @found_intf;
}

sub setenv_ip6 {
	my ($key, $sla_id) = @_;
	defined $sla_id or $sla_id = 0; #Sous réseau 00 par défaut pour l'interface externe si non spécifié
	
	return unless defined $ENV{"${key}_ip6_prefix"};
	my $ip_prefix = NetAddr::IP::Lite->new6($ENV{"${key}_ip6_prefix"});
	return unless defined $ip_prefix;
		
	my $if_subnet = compute_subnet($ip_prefix, $sla_id, 64-$ip_prefix->masklen());
	$ENV{"${key}_ip6_address"} = $if_subnet->first()->addr();
	$ENV{"${key}_ip6_prefixlen"} = $if_subnet->masklen();
}

sub pre_hook {
	if($reason eq 'BOUND6') {
		waitfor_commit();
		setenv_ip6('new', get_sla_id_for_intf($interface->path())) or die;
	}
	
	elsif($reason eq 'RENEW6' or $reason eq 'REBIND6' or $reason eq 'DEPREF6') {
		waitfor_commit();
		my $sla_id = get_sla_id_for_intf($interface->path());
		
		setenv_ip6('old', $sla_id) or die;
		setenv_ip6('new', $sla_id) or die;
	}
	
	elsif($reason eq 'EXPIRE6' or $reason eq 'RELEASE6' or $reason eq 'STOP6') {
		waitfor_commit();
		setenv_ip6('old', get_sla_id_for_intf($interface->path())) or die;
	}
}

sub post_hook {
	my @config_commands = ();
	
	if($reason eq 'PREINIT6') {
		my $ifname = $interface->name();
		sysctl_set_ra($ifname, 2);
		
		syslog(LOG_NOTICE, "Acceptation du Router Advertisement sur l'interface $ifname. (RA mode 2)");
	}
	
	elsif($reason eq 'BOUND6') {
		my @target_intf = get_other_intf_with_sla_id();
		
		if(@target_intf) {
			die unless defined $ENV{'new_ip6_prefix'};
			my $ip_prefix = NetAddr::IP::Lite->new6($ENV{'new_ip6_prefix'});
			die unless defined $ip_prefix;
			
			syslog(LOG_NOTICE, "Nouveau préfixe Orange : $ENV{'new_ip6_prefix'}.");
			
			foreach(@target_intf) {
				my $intf_cfg_path = $_->{'cfg_path'};
				my $subnet = scalar compute_subnet($ip_prefix, $_->{'sla_id'}, 64-$ip_prefix->masklen());
				push @config_commands, "set $intf_cfg_path ipv6 router-advert prefix $subnet";
				
				if(defined $ENV{'new_max_life'}) {
					push @config_commands, "set $intf_cfg_path ipv6 router-advert prefix $subnet valid-lifetime $ENV{'new_max_life'}";
				}
				
				if(defined $ENV{'new_preferred_life'}) {
					push @config_commands, "set $intf_cfg_path ipv6 router-advert prefix $subnet preferred-lifetime $ENV{'new_preferred_life'}";
				}
				
				syslog(LOG_INFO, "+ Annonce du préfixe $subnet.");
			}
		}
	}
	
	elsif($reason eq 'RENEW6' or $reason eq 'REBIND6' or $reason eq 'DEPREF6') {
		my @target_intf = get_other_intf_with_sla_id();
		
		if(@target_intf) {
			die unless defined($ENV{'old_ip6_prefix'}) and defined($ENV{'new_ip6_prefix'});
			
			if($ENV{'old_ip6_prefix'} eq $ENV{'new_ip6_prefix'}) {
				syslog(LOG_INFO, "Préfixe Orange inchangé ($ENV{'new_ip6_prefix'}).");
				
				my $max_life_changed = 0;
				my $preferred_life_changed = 0;
				if(defined($ENV{'old_max_life'}) and defined($ENV{'new_max_life'})) {
					$max_life_changed = $ENV{'old_max_life'} != $ENV{'new_max_life'};
				}
				if(defined($ENV{'old_preferred_life'}) and defined($ENV{'new_preferred_life'})) {
					$preferred_life_changed = $ENV{'old_preferred_life'} != $ENV{'new_preferred_life'};
				}
				
				if($max_life_changed or $preferred_life_changed) {
					my $new_ip_prefix = NetAddr::IP::Lite->new6($ENV{'new_ip6_prefix'});
					die unless defined $new_ip_prefix;
					
					foreach(@target_intf) {
						my $intf_cfg_path = $_->{'cfg_path'};
						my $subnet = scalar compute_subnet($new_ip_prefix, $_->{'sla_id'}, 64-$new_ip_prefix->masklen());
						
						if($max_life_changed) {
							push @config_commands, "set $intf_cfg_path ipv6 router-advert prefix $subnet valid-lifetime $ENV{'new_max_life'}";
						}
						
						if($preferred_life_changed) {
							push @config_commands, "set $intf_cfg_path ipv6 router-advert prefix $subnet preferred-lifetime $ENV{'new_preferred_life'}";
						}
					}
				}
			}
			else {
				syslog(LOG_NOTICE, "Nouveau préfixe Orange : $ENV{'new_ip6_prefix'}.");
				
				my $old_ip_prefix = NetAddr::IP::Lite->new6($ENV{'old_ip6_prefix'});
				my $new_ip_prefix = NetAddr::IP::Lite->new6($ENV{'new_ip6_prefix'});
				die unless defined($old_ip_prefix) and defined($new_ip_prefix);
				
				foreach(@target_intf) {
					my $intf_cfg_path = $_->{'cfg_path'};
					my $old_subnet = scalar compute_subnet($old_ip_prefix, $_->{'sla_id'}, 64-$old_ip_prefix->masklen());
					my $new_subnet = scalar compute_subnet($new_ip_prefix, $_->{'sla_id'}, 64-$new_ip_prefix->masklen());
					
					push @config_commands, "delete $intf_cfg_path ipv6 router-advert prefix $old_subnet";
					
					push @config_commands, "set $intf_cfg_path ipv6 router-advert prefix $new_subnet";
				
					if(defined $ENV{'new_max_life'}) {
						push @config_commands, "set $intf_cfg_path ipv6 router-advert prefix $new_subnet valid-lifetime $ENV{'new_max_life'}";
					}
					
					if(defined $ENV{'new_preferred_life'}) {
						push @config_commands, "set $intf_cfg_path ipv6 router-advert prefix $new_subnet preferred-lifetime $ENV{'new_preferred_life'}";
					}
					
					syslog(LOG_INFO, "≠ Remplacement du préfixe $old_subnet par $new_subnet.");
				}
			}
		}
	}
	
	elsif($reason eq 'EXPIRE6' or $reason eq 'RELEASE6' or $reason eq 'STOP6') {
		syslog(LOG_WARNING, "Préfixe Orange expiré.");
		
		my @target_intf = get_other_intf_with_sla_id();
		
		if(@target_intf) {
			die unless defined $ENV{'old_ip6_prefix'};
			my $ip_prefix = NetAddr::IP::Lite->new6($ENV{'old_ip6_prefix'});
			die unless defined $ip_prefix;
			
			foreach(@target_intf) {
				my $intf_cfg_path = $_->{'cfg_path'};
				my $subnet = scalar compute_subnet($ip_prefix, $_->{'sla_id'}, 64-$ip_prefix->masklen());
				
				push @config_commands, "delete $intf_cfg_path ipv6 router-advert prefix $subnet";
				
				syslog(LOG_INFO, "- Suppression de l'annonce du préfixe $subnet.");
			}
		}
		
		my $ifname = $interface->name();
		sysctl_set_ra($ifname, 1);
		
		syslog(LOG_INFO, "Refus du Router Advertisement sur l'interface $ifname. (RA mode 1)");
	}

	if(@config_commands) {
		unshift @config_commands, 'begin';
		push @config_commands, 'commit';
		push @config_commands, 'end';
		
		waitfor_commit();
		syslog(LOG_NOTICE, "Modification de la configuration du routeur…");
		
		foreach(@config_commands) {
			system("/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper $_");
		}
		
		syslog(LOG_INFO, "Commit terminé.");
	}
}


openlog('DHCPv6 Orange', '', LOG_DAEMON);
syslog(LOG_INFO, "--- Évènement DHCPv6 $reason sur l'interface " . $interface->name() . ' ---');

pre_hook();

system("$DHCLIENT_BIN_DIR/dhclient-script");

post_hook();

closelog();
