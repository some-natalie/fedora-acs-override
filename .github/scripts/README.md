# scripts for the github actions build jobs go here

All of them run from the repo root and read their inputs from the environment, so they're callable straight from a `run:` step. They set their own `set -euo pipefail`, so the workflow doesn't need to, and they're invoked directly rather than piped to a shell, so they need their executable bit.

| script | called by | environment it needs |
| --- | --- | --- |
| `check-kernel-version.sh` | `build-acs-kernel.yml`, `check` job | `GH_TOKEN`, `GITHUB_OUTPUT`, optional `FORCE=true` |
| `free-disk-space.sh` | `build-acs-kernel.yml`, both build jobs | nothing |
| `import-signing-key.sh` | `build-acs-kernel.yml`, `publish` job | `SIGNING_KEY`, `GITHUB_ENV` |
| `publish-yum-repo.sh` | `build-acs-kernel.yml`, `publish` job | `GH_TOKEN`, `REPO`, `KEYID`, `V43`, `V44`, `GITHUB_ENV` |
| `parse-action-diff.sh` | `malcontent-actions.yml`, `extract-action-repo` | `GH_TOKEN`, `PR_NUMBER`, `GITHUB_OUTPUT` |
| `setup-action-code.sh` | `malcontent-actions.yml`, `malcontent`, once per side | `SIDE` (`OLD`/`NEW`), `REPO`, `CHECKOUT`, `ACTION_DIR`, `GITHUB_ENV`, `GITHUB_STEP_SUMMARY` |
| `malcontent-diff.sh` | `malcontent-actions.yml`, `malcontent` | `GITHUB_WORKSPACE`, `OLD_ACTION_TYPE`, `NEW_ACTION_TYPE`, and the `*_ACTION_IMAGE` pair for Docker Actions |
| `comment-malcontent-results.sh` | `malcontent-actions.yml`, `comment` | `GH_TOKEN`, `REPO`, `PR_NUMBER` |

`check-kernel-version.sh` reads the Fedora image digest out of each `fc*-action/Dockerfile` rather than pinning it again, so Dependabot's Dockerfile updates stay the single source of truth.

`publish-yum-repo.sh` writes `PUBLISHED_FC43`/`PUBLISHED_FC44` to `GITHUB_ENV` naming the directory it just published, and the attestation steps key off those. That way a run only attests RPMs it actually released, rather than re-attesting the older ones it downloaded to rebuild the index.

`publish-yum-repo.sh` signs the RPMs before uploading them to the release, because the repo metadata carries checksums of the exact bytes that get served.

Releases here are immutable, so each build publishes its own release tagged with the kernel version it carries (`7.1.8-100.fc43`) instead of re-uploading to one rolling release. A published release won't accept new assets or let existing ones be deleted, which shapes three things: the RPMs are attached while the release is still a draft and it's published afterwards, retention prunes by deleting whole old releases rather than assets off a shared one, and a forced rebuild of a version that's already out indexes the published RPMs instead of the ones it just built, since those are the bytes people can actually download. The set of release tags is the state, which is also what `check-kernel-version.sh` compares upstream against, so there's no version file to drift.

Each kept release is indexed on its own with `createrepo_c --baseurl` pointing at that release's download URL, then `mergerepo_c --all` stitches them into the single repo Pages serves. Every package keeps the `xml:base` of the release hosting it, which is what lets one dnf repo span several immutable releases. The `--all` is load-bearing - without it `mergerepo_c` keeps only the newest version of each package, which is exactly the older kernels this is meant to retain.

Which Fedora versions get published comes from the release tags that exist, unioned with whatever built this run, rather than from a hardcoded list. So a Fedora version that goes EOL and drops out of the build jobs keeps its repodata and its last few kernels stay installable, instead of the whole-site deploy quietly removing its directory and leaving everyone still on it with a repo that 404s. `dnf` doesn't skip an unreachable repo by default, so that would break unrelated installs too, not just kernel updates. Retiring a Fedora version for real means deleting its releases by hand.

The cost of that is re-downloading every kept RPM on each publish, for every Fedora version including the EOL ones, so it grows as versions accumulate. If that gets tiresome, the fix is to build each release's `repodata` while it's still a draft and attach it as an asset, so later runs fetch that instead of the RPMs - it has to go on before publishing, because nothing can be added afterwards.

The public key is committed at `pages/RPM-GPG-KEY-acs-override` rather than exported from the keyring at publish time, so changing the trust anchor consumers import takes a reviewed commit instead of a deploy. `publish-yum-repo.sh` checks that committed key's fingerprint against the key it's actually signing with and fails the run on a mismatch, since publishing the two out of sync would break `gpgcheck` for everyone who already imported it.

`setup-action-code.sh` handles both sides of the malcontent comparison, picking its image name and summary wording off `SIDE`, because the two were otherwise identical.

Values reach these scripts through `env:` rather than `${{ }}` interpolated into the script body, which keeps a crafted branch or tag name from being expanded as shell.

Linting is `shellcheck` plus an executable-bit check, via `VALIDATE_BASH` and `VALIDATE_BASH_EXEC` in the super-linter step of `pr-checks.yml`, and the `shellcheck` and `check-shebang-scripts-are-executable` pre-commit hooks locally. Both pick this directory up on their own; super-linter has no default path exclusions.
