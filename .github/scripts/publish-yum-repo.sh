#!/usr/bin/env bash
# Sign the freshly built RPMs, publish each Fedora version's build as its own
# immutable release, and build the repo metadata that Pages serves.
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

# Every build gets its own release, tagged with the kernel version it carries
# (7.1.8-100.fc43), because releases here are immutable: assets can't be added to
# or removed from one once it's published. So the tag names the Fedora version it
# belongs to and sorts within it, and the set of releases is the repo's state.
# Drafts are skipped - their assets aren't public, so indexing one would put a URL
# in the repodata that dnf can't fetch.
releases=$(gh release list --repo "$REPO" --limit 200 --json tagName,isDraft \
  --jq '.[] | select(.isDraft == false) | .tagName | select(test("^[0-9].*\\.fc[0-9]+$"))')

# Publish every Fedora version that has a release, not just the ones still being
# built. A version that's gone EOL and dropped out of the build list keeps its
# repodata this way, so its last few kernels stay installable - otherwise the
# whole-site deploy drops its directory and dnf 404s on the repo it still has
# configured. Union with what built this run, since the first build of a new
# Fedora version has no release yet.
fcs=$({
  printf '%s\n' "$releases" | sed -nE 's/.*\.fc([0-9]+)$/\1/p'
  # a glob rather than find, so a missing fresh/ isn't a pipefail that exits the
  # whole script without printing why
  for dir in fresh/rpms-fc*; do
    [ -d "$dir" ] && printf '%s\n' "${dir##*/rpms-fc}"
  done
  true
} | sort -un)

for fc in $fcs; do
  work="work/fc${fc}"

  if [ -d "fresh/rpms-fc${fc}" ]; then
    version_var="V${fc}"
    tag=${!version_var}
    # isDraft, not just existence: a draft that never flipped to published looks
    # like a release to `gh release view` but its assets are private, so treating
    # it as done blocks this version forever while the build job keeps rebuilding it
    existing=$(gh release view "$tag" --repo "$REPO" --json isDraft --jq .isDraft 2>/dev/null || true)
    if [ "$existing" = "false" ]; then
      # a forced rebuild of a version that's already out: the published assets are
      # frozen and are what the repodata has to describe, so the rebuilt RPMs go
      # unused rather than being indexed as bytes nobody can download
      echo "::warning::${tag} is already released and immutable, indexing what it published"
      releases=$(printf '%s\n%s' "$releases" "$tag")
    else
      # a leftover draft holds no tag and nothing public points at it, so drop it
      # and republish from this build rather than adopting assets nobody can fetch
      if [ -n "$existing" ]; then
        echo "::warning::${tag} was left as a draft, deleting it and publishing this build"
        gh release delete "$tag" --repo "$REPO" --yes
      fi
      mkdir -p "$work/$tag"
      mv "fresh/rpms-fc${fc}"/*.rpm "$work/$tag"/
      # sign before upload: repodata carries checksums of the bytes that get served
      rpm --addsign "$work/$tag"/*.rpm
      # publishing is what freezes a release, so the assets have to go on while it's
      # still a draft.  Publishing is also where it can fail for good: immutable
      # releases burn a tag name when a release is deleted, so a version whose
      # release went away can never be published again.  Warn and index without it
      # instead of failing, so the repo keeps serving the versions that do exist and
      # the next kernel publishes normally.
      if gh release create "$tag" --repo "$REPO" --draft \
        --title "kernel-acs-${tag}" \
        --notes "Fedora ${fc} kernel ${tag} with ACS override patch applied." \
        "$work/$tag"/*.rpm &&
        gh release edit "$tag" --repo "$REPO" --draft=false &&
        [ "$(gh release view "$tag" --repo "$REPO" --json isDraft --jq .isDraft)" = "false" ]; then
        # only the RPMs this run actually published are worth attesting
        printf 'PUBLISHED_FC%s=%s\n' "$fc" "$work/$tag" >>"${GITHUB_ENV:-/dev/null}"
        releases=$(printf '%s\n%s' "$releases" "$tag")
      else
        # left out of $releases on purpose: an unpublished release's assets 404 for
        # everyone but this token, and indexing them hands dnf URLs it can't fetch
        echo "::warning::could not publish ${tag}, leaving it out of the repo - a deleted release burns its tag name for good"
        rm -rf "${work:?}/${tag:?}"
      fi
    fi
  fi

  mine=$(printf '%s\n' "$releases" | { grep -E "\.fc${fc}\$" || true; } | sort -u -V)
  kept=$(printf '%s\n' "$mine" | tail -n "$KEEP")

  # retention is per release now: pruning a version means deleting the whole thing,
  # since picking assets off one isn't allowed
  for tag in $mine; do
    if ! grep -qxF "$tag" <<<"$kept"; then
      echo "pruning release ${tag}, past the newest ${KEEP} versions"
      gh release delete "$tag" --repo "$REPO" --yes
    fi
  done

  merge_args=()
  for tag in $kept; do
    dir="$work/$tag"
    if [ ! -d "$dir" ]; then
      mkdir -p "$dir"
      gh release download "$tag" --repo "$REPO" --dir "$dir" --pattern '*.rpm'
    fi
    # sudo, because --import above wrote the key into root's keyring and an
    # unprivileged --checksig reports every package NOKEY.  Collected rather than
    # piped into `if`, because pipefail makes the condition read rpm's nonzero exit
    # instead of grep's match, which is exactly backwards.
    unsigned=$(sudo rpm --checksig "$dir"/*.rpm | grep -v 'signatures OK' || true)
    if [ -n "$unsigned" ]; then
      printf '%s\n' "$unsigned"
      echo "::error::the RPMs above are unsigned, refusing to publish"
      exit 1
    fi
    createrepo_c --baseurl "https://github.com/${REPO}/releases/download/${tag}/" "$dir"
    merge_args+=("--repo=$dir")
  done

  # each package keeps the xml:base of the release hosting it, which is what lets one
  # dnf repo span several immutable releases instead of one mutable release
  mergerepo_c --all "${merge_args[@]}" -o "site/fc${fc}"
  gpg --batch --yes --detach-sign --armor "site/fc${fc}/repodata/repomd.xml"
done
