#!/usr/bin/env bash
# Sign the freshly built RPMs, publish them to the rolling release for their
# Fedora version, and build the repo metadata that Pages serves.
#
# Run from the repo root, after the build artifacts are downloaded to fresh/.
# Needs GH_TOKEN, REPO, KEYID, and V43/V44 (the kernel version per release).
set -euo pipefail

# kernel versions kept installable per Fedora release, so a kernel that breaks
# passthrough can be backed out with dnf downgrade
KEEP=5

printf '%%_gpg_name %s\n' "$KEYID" >~/.rpmmacros

mkdir -p site
cp -r pages/. site/

# the committed key is the trust anchor consumers import, so signing with anything
# else would break every gpgcheck out there - fail before publishing, not after
committed=$(gpg --show-keys --with-colons site/RPM-GPG-KEY-acs-override |
  awk -F: '/^fpr/{print $10; exit}')
if [ "$committed" != "$KEYID" ]; then
  echo "::error::pages/RPM-GPG-KEY-acs-override is ${committed}, but signing with ${KEYID}"
  exit 1
fi

# rpm --checksig reads rpm's own keyring, not gpg's
sudo rpm --import site/RPM-GPG-KEY-acs-override

# kernel-modules-extra-7.1.8-100.fc43.acs.x86_64.rpm -> 7.1.8-100.fc43.acs
version_of() {
  local n=${1##*/}
  n=${n%.x86_64.rpm}
  echo "${n#"${n%-*-*}-"}"
}

for fc in 43 44; do
  tag="fc${fc}-latest"
  dest="site/fc${fc}"
  mkdir -p "$dest"

  if [ -d "fresh/rpms-fc${fc}" ]; then
    mv "fresh/rpms-fc${fc}"/*.rpm "$dest"/
    # sign before upload: repodata carries checksums of the bytes that get served
    rpm --addsign "$dest"/*.rpm
    version_var="V${fc}"
    gh release create "$tag" --repo "$REPO" \
      --title "Fedora ${fc} ACS override kernel" --notes "Building..." || true
    gh release edit "$tag" --repo "$REPO" \
      --title "Fedora ${fc} ACS override kernel ${!version_var}" \
      --notes "Kernel ${!version_var} with Alex Williamson's ACS override patch applied."
    gh release upload "$tag" "$dest"/*.rpm --repo "$REPO" --clobber
  fi

  # the release is the state, so index whatever it holds rather than just what
  # built this run - otherwise a version drops out of the repo the day it's
  # superseded and reappears the next time this release sits a run out
  assets=$(gh release view "$tag" --repo "$REPO" --json assets \
    --jq '.assets[].name | select(endswith(".rpm"))' 2>/dev/null || true)
  if [ -z "$assets" ]; then
    echo "::warning::no RPMs published for ${tag} yet, leaving it out of the repo"
    # a failure here means the upload above landed but the listing came back empty
    rmdir "$dest"
    continue
  fi

  keep=$(while read -r asset; do version_of "$asset"; done <<<"$assets" |
    sort -u -V | tail -n "$KEEP")
  while read -r asset; do
    if grep -qxF "$(version_of "$asset")" <<<"$keep"; then
      # already local if it built this run, and it's the same signed bytes
      [ -f "$dest/$asset" ] ||
        gh release download "$tag" --repo "$REPO" --dir "$dest" --pattern "$asset"
    else
      echo "pruning ${asset}, past the newest ${KEEP} versions"
      gh release delete-asset "$tag" "$asset" --repo "$REPO" --yes
    fi
  done <<<"$assets"

  if rpm --checksig "$dest"/*.rpm | grep -v 'signatures OK'; then
    echo "::error::the RPMs above are unsigned, refusing to publish"
    exit 1
  fi

  createrepo_c --baseurl "https://github.com/${REPO}/releases/download/${tag}/" "$dest"
  gpg --batch --yes --detach-sign --armor "$dest/repodata/repomd.xml"
done
