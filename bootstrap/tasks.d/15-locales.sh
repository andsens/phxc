#!/usr/bin/env bash

PACKAGES+=(tzdata)
if $DEBUG; then
  PACKAGES+=(locales)
fi

locales() {
  rm -f /etc/timezone /etc/localtime
  debconf-set-selections - <<<"tzdata tzdata/Areas select Europe
tzdata tzdata/Zones/Europe select Copenhagen"
  dpkg-reconfigure --frontend noninteractive tzdata
  if $DEBUG; then
    debconf-set-selections - <<<"locales locales/default_environment_locale select en_US.UTF-8
locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8"
    dpkg-reconfigure --frontend noninteractive locales
  fi
}
