#!/usr/bin/env bash

PACKAGES+=(locales)

locales() {
  debconf-set-selections - <<<"tzdata  tzdata/Areas    select  Europe
tzdata  tzdata/Zones/Europe     select  Copenhagen
locales locales/locales_to_be_generated multiselect     en_US.UTF-8 UTF-8
locales locales/locales_to_be_generated multiselect     en_US.UTF-8 UTF-8"

  rm /etc/locale.gen
  dpkg-reconfigure --frontend noninteractive locales tzdata
}
