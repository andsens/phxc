#!/usr/bin/env bash

PACKAGES+=(locales)

locales() {
  rm /etc/locale.gen /etc/timezone /etc/localtime
  debconf-set-selections - <<<"tzdata tzdata/Areas select Europe
tzdata tzdata/Zones/Europe select Copenhagen
locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8
locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8"
  dpkg-reconfigure --frontend noninteractive locales tzdata
}
