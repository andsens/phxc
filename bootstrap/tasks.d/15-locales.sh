#!/usr/bin/env bash

locales_pre_install() {
  PACKAGES+=(tzdata)
  DEBCONF_SELECTIONS+=(
    "tzdata tzdata/Areas select Europe"
    "tzdata tzdata/Zones/Europe select Copenhagen"
  )
  if $DEBUG; then
    PACKAGES+=(locales)
    DEBCONF_SELECTIONS+=(
      "locales locales/default_environment_locale select en_US.UTF-8"
      "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8"
    )
  fi
  rm -f /etc/timezone /etc/localtime
}
