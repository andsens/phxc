# Home cluster

## Requirements

Linux or WSL

## Setup

### Clone & configure

- Clone this repo your (WSL) workspace
- Copy `settings.template.yaml` to settings.yaml and adjust values while you are doing the following:
  - Create the TrueNAS host bridge
    - Make sure to enable DHCP on the main NIC again after creating the host bridge
  - Clone this repo to your NAS
  - Run bin/install-deps on your NAS
  - Create NFS mounts
  - Setup VMs
- Run `bin/install-deps`
- Add cronjob on your NAS to run `lib/machine-commands/update-machines`
- `fai-mk-configspace`
- Run `bin/bootstrap k8sMaster bootstrapper`
- Copy the resulting images to your NAS
- Run `tools/replace-disk.sh k8sMaster` and `tools/replace-disk.sh bootstrapper`
- Start k8sMaster

### Setting up a TrueNAS host bridge

- In order to securely mount NFS shares from your TrueNAS to your VMs Create a
  For a random IPv4 subnet use random.org 1-255 for the two groups after the "10."
  For a random IPv6 subnet use https://unique-local-ipv6.com/

### Setup home-cluster repo on TrueNAS

```
git init home-cluster
cd home-cluster
ssh-keygen -f deploy-key -t ed25519
# Add deploy-key.pub to github repo
git config --add --local core.sshCommand 'ssh -i /mnt/cluster/home-cluster/deploy-key'
git remote add origin git@github.com:<REPO>
git fetch origin
git reset --hard origin/master
```

### Wipe a data disk:

```
wipefs -fa /dev/zvol/cluster/<DISK>
```

### Setup smallstep trust

step ca bootstrap --ca-url pki.$(bin/settings get cluster.domain):9000 \
	--fingerprint "$(step certificate fingerprint <(kubectl -n smallstep get secret smallstep-root -o=jsonpath='{.data.tls\.crt}' | base64 -d))"

### Trust host SSH certificates

`printf "@cert-authority *.local %s\n" "$(step ssh config --host --roots)" >>$HOME/.ssh/known_hosts`

# Cool features

- Security for untrusted network
- cilium networking
- k3s is bare-bones
- Config changes kept to a minimum

# How to reauth when init admin cert has expired
