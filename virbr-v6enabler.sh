#! /bin/sh
#
# (C) 2011 Shinichiro HIDA <shinichiro@stained-g.net>
# License:  GPLv3
#
# Created: Fri, Jul 08 08:23:21 JST 2011 
# Last modified: Wed, Jul 13 20:16:16 JST 2011

# Short-Description: Add IPv6 address to virbrN interfaces.
# Description:       Add IPv6 address to virbrN interfaces which bringed up
#                    by libvirt-bin to get IPv6 reachability for KVM
#                    guests virtual machines on vnetN virtual networks. 


# Require: ip command (iproute2)
#          sysctl
#          virbr-v6enabler.conf
#          radvd, (or dhcpv6)

## Please set up some variables in `virbr-v6enabler.conf' file to fit
## your environment.
## This script should call later libvirt-bin started.
## If this script run successfly, it is ready to run radvd or dhcpv6.
## For more information, please read README file.

# Please set your config file (virbr-v6enabler.conf) directory.
conf_path_prefix="/usr/local/etc"

config_file="$conf_path_prefix""/virbr-v6enabler.conf"
# get variables..
if [ -s "$config_file" ]; then
    . $config_file
else
    echo "$0: Error: $config_file not found. exit.."
    exit 1
fi

## set default variable..
if [ "$v_mtu" = "" ]; then
    v_mtu="1280"
fi

## calculate function. hex to decimal
hexdec() {
    num=`echo $1 | tr '[a-f]' '[A-F]'`
    echo 16i $num p | dc
}

## Start
echo "$0: Setting up IPv6 environment for virbrN (bringed up by libvirt)"

## check virtual bridges (virbrN, N=[0-9]*) are found or not..
virt_bridges=`echo \`ip link show | grep "virbr" | awk '{print $2}' | sed -e "s/[:]//g"\``

## First, enabling ipv6 for adding linklocal address.
## for checking your system like below..
## $ sysctl -a | grep "net.ipv6.conf.vibr" | grep "disable_ipv6"

if [ "$virt_bridges" != "" ]; then
    echo "$0"": virt_bridges $virt_bridges found. [OK]"
     # $n is counter for determine subnet_address.
     n="0"
     # determine v6prefix..
     if [ "$v6prefix_64" != "" ]; then
	     # all virbrN into 1 same subnet..
	     v6prefix="v6prefix_64"

     elif [ "v6prefix_48" != ""  ]; then
         # ok, determine subnet address from subnet_range_*..
	 # get starting and ending address from subnet_range_*..
	 if [ "$subnet_range_hex" != "" ]; then
	     subnet_start_hex=`echo "$subnet_range_hex" | awk -F, '{print $1}'`
	     subnet_end_hex=`echo "$subnet_range_hex" | awk -F, '{print $2}'`
		     
	     # calculate subnet_(start,end) from hex to decimal
	     subnet_start=`hexdec $subnet_start_hex`
	     subnet_end=`hexdec $subnet_end_hex`
	     
	 elif [ "$subnet_range_dec" != "" ]; then
	     # subnet_range_hex is NOT defined. Using subnet_range_dec.
	     subnet_start=`echo "$subnet_range_dec" | awk -F, '{print $1}'`
	     subnet_end=`echo "$subnet_range_dec" | awk -F, '{print $2}'`
	     
	 else
             # subnet_range_* not found...
	     # Could not determine v6prefix...
	     echo "$0: Sorry, I could not determine your IPv6 prefix /64."
	     echo "$0: to add only linklocal address to your virbr$i,\
 please do: sysctl -w net.ipv6.conf.$i.disable_ipv6=0 .\
 This cause, you could not access to outside of your virbrN LAN."
	     echo "$0: If you do not want this situation,\
  please specify v6prefix_64, or v6prefix_48 and prefix_range valiables\
  which defined /etc/default/virbr-v6enabler."
	     echo "$0: Please check and adjust /etc/radvd.conf also."
	     echo "%0: exitting.."
	     exit 1
	 fi
     fi

     # Try to enable IPv6 all virbrN.
     for i in $virt_bridges
     do
	 n=`expr $n + 1`
	 echo "$0: $i found. bring-up IPv6 link-local address to $i."

         # enabling IPv6 for iface virbrN. you get linklocal address your $i
	 iface_disable_ipv6=`/sbin/sysctl -n net.ipv6.conf.$i.disable_ipv6`
	 if [ "$iface_disable_ipv6" = "1" ]; then
             /sbin/sysctl -w net.ipv6.conf."$i".disable_ipv6=0 || \
	     echo "$0: Error:line 107: /sbin/sysctl -w net.ipv6.conf.$i.disable_ipv6=0"
	 fi

         # determine "iface_number_decimal". If all virbrN in 1 subnet, from 1 to increment.
	 if [ "$v6prefix_64" != "" ]; then
             iface_number_decimal=`expr ${iface_number_decimal:=0} + 1`
	     echo "iface_number_decimal is $iface_number_decimal"
	 else
	     # all interface start from 1.
	     iface_number_decimal="1"
	 fi
	 
	 if [ "$iface_number_decimal" -gt "65535" ]; then
	     # FIXME: if this value is out of range of 16bit, we must control upper 16bit.
	     echo "\$iface_number_decimal is too big..\
 it is limit to 65535 (last single block of IPv6, 16^4-1) in this script. sorry.."
	     echo "$0: Error: exit.."
	     exit 1;
	 fi
	 
	 # calculate IPv6 hex address
         iface_address=`echo 16o $iface_number_decimal p | dc`
	 
	 # determine subnet address incremental.
	 subnet=`expr "$subnet_start" + "$n" - 1`
	 if [ "$subnet" -gt "$subnet_end" ]; then
	     echo "$0: Error.. Over the limit of subnet range.. exit.."
	     echo "$0: Please specify more wide subnet range in virbr-v6enabler.conf,\
 or too much virbrN present.."
	     exit 1
	 else
	     subnet_hex=`echo 16o "$subnet" p | dc`
	     # ok, We get v6prefix /64..
	     v6prefix="$v6prefix_48""$subnet_hex"":"

 	     # add IPv6 address to virbrN interface.
	     v6_exist=`ip -6 addr | grep -A2 $i | grep inet6 | awk '{print $2}' | \
awk -F: '{print $1 $2 $3}'`
	     echo "v6_exist is $v6_exist"
	     v6prefix_num=`echo $v6prefix | awk -F: '{print $1 $2 $3}'`
	     echo "v6prefix_num is $v6prefix_num"

	     # if interface already has IPv6 address as same prefix, do nothing..
	     if [ "$v6_exist" != "$v6prefix_num" ]; then
		 echo "not equal.."
		 ip -6 addr add "$v6prefix":"$iface_address"/64 dev "$i" || \
		     echo "$0"": Error:line 144: ""ip -6 addr add ""$v6prefix"":""$iface_address""/64 dev"" $i"
                 # add IPv6 route to virtual network vrbrN.
		 ip -6 route add "$v6prefix":/64  dev "$i" mtu "$v_mtu" || \
		     echo "$0"": Error:line 147: ""ip -6 route add ""$v6prefix"":/64 dev ""$i"" mtu ""$v_mtu"
	     	     
                 # Print routing advisory.. 
		 default_dev=`ip -6 route | grep default | awk '{print $5}'`
		 gw_router=`ip -6 route | grep default | awk '{print $3}'`
		 v6network="$v6prefix"":/64"
		 host_linklocal=`ip -6 addr | grep -A4 "$default_dev" | \
                              grep "inet6" | grep "fe80" | awk '{print $2}' | \
                              sed -e 's/[/]64//g'`
		 if [ "$gw_router" != "" ]; then
		     may_be=", may be "
		 fi
		 echo "$0: Please add route _on your gateway router_""$may_be""$gw_router:\
 if the gw_router is a linux machine, example (on the router): "\
" ip -6 route add ""$v6network"" via ""$host_linklocal"" dev ""\$gw_ethN"" mtu 1280 "\
" ( \$gw_ethN is a interface on your gw router.. ex. eth1)"
	     else
		 echo "$0: $i already has IPv6 in same prefix.. nothing todo.."
	     fi
	 fi
     done
     # to enable ipv6 forwarding.. it's required by radvd working..
     v6_forwarding=`/sbin/sysctl -n net.ipv6.conf.all.forwarding`
     if [ "$v6_forwarding" = "0" ]; then
	 /sbin/sysctl -w net.ipv6.conf.all.forwarding=1 || \
	 echo "$0: Error:line 169: /sbin/sysctl -w net.ipv6.conf.all.forwarding=1"
     fi
else
    echo "$0: Error:line 173: No virbrN present.. Please check libvirt process, or libvirt network autostart setting."
    exit 1
fi

# finaly.. radvd wake up.. by default, too early to call radvd in
# rc*.d.. then may be failure to start..  radvd require
# net.ipv6.conf.all.forwarding=1 and virbrN interfaces bringed up.

# check radvd pid file..
if [ "$wakeup_radvd" = "yes" ]; then
    radvd_exec=`which radvd`
    if [ -x "$radvd_exec" ]; then 
         radvd_pid="/var/run/radvd/radvd.pid"
         if [ ! -s "$radvd_pid" ]; then
              /etc/init.d/radvd start
          fi
     fi
fi

#EOF 
