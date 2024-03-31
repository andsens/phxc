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
TRUENAS_HOST_BRIDGE_CLIENT_IPs['bootstrapper']="10.15.180.3/24,fd25:9998:d0e7:e351:1a01:be9:4d9a:157f/48"
BOOTSTRAPPER_NFS_SHARE=/mnt/cluster/bootstrapper
BOOTSTRAPPER_GIT_REMOTE=https://github.com/andsens/home-cluster.git
# Leave empty if using a public repo
BOOTSTRAPPER_GIT_DEPLOY_KEY=
BOOTSTRAPPER_GIT_REMOTE_SSH_KEYS=
# When cloning via ssh you will need to trust the remote. For GitHub the keys are:
# BOOTSTRAPPER_GIT_REMOTE_SSH_KEYS='|1|8jHpq1TRdjyRbwBRcH23I2OLtF8=|uk+0m7ScMP+V/M4ZfiVkyohWKDA= ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
# |1|uQiPao7vfX6EtebIPrakQdTFeGA=|9xWf68bM3DiK+EkkE4T/ExnNHbg= ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
# |1|E/XNHmuoBRKRPJu+eHMyjYli4g0=|q735yv4k6923UkPMM9b78WgBFTA= ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'

#########################
### Cluster settings ###
#########################

MACHINE_IDS['k8s-nas']='2a178ed534ac2a67dbc8049d65eddc45'
TRUENAS_HOST_BRIDGE_CLIENT_IPs['k8s-nas']="10.15.180.2/24,fd25:9998:d0e7:e351:1a01:be9:4d9a:157e/48"

# Name of the cluster, used in various contexts to identify it outwardly
# Spaces are allowed and might be replaced with _ or - depending on the context
# Examples:
# "$CLUSTER_NAME Root" and "$CLUSTER_NAME Intermediate" for step-ca certificate CN
CLUSTER_NAME="Elysium"

# The name of the context for the cluster, used by the apply.sh scripts
CLUSTER_CONTEXT=k3s

# For a random IPv6 subnet use https://unique-local-ipv6.com/
# https://github.com/cilium/cilium/issues/20756
CLUSTER_IPV4_CIDR="10.42.0.0/16"
CLUSTER_IPV6_CIDR="fd73:9867:6b4d:42::/56"
CLUSTER_IPV4_SERVICE_CIDR="10.43.0.0/16"
CLUSTER_IPV6_SERVICE_CIDR="fd73:9867:6b4d:43::/112"

CLUSTER_NFS_SERVER_IP="10.15.180.1"
CLUSTER_NFS_SERVER_IP_CIDR="10.15.180.0/32"
CLUSTER_NFS_SHARE=/mnt/cluster/storage/workloads
CLUSTER_NFS_SUBDIR='${pvc.metadata.namespace}/${pvc.metadata.name}'
