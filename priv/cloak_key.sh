#!/usr/bin/env sh
set -eu

# 32 bytes, standard base64, one line. Cloak decodes this to the AES-256 key.
head -c 32 /dev/urandom | base64
