#!/usr/bin/env bash
# shellcheck disable=2016,2034,2209

# Fixed IP addresses for the link between the host and the K8S VM
# Guide for setting up the bridge interface on TrueNAS:
# https://www.truenas.com/community/threads/is-there-any-way-to-enable-create-an-virtual-switch.95269/page-2#post-674816
# For a random IPv4 subnet use random.org 1-255 for the two groups after the "10."
# For a random IPv6 subnet use https://unique-local-ipv6.com/
declare -A TRUENAS_HOST_BRIDGE_CLIENT_IPs
TRUENAS_HOST_BRIDGE_SERVER_IP="[fd25:9998:d0e7:e351:1a01:be9:4d9a:157d]"

# Generate with dbus-uuidgen
declare -A MACHINE_IDS

TIMEZONE=Europe/Copenhagen
APTPROXY=http://localhost:3142

TRUENAS_PERSISTENT_VOLUME_DEV_PATH=/dev/vdb

######################
### Admin settings ###
######################

ADMIN_UID=3000
ADMIN_USERNAME=admin
ADMIN_USER_SHELL=/usr/bin/zsh
# Generate with mkpasswd (from the `whois` package) and make sure to single quote
ADMIN_PASSWORD='$y$j9T$3vODFlaqbGjodgu9KgDcE0$qa4856yiPK5.vw/iX0FZbbrYdmwR0HzcVvuRkbopBRC'
ADMIN_AUTH_KEYS='ssh-rsa ...
ssh-rsa ...'
ADMIN_NFS_HOME_SHARE=/mnt/cluster/home/...

#############################
### Bootstrapper settings ###
#############################

MACHINE_IDS['bootstrapper']='b8b235b3279c6054bc9f33ef6609287a'
TRUENAS_HOST_BRIDGE_CLIENT_IPs[bootstrapper]="10.15.180.3/24,fd25:9998:d0e7:e351:1a01:be9:4d9a:157f/48"
BOOTSTRAPPER_NFS_IMAGES_SHARE=/mnt/cluster/images

#########################
### Cluster settings ###
#########################

MACHINE_IDS['k8s-nas']='2a178ed534ac2a67dbc8049d65eddc45'
TRUENAS_HOST_BRIDGE_CLIENT_IPs[k8s-nas]="10.15.180.2/24,fd25:9998:d0e7:e351:1a01:be9:4d9a:157e/48"

# Name of the cluster, used in various contexts to identify it outwardly
# Spaces are allowed and might be replaced with _ or - depending on the context
# Examples:
# "$CLUSTER_NAME Root" and "$CLUSTER_NAME Intermediate" for step-ca certificate CN
CLUSTER_NAME="Elysium"

# The name of the context for the cluster, used by the apply.sh scripts
CLUSTER_CONTEXT=k3s

# For a random IPv6 subnet use https://unique-local-ipv6.com/
# https://github.com/cilium/cilium/issues/20756
CLUSTER_IP4_CIDR="10.42.0.0/16"
CLUSTER_IP6_CIDR="fd73:9867:6b4d:42::/56"
CLUSTER_IP4_SERVICE_CIDR="10.43.0.0/16"
CLUSTER_IP6_SERVICE_CIDR="fd73:9867:6b4d:43::/112"

CLUSTER_NFS_SERVER_IP="10.15.180.1"
CLUSTER_NFS_SERVER_IP_CIDR="10.15.180.0/32"
CLUSTER_NFS_SHARE=/mnt/cluster/storage/workloads
CLUSTER_NFS_SUBDIR='${pvc.metadata.namespace}/${pvc.metadata.name}'
