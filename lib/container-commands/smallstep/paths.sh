#!/bin/bash
# shellcheck source-path=../../..
# shellcheck disable=SC2034

: "${STEPPATH:?}"

ROOT_KEY_PATH=$STEPPATH/persistent-certs/root_ca_key
ROOT_CRT_PATH=$STEPPATH/persistent-certs/root_ca.crt

INTERMEDIATE_KEY_PATH=$STEPPATH/persistent-certs/intermediate_ca_key
INTERMEDIATE_CRT_PATH=$STEPPATH/persistent-certs/intermediate_ca.crt

KUBE_CLIENT_CA_KEY_PATH=$STEPPATH/certs/kube_apiserver_client_ca_key
KUBE_CLIENT_CA_CRT_PATH=$STEPPATH/certs/kube_apiserver_client_ca.crt
