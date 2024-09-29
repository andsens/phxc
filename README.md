# Home cluster

## Requirements

https://www.adrian.idv.hk/2022-09-30-diskless/
Linux or WSL

## Setup

### Clone & configure

- Clone this repo your (WSL) workspace
- Copy `config/config/home-cluster.template.yaml` to `config/config/home-cluster.yaml` and adjust values while you are doing the following:
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

Simply copy home-cluster.yaml from the NFS mount. It is regenerated every 24h
and bin/auth is built to be re-run.

# How to setup WSL

In your windows home directory setup mirrored networking for WSL:

```
[wsl2]
networkingMode = mirrored
# optional
dnsTunneling = true
```

The shutdown wsl with `wsl --shutdown`

Import the generated vhdx in windows with `wsl --import-in-place k8s-wsl D:\WSL\k8sWSL.vhdx`
To refresh an image, run `wsl --unregister k8s-wsl` and then import it again.

Setup Hyper-W firewall to allow incoming requests

## RaspberryPI5 init

- `rpi-otp-private-key -w -y -l 16 $(openssl rand -hex 64)`
- Enable PXE booting ("Network Boot") with Raspberry Pi Imager
