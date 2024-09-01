#!/usr/bin/env bash

escape_key() {
  # Converts any path like some-path.to-something.here
  # into ["some-path"]["to-something"]["here"]
  # This means dots in keys are not allowed
  local key=$1
  key=${key//'.'/'"]["'}
  key="[\"$key\"]"
  printf "%s\n" "$key"
}
