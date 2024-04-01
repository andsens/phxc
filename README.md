Setup home-cluster repo on TrueNAS

```
ssh-keygen -f deploy-key -t ed25519
git config --add --local core.sshCommand 'ssh -i /mnt/cluster/home-cluster/deploy-key'
```
