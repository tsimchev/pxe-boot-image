#!/bin/sh

set -e

TFTP_PATH="/var/lib/tftpboot"
TFTP_PXE_PATH=$TFTP_PATH/pxelinux
TFTP_PXE_CFG_PATH=$TFTP_PXE_PATH/pxelinux.cfg
TFTP_LOG="/tmp/tftp.log"
DHCP_CONF=/etc/dhcp/dhcpd.conf
HTTP="/http"

# Switch between Docker BUILD (SERVICE in args) and RUN (SERVICE not in args)
[[ $1 != "SERVICE" ]] && {
	# TFPT folders and permissions
	mkdir -p $TFTP_PXE_CFG_PATH
	chmod -R 755 $TFTP_PATH
	chown -R nobody:nogroup $TFTP_PATH
	touch $TFTP_LOG
	chmod 777 $TFTP_LOG

	# Obtain Syslinux binaries (Rhel 8 already have them as part of the image)
	SYSLINUX_URL=https://cdn.kernel.org/pub/linux/utils/boot/syslinux/3.xx/syslinux-3.86.zip
	SYSLINUX_DIR=/syslinux
	SYSLINUX_TMP=/tmp/syslinux.zip

    yum -y update
	yum -y install \
		git curl unzip lsof ipcalc jq awk xorriso-1.4.8 \
		python3-3.7.3 atftp-0.7.2 dhcp-server-4.3.5

	# Install Syslinux
	curl -L $SYSLINUX_URL --output $SYSLINUX_TMP
	unzip $SYSLINUX_TMP -d $SYSLINUX_DIR
	rm -rf $SYSLINUX_TMP

	mkdir -p $TFTP_PXE_CFG_PATH
	cp $SYSLINUX_DIR/core/pxelinux.0 $TFTP_PXE_PATH
	chmod +x $0
	exit 0
}

# Templates for configuration file generation
pxelinux_msg(){
cat <<EOF
Welcome to PXE Boot installation screen

Press 1 - Install fresh Red Hat Enterprise Linux [DEFAULT]
Press 2 - Boot from Harddisk
EOF
}

pxelinux_cfg(){
cat <<EOF
timeout 600
display pxelinux.msg
default 1
prompt  1

label 1
  menu label ^Install Red Hat Enterprise Linux
  kernel vmlinuz
  append initrd=initrd.img showopts ks=http://$PXE_IP:80/$MAC_NAME/kickstart.cfg ip=dhcp net.ifnames=0 biosdevname=0

label 2
  menu label Boot from ^Local Drive
  localboot 0x80

menu end
EOF
}

dhcp_conf(){
cat <<EOF
default-lease-time 600;
max-lease-time 7200;
authoritative;
log-facility local7;
allow booting;
allow bootp;
option client-system-arch code 93 = unsigned integer 16;

subnet $(cidr NETWORK) netmask $(cidr NETMASK) {
   option routers $GATEWAY;
   option subnet-mask $(cidr NETMASK);
   option broadcast-address $(cidr BROADCAST);
   option domain-name-servers $DNS;
   range $(cidr MINADDR) $(cidr MAXADDR); 
   next-server $PXE_IP;
   deny unknown-clients;
}

class "pxeclients" {
   next-server $PXE_IP;
   filename "pxelinux/pxelinux.0";
}

EOF
}

dhcp_conf_host(){
cat <<EOF
host $HOSTNAME {
    hardware ethernet $MAC;
}

EOF
}

# Validate Input
: {MACS:?} {CIDR:?} {GATEWAY:?} {DNS:?} {PXE_IP:?}

# Normalize MACs
IFS=',' read -ra MACS <<< $MACS

# Set PXE Boot Welcome message
pxelinux_msg > $TFTP_PXE_PATH/pxelinux.msg

# Set initial DHCPD configuration
cidr(){ ipcalc $CIDR --json | jq -r .$1; }; dhcp_conf > $DHCP_CONF

# Create PXE targeted hosts specific configuration
INDEX=0
for MAC in ${MACS[@]}; do
	((INDEX=INDEX+1))

	# Generate namespace based on MAC
	MAC_NAME=$(sed s/:/-/g <<< $MAC)

	# Generate temporary hostname
	HOSTNAME=host-$INDEX

	# Configure PXE for host
	pxelinux_cfg > $TFTP_PXE_CFG_PATH/01-$MAC_NAME

	# Configure DHCPD for host
	dhcp_conf_host >> $DHCP_CONF

	# Generate Kickstart for host
	mkdir -p $HTTP/$MAC_NAME/
	export MAC && bash "/kickstart" > $HTTP/$MAC_NAME/kickstart.cfg
done

# Configure TFTP - Extract ISO
xorriso -osirrox on -indev /iso -extract / $TFTP_PATH/image
cp $TFTP_PATH/image/images/pxeboot/{vmlinuz,initrd.img} $TFTP_PXE_PATH

# Report hosts installation status by monitor TFTP connections
while $(sleep 5); do lsof -i:69; done &

# Run TFTP in background
/usr/sbin/in.tftpd \
	--maxthread 300 \
	--logfile $TFTP_LOG \
	--verbose=7 \
	--trace \
	--daemon \
	--user tftp \
	/var/lib/tftpboot &

# Run DHCPD in background
/usr/sbin/dhcpd -4 -f -d --no-pid -cf $DHCP_CONF eth0 &

# Run HTTP in background
python3 -m http.server -d $HTTP
