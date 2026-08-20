#!/usr/bin/env bash
# Import the RPM signing key and hand its fingerprint back as KEYID.
#
# Needs SIGNING_KEY (base64 of an armored private key) and GITHUB_ENV.
set -euo pipefail

base64 -d <<<"$SIGNING_KEY" | gpg --batch --import
gpg --list-secret-keys --with-colons |
  awk -F: '/^fpr/{print "KEYID="$10; exit}' >>"$GITHUB_ENV"
