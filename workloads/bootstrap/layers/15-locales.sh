#!/usr/bin/env bash

PACKAGES+=(locales)

locales() {
  debconf-set-selections <<<"tzdata tzdata/Areas select Europe
  tzdata tzdata/Zones/Europe select Copenhagen
  locales locales/locales_to_be_generated multiselect     en_US.UTF-8 UTF-8
  locales locales/default_environment_locale      select  en_US.UTF-8
  ucf ucf/changeprompt select keep_current"

  rm /etc/locale.gen
  dpkg-reconfigure --frontend noninteractive locales tzdata
}
