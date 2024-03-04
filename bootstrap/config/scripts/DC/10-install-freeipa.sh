#!/usr/bin/env bash

error=0; trap 'error=$(($?>$error?$?:$error))' ERR # save maximum error code

fcopy -Sm root,root,0744 /usr/local/sbin/freeipa
fcopy -SM /etc/systemd/system/freeipa.service
fcopy -Sm root,root,0600 /etc/freeipa/ipa-server-install-options
$ROOTCMD systemctl enable freeipa.service
mkdir "${target:?}/var/lib/freeipa"

exit $error
