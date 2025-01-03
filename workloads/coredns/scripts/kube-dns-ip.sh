#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

main() {
  # Calculate the kube-dns IPs using the svc CIDR
  local ipv4 ipv6
  ipv4=$(kubectl -n kube-system get cm cilium-config -ojsonpath='{.data.ipv4-service-range}' | (cidrex -4 || true) | head -n11 | tail -n1)
  ipv6=$(kubectl -n kube-system get cm cilium-config -ojsonpath='{.data.ipv6-service-range}' | (cidrex -6 || true) | head -n11 | tail -n1)
  printf -- 'kind: ResourceList
items:
- apiVersion: v1
  kind: ConfigMap
  metadata:
    name: kube-dns-ip
  data:
    ipv4: "%s"
    ipv6: "%s"' "$ipv4" "$ipv6"
}

usage() {
  printf "Usage: kube-dns-ip.sh\n" >&2
  return 1
}

main "$@"
