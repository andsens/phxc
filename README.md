Setup home-cluster repo on TrueNAS

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

Wipe a data disk:

```
wipefs -fa /dev/zvol/cluster/<DISK>
```

Setup smallstep trust:
step ca bootstrap --ca-url pki.$(bin/settings.sh get cluster.dns.domain):9000 \
	--fingerprint "$(step certificate fingerprint <(kubectl -n smallstep get secret smallstep-root -o=jsonpath='{.data.tls\.crt}' | base64 -d))"
