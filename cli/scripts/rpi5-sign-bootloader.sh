#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg
source "$PKGROOT/.upkg/records.sh/records.sh"

FIRMWARE_DIR=/usr/lib/firmware/raspberrypi/bootloader-2712/stable
EEPROM_SIZE=2097152

# Make sure we use the latest firmware
apt-get update -qq
apt-get install -qq rpi-eeprom

main() {
  [[ $# -le 1 ]] || usage
  [[ $# -eq 0 || $1 = -r ]] || usage
  local e; for e; do [[ $e != --help ]] || usage; done
  sign_recovery_bin=false
  [[ $1 != -r ]] || sign_recovery_bin=true

  local secureboot_key=/run/secrets/secureboot.key \
        secureboot_pub=/run/secrets/secureboot.pub \
        pieeprom \
        orig_dir sign_dir

  verbose "Validating secureboot key"
  openssl rsa -in $secureboot_key -noout -check | pipe_verbose || fatal "Secureboot key must be a 2048 bit RSA key"
  [[ $(openssl rsa -in $secureboot_key -noout -text) =~ Private-Key:\ \(([0-9]+)\ bit, ]] || fatal "Unable to determine secureboot keysize"
  [[ ${BASH_REMATCH[1]} = 2048 ]] || fatal "Secureboot key must be a 2048 bit RSA key (got %d bit)" "${BASH_REMATCH[1]}"
  openssl rsa -in $secureboot_key -pubout >$secureboot_pub 2> >(pipe_verbose)

  pieeprom=$(LC_ALL=C compgen -G "$FIRMWARE_DIR/pieeprom-*.bin" | head -n1)
  [[ $(stat -c%s "$pieeprom") = "$EEPROM_SIZE" ]] || fatal "Sanity check failed. Size of %s is not %d bytes" "$pieeprom" "$EEPROM_SIZE"

  orig_dir=$(mktemp -d); sign_dir=$(mktemp -d)

  info "Signing bootloader"

  verbose "Extracting latest pieeprom.bin"
  # Creates bootcode.bin, bootconf.sig, bootconf.txt, cacert.der, pubkey.bin
  (cd "$orig_dir"; rpi-eeprom-config --extract "$pieeprom")

  verbose "Counter-signing bootcode.bin"
  rpi-sign-bootcode --chip 2712 \
                    --private-keynum 16 \
                    --private-version 0 \
                    --private-key $secureboot_key \
                    --input "$orig_dir/bootcode.bin" \
                    --output "$sign_dir/bootcode.bin"

  verbose "Signing bootconf.txt"
  rpi-eeprom-digest -k $secureboot_key \
                    -i /assets/bootconf.rpi5-secureboot.txt \
                    -o "$sign_dir/bootconf.sig"

  verbose "Creating pieeprom.bin with counter-signed bootcode.bin"
  rpi-eeprom-config --config /assets/bootconf.rpi5-secureboot.txt \
                    --digest "$sign_dir/bootconf.sig" \
                    --bootcode "$sign_dir/bootcode.bin" \
                    --pubkey $secureboot_pub \
                    --out /run/rpi5-bootloader/pieeprom.bin \
                    "$pieeprom"

  verbose "Signing pieeprom.bin"
  rpi-eeprom-digest -k $secureboot_key \
                    -i /run/rpi5-bootloader/pieeprom.bin \
                    -o /run/rpi5-bootloader/pieeprom.sig

  if $sign_recovery_bin; then
    info "Signing recovery.bin"
    rpi-sign-bootcode --chip 2712 \
                      --private-keynum 16 \
                      --private-version 0 \
                      --private-key $secureboot_key \
                      --input $FIRMWARE_DIR/recovery.bin \
                      --output /run/rpi5-bootloader/bootcode5.bin
  else
    verbose "Copying recovery.bin to flashing dir"
    cp $FIRMWARE_DIR/recovery.bin /run/rpi5-bootloader/bootcode5.bin
  fi

  verbose "Copying config.txt to flashing dir"
  cp /assets/config.rpi5-secureboot.txt /run/rpi5-bootloader/config.txt

  info "RaspberryPi 5 bootloader signed"
}

usage() {
  printf "Usage: rpi-sign-bootloader.sh [-r]\n\nOptions:\n  -r  Sign recovery.bin" >&2
  return 1
}

main "$@"
