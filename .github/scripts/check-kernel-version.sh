#!/usr/bin/env bash
# Decide which Fedora releases need a kernel build, by comparing the newest
# upstream kernel against the RPMs already published to the rolling releases.
#
# Run from the repo root. Needs GH_TOKEN and GITHUB_OUTPUT in the environment.
# Set FORCE=true to build regardless of what's published.
set -euo pipefail

for fc in 43 44; do
  # reuse the digest pin from the build container so there's one source of truth
  image=$(grep -oE '^FROM [^ ]+' "fc${fc}-action/Dockerfile" | cut -d' ' -f2)
  upstream=$(docker run --rm "$image" \
    dnf -q repoquery --latest-limit 1 --queryformat '%{version}-%{release}\n' kernel)

  # the published RPM filenames are the state, so there's no version file to drift
  assets=$(gh release view "fc${fc}-latest" --json assets --jq '.assets[].name' 2>/dev/null || true)
  published=$(printf '%s\n' "$assets" |
    sed -nE 's/^kernel-core-(.+)\.x86_64\.rpm$/\1/p' | sed 's/\.acs//' | head -1)

  echo "fc${fc}-version=${upstream}" >>"$GITHUB_OUTPUT"
  if [ "$upstream" = "$published" ] && [ "${FORCE:-false}" != "true" ]; then
    echo "fc${fc}-build=false" >>"$GITHUB_OUTPUT"
    echo "::notice::fc${fc} is up to date at ${upstream}"
  else
    echo "fc${fc}-build=true" >>"$GITHUB_OUTPUT"
    echo "::notice::fc${fc} needs a build - upstream ${upstream}, published ${published:-none}"
  fi
done
