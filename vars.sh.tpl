#!/usr/bin/env bash
# shellcheck disable=2016,2034,2209

# Fixed IP address for the link between the host and the K8S VM
# Guide for setting up the bridge interface on TrueNAS:
# https://www.truenas.com/community/threads/is-there-any-way-to-enable-create-an-virtual-switch.95269/page-2#post-674816
# For a random IPv4 subnet use random.org 1-255 for the two groups after the "10."
# For a random IPv6 subnet use https://unique-local-ipv6.com/
TRUENAS_HOST_BRIDGE_SERVER_IP="[fd25:9998:d0e7:e351:1a01:be9:4d9a:157d]"
TRUENAS_HOST_BRIDGE_SERVER_IP_CIDR="fd25:9998:d0e7:e351:1a01:be9:4d9a:157d/128"

# Used to confirm ensure scripts are run on the correct machine
MACHINE_IDS_truenas='38a6ed82302b612fd55b9b69660a83e0'

TIMEZONE=Europe/Copenhagen

HOME_CLUSTER_NFS_SHARE=/mnt/cluster/home-cluster

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

# Generate with dbus-uuidgen
MACHINE_IDS['bootstrapper']='b8b235b3279c6054bc9f33ef6609287a'
TRUENAS_HOST_BRIDGE_CLIENT_IPs['bootstrapper']="10.15.180.3/24,fd25:9998:d0e7:e351:1a01:be9:4d9a:157f/48"
BOOTSTRAPPER_NFS_SHARE=/mnt/cluster/bootstrapper

#########################
### Cluster settings ###
#########################

MACHINE_IDS['k8s-nas']='2a178ed534ac2a67dbc8049d65eddc45'
TRUENAS_HOST_BRIDGE_CLIENT_IPs['k8s-nas']="10.15.180.2/24,fd25:9998:d0e7:e351:1a01:be9:4d9a:157e/48"
CLUSTER_NFS_SHARE=/mnt/cluster/workloads

# Name of the cluster, used in various contexts to identify it outwardly
# Spaces are allowed and might be replaced with _ or - depending on the context
# Examples:
# "$CLUSTER_NAME Root" and "$CLUSTER_NAME Intermediate" for step-ca certificate CN
CLUSTER_NAME="Elysium"

# For a random IPv6 subnet use https://unique-local-ipv6.com/
# https://github.com/cilium/cilium/issues/20756
CLUSTER_IPV4_CIDR="10.42.0.0/16"
CLUSTER_IPV6_CIDR="fd73:9867:6b4d:42::/56"
CLUSTER_IPV4_SERVICE_CIDR="10.43.0.0/16"
CLUSTER_IPV6_SERVICE_CIDR="fd73:9867:6b4d:43::/112"
