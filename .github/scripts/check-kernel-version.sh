#!/usr/bin/env bash
# Decide which Fedora releases need a kernel build, by comparing the newest
# upstream kernel against the newest one already published as a release.
#
# Run from the repo root. Needs GH_TOKEN and GITHUB_OUTPUT in the environment.
# Set FORCE=true to build regardless of what's published.
set -euo pipefail

for fc in 43 44; do
  # reuse the digest pin from the build container so there's one source of truth
  image=$(grep -oE '^FROM [^ ]+' "fc${fc}-action/Dockerfile" | cut -d' ' -f2)
  upstream=$(docker run --rm "$image" \
    dnf -q repoquery --latest-limit 1 --queryformat '%{version}-%{release}\n' kernel)

  # each build has its own release tagged with the kernel version it carries, so the
  # newest tag for this Fedora version is the published state - no version file to drift
  published=$(gh release list --limit 200 --json tagName,isDraft \
    --jq '.[] | select(.isDraft == false) | .tagName' 2>/dev/null |
    { grep -E "^[0-9].*\.fc${fc}$" || true; } | sort -V | tail -1)

  echo "fc${fc}-version=${upstream}" >>"$GITHUB_OUTPUT"
  if [ "$upstream" = "$published" ] && [ "${FORCE:-false}" != "true" ]; then
    echo "fc${fc}-build=false" >>"$GITHUB_OUTPUT"
    echo "::notice::fc${fc} is up to date at ${upstream}"
  else
    echo "fc${fc}-build=true" >>"$GITHUB_OUTPUT"
    echo "::notice::fc${fc} needs a build - upstream ${upstream}, published ${published:-none}"
  fi
done
