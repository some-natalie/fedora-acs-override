#!/usr/bin/env bash
# Sign the freshly built RPMs, publish them to the rolling release for their
# Fedora version, and build the repo metadata that Pages serves.
#
# Run from the repo root, after the build artifacts are downloaded to fresh/.
# Needs GH_TOKEN, REPO, KEYID, and V43/V44 (the kernel version per release).
set -euo pipefail

printf '%%_gpg_name %s\n' "$KEYID" >~/.rpmmacros

mkdir -p site
cp -r pages/. site/
gpg --armor --export "$KEYID" >site/RPM-GPG-KEY-acs-override
# rpm --checksig reads rpm's own keyring, not gpg's
sudo rpm --import site/RPM-GPG-KEY-acs-override

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
  else
    # untouched this run, but the site deploy replaces everything, so re-index it
    gh release download "$tag" --repo "$REPO" --dir "$dest" --pattern '*.rpm' || {
      echo "::warning::no release published for ${tag} yet, leaving it out of the repo"
      rm -rf "$dest"
      continue
    }
  fi

  if rpm --checksig "$dest"/*.rpm | grep -v 'signatures OK'; then
    echo "::error::the RPMs above are unsigned, refusing to publish"
    exit 1
  fi

  createrepo_c --baseurl "https://github.com/${REPO}/releases/download/${tag}/" "$dest"
  gpg --batch --yes --detach-sign --armor "$dest/repodata/repomd.xml"
done
