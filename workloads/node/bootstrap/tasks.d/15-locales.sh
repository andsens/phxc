#!/usr/bin/env bash

locales() {
  rm /etc/timezone /etc/localtime
  debconf-set-selections - <<<"tzdata tzdata/Areas select Europe
tzdata tzdata/Zones/Europe select Copenhagen"
  dpkg-reconfigure --frontend noninteractive tzdata
}
