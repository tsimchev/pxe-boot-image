# About
All in one PXE Boot Docker Image based on *MAC* addresses.

# Build PXE Image
```shell
docker build -t iict/acad/pxe:1.0 .
```

# Run PXE Container

## Create VLAN interface on the Docker Host
The interface connects to the PXE VLAN network target for installation
```shell
iface ens172.16 inet static
  address 172.16.0.253 # Will act as router
  netmask 255.255.255.0
```

## Create Docker Network
The network allows Docker container to connect to the PXE network
```shell
docker network create -d macvlan -o parent=ens172.16 \
    --subnet=172.16.0.0/16 \
    --gateway=172.16.0.253 \
    pxe
```

## Work with PXE Server
Starts container that serves PXE.

- **path/to/iso** is the absolute path to the image (Tested with RedHat 8)
- **path/to/kickstart** is the location to a *kickstart file generator* script.
The PXE container will call this script for every host target of installation,
setting its *MAC* address as an environment variable.

### Kickstart File Generator (Example script)
```shell
#!/bin/bash

case ${MAC:?} in

  "82:0f:30:e6:d4:01")
    HOSTNAME="one.corp.local"
    ;;

  "82:0f:30:e6:d4:04")
    HOSTNAME="one.corp.local"
    ;;
esac

cat <<EOF
ignoredisk --only-use=sda

network --bootproto=dhcp --device=em1 --hostname=$HOSTNAME

# Partition clearing information
clearpart --all

# Use text install
text

# Create APPStream Repo
repo --name="AppStream" --baseurl=file:///run/install/repo/AppStream

# Use HTTP Repo
# url --url http://<ip>/<path>

# Keyboard layouts
keyboard --vckeymap=us --xlayouts='us'
EOF
```

### Run PXE Server
```shell
docker run -d \
    --restart unless-stopped \
    # Container static IP has to be same as PXE_IP
    --ip 172.16.0.252 \
    # VLAN Docker network
    --net=pxe \
    # Operating System ISO
    -v path/to/iso:/iso \
    # Kickstart file generator
    -v path/to/kickstart:/kickstart \
    # MAC Addresses of the hosts target of installation
    -e MACS=82:0f:30:e6:d4:01,82:0f:30:e6:d4:04 \
    # DHCPD Range
    -e CIDR=172.16.0.0/24 \
    # DHCPD Gateway
    -e GATEWAY=172.16.0.253 \
    # DHCPD DNS
    -e DNS=172.16.0.253 \
    # PXE TFTP, HTTP endpoints
    -e PXE_IP=172.16.0.252 \
    iict/acad/pxe:1.0
```
