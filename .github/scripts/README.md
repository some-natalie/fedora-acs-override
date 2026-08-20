# scripts for the github actions build jobs go here

All of them run from the repo root and read their inputs from the environment, so they're callable straight from a `run:` step. They set their own `set -euo pipefail`, so the workflow doesn't need to, and they're invoked directly rather than piped to a shell, so they need their executable bit.

| script | called by | environment it needs |
| --- | --- | --- |
| `check-kernel-version.sh` | `build-acs-kernel.yml`, `check` job | `GH_TOKEN`, `GITHUB_OUTPUT`, optional `FORCE=true` |
| `free-disk-space.sh` | `build-acs-kernel.yml`, both build jobs | nothing |
| `import-signing-key.sh` | `build-acs-kernel.yml`, `publish` job | `SIGNING_KEY`, `GITHUB_ENV` |
| `publish-yum-repo.sh` | `build-acs-kernel.yml`, `publish` job | `GH_TOKEN`, `REPO`, `KEYID`, `V43`, `V44` |
| `parse-action-diff.sh` | `malcontent-actions.yml`, `extract-action-repo` | `GH_TOKEN`, `PR_NUMBER`, `GITHUB_OUTPUT` |
| `setup-action-code.sh` | `malcontent-actions.yml`, `malcontent`, once per side | `SIDE` (`OLD`/`NEW`), `REPO`, `CHECKOUT`, `ACTION_DIR`, `GITHUB_ENV`, `GITHUB_STEP_SUMMARY` |
| `malcontent-diff.sh` | `malcontent-actions.yml`, `malcontent` | `GITHUB_WORKSPACE`, `OLD_ACTION_TYPE`, `NEW_ACTION_TYPE`, and the `*_ACTION_IMAGE` pair for Docker Actions |
| `comment-malcontent-results.sh` | `malcontent-actions.yml`, `comment` | `GH_TOKEN`, `REPO`, `PR_NUMBER` |

`check-kernel-version.sh` reads the Fedora image digest out of each `fc*-action/Dockerfile` rather than pinning it again, so Dependabot's Dockerfile updates stay the single source of truth.

`publish-yum-repo.sh` signs the RPMs before uploading them to the release, because the repo metadata carries checksums of the exact bytes that get served.

It indexes whatever the release holds rather than only what built this run, and prunes the release to the newest `KEEP` versions. Both halves matter: a Pages deploy replaces the whole site, so a release that didn't rebuild still has to be re-indexed or it vanishes from the repo, and indexing only the fresh build would drop older kernels from the repo the day they're superseded only for them to reappear the next time that release sat a run out. Keeping several versions is deliberate, since a kernel that breaks passthrough wants backing out with `dnf downgrade`. The cost is re-downloading the kept RPMs on each publish, which retention bounds.

The public key is committed at `pages/RPM-GPG-KEY-acs-override` rather than exported from the keyring at publish time, so changing the trust anchor consumers import takes a reviewed commit instead of a deploy. `publish-yum-repo.sh` checks that committed key's fingerprint against the key it's actually signing with and fails the run on a mismatch, since publishing the two out of sync would break `gpgcheck` for everyone who already imported it.

`setup-action-code.sh` handles both sides of the malcontent comparison, picking its image name and summary wording off `SIDE`, because the two were otherwise identical.

Values reach these scripts through `env:` rather than `${{ }}` interpolated into the script body, which keeps a crafted branch or tag name from being expanded as shell.

Linting is `shellcheck` plus an executable-bit check, via `VALIDATE_BASH` and `VALIDATE_BASH_EXEC` in the super-linter step of `pr-checks.yml`, and the `shellcheck` and `check-shebang-scripts-are-executable` pre-commit hooks locally. Both pick this directory up on their own; super-linter has no default path exclusions.
