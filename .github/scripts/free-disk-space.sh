#!/usr/bin/env bash
# Make room for a kernel build on a stock GitHub-hosted runner.
set -euo pipefail

sudo apt-get -qq purge build-essential "ghc*"
sudo apt-get clean
# cleanup docker images not used by us
docker system prune -af
# free up a lot of stuff from /usr/local
sudo rm -rf /usr/local
df -h
