#!/bin/sh

# Snatched from https://github.com/dracutdevs/dracut/blob/5d2bda46f4e75e85445ee4d3bd3f68bf966287b9/modules.d/98dracut-systemd/parse-root.sh#L9

type getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh

# Skip the entire root checking. get-rootimg does that
root=$(getarg root=)
rootok=1
