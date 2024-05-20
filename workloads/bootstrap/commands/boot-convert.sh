#!/usr/bin/env bash
# shellcheck source-path=../../../
set -Eeo pipefail; shopt -s inherit_errexit
CONTEXT=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
PKGROOT=$(realpath "$CONTEXT/../../..")

main() {
  source "$PKGROOT/lib/common.sh"
  DOC="boot-convert - Convert a docker image into bootable disk
Usage:
  boot-convert [options] IMAGE

Options:
  --format FORMAT  The output format (raw or vhdx) [default: raw]
"
# docopt parser below, refresh this parser with `docopt.sh boot-convert.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh" '2.0.0a3' || {
ret=$?;printf -- "exit %d\n" "$ret";exit "$ret";};set -e
trimmed_doc=${DOC:0:170};usage=${DOC:57:37};digest=b0c97;options=(' --format 1')
node_0(){ value __format 0;};node_1(){ value IMAGE a;};node_2(){ optional 0;}
node_3(){ sequence 2 1;};cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" \
"$1" >&2;printf "%s\n" "${DOC:57:37}" >&2;exit 1;}';local varnames=(__format \
IMAGE) varname;for varname in "${varnames[@]}"; do unset "var_$varname";done
parse 3 "$@";local p=${DOCOPT_PREFIX:-''};for varname in "${varnames[@]}"; do
unset "$p$varname";done;eval $p'__format=${var___format:-raw};'$p'IMAGE=${var_'\
'IMAGE:-};';local docopt_i=1;[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2;for \
((;docopt_i>0;docopt_i--)); do for varname in "${varnames[@]}"; do declare -p \
"$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh"' boot-convert.sh`
  eval "$(docopt "$@")"

  docker build \
    --file "$PKGROOT/workloads/bootstrap/containers/base/Dockerfile" \
    --tag "cr.$CLUSTER_DOMAIN/base" \
    "$PKGROOT"
  docker build \
    --build-arg "IMAGE=cr.$CLUSTER_DOMAIN/base" \
    --file "$PKGROOT/workloads/bootstrap/containers/boot-convert/Dockerfile" \
    --tag "pki.$CLUSTER_DOMAIN/boot-convert" \
    "$PKGROOT"

  local tar="$PKGROOT/images/${IMAGE#*/}.tar"
  local boot_convert_src
  boot_convert_src=$(docker create -q "$IMAGE")
  # shellcheck disable=SC2064
  trap "docker rm \"$boot_convert_src\"" EXIT
  docker export "$boot_convert_src" -o "$tar"
  docker rm "$boot_convert_src"
  # shellcheck disable=SC2064
  trap "rm -f \"$tar\"" EXIT

  # shellcheck disable=SC2154
  docker run --rm \
    -v "$PKGROOT:/var/lib/home-cluster:ro" \
    -v "$PKGROOT/images:/var/lib/home-cluster/images:rw" \
    --cap-add SYS_ADMIN \
    --device /dev/loop5:/dev/loop5 \
    --device /dev/loop6:/dev/loop6 \
    --device /dev/loop-control:/dev/loop-control \
    pki.$CLUSTER_DOMAIN/boot-convert --format "$__format" "/var/lib/home-cluster/images/$(basename "$tar")"
}

main "$@"
