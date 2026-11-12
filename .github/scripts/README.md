# scripts for the github actions build jobs go here

All of them run from the repo root and read their inputs from the environment, so they're callable straight from a `run:` step. They set their own `set -euo pipefail`, so the workflow doesn't need to, and they're invoked directly rather than piped to a shell, so they need their executable bit.

| script | called by | environment it needs |
| --- | --- | --- |
| `check-kernel-version.sh` | `build-acs-kernel.yml`, `check` job | `GH_TOKEN`, `GITHUB_OUTPUT`, optional `FORCE=true` |
| `free-disk-space.sh` | `build-acs-kernel.yml`, both build jobs | nothing |
| `build-kernel-rpms.sh` | `build-acs-kernel.yml`, both build jobs; `pr-checks.yml`, `build-dependabot-PRs` | `FEDORA_RELEASE` (`43`/`44`), `RUNNER_TEMP`, `GITHUB_WORKSPACE`, optional `STUB=true` |
| `import-signing-key.sh` | `build-acs-kernel.yml`, `publish` job | `SIGNING_KEY`, `GITHUB_ENV` |
| `publish-yum-repo.sh` | `build-acs-kernel.yml`, `publish` job | `GH_TOKEN`, `REPO`, `KEYID`, `V43`, `V44`, `GITHUB_ENV` |
| `parse-action-diff.sh` | `malcontent-actions.yml`, `extract-action-repo` | `GH_TOKEN`, `PR_NUMBER`, `GITHUB_OUTPUT` |
| `setup-action-code.sh` | `malcontent-actions.yml`, `malcontent`, once per side | `SIDE` (`OLD`/`NEW`), `REPO`, `CHECKOUT`, `ACTION_DIR`, `GITHUB_ENV`, `GITHUB_STEP_SUMMARY` |
| `malcontent-diff.sh` | `malcontent-actions.yml`, `malcontent` | `GITHUB_WORKSPACE`, `OLD_ACTION_TYPE`, `NEW_ACTION_TYPE`, and the `*_ACTION_IMAGE` pair for Docker Actions |
| `comment-malcontent-results.sh` | `malcontent-actions.yml`, `comment` | `GH_TOKEN`, `REPO`, `PR_NUMBER` |

`check-kernel-version.sh` reads the Fedora image digest out of each `fc*-action/Dockerfile` rather than pinning it again, so Dependabot's Dockerfile updates stay the single source of truth.

`build-kernel-rpms.sh` runs the build container by hand instead of letting each `fc*-action` be a Docker Action, because the build needs `--security-opt seccomp=unconfined` and a Docker Action takes no docker flags. `kernel.spec` hmac-signs the kernel with `sha512hmac`, which hashes over an `AF_ALG` socket, and docker's builtin seccomp profile denies that socket on the ubuntu-26.04 runner image - the failure is `Allocation of hmac(sha512) cipher failed (ret=-1)` about 90 minutes into `%build`. Loosening AppArmor doesn't help and neither does loading `af_alg`/`algif_hash` on the host; seccomp is the only gate. The directories keep their `-action` names because `check-kernel-version.sh` and `dependabot.yml` both find the Dockerfiles by that path.

The script recreates the environment the runner used to hand the action: `HOME=/github/home` bound to `$RUNNER_TEMP/_github_home`, which is where `~/rpmbuild` lands and where the `upload-artifact` globs go looking for the RPMs, and the checkout bound to `/github/workspace` so `entrypoint.sh` can copy the ACS patch out of it. `GITHUB_OUTPUT` is pointed at `/dev/null`: the entrypoint writes a `kernel-version` output that no step ever read, since published versions come from the `check` job.

`STUB=true` is passed through to `entrypoint.sh`, which runs the whole prep and exits before `rpmbuild`. That's what Dependabot's PRs get: a base image bump or an action pin can break the build deps, `koji download-build`, or the spec surgery against whatever `kernel.spec` looks like upstream today, and all of that runs in the prep. What it can't break is the compile, so the PR check doesn't spend 90 minutes per Fedora release finding that out. A real kernel build is what the scheduled run is for.

`publish-yum-repo.sh` writes `PUBLISHED_FC43`/`PUBLISHED_FC44` to `GITHUB_ENV` naming the directory it just published, and the attestation steps key off those. That way a run only attests RPMs it actually released, rather than re-attesting the older ones it downloaded to rebuild the index.

`publish-yum-repo.sh` signs the RPMs before uploading them to the release, because the repo metadata carries checksums of the exact bytes that get served.

Releases here are immutable, so each build publishes its own release tagged with the kernel version it carries (`7.1.8-100.fc43`) instead of re-uploading to one rolling release. A published release won't accept new assets or let existing ones be deleted, which shapes three things: the RPMs are attached while the release is still a draft and it's published afterwards, retention prunes by deleting whole old releases rather than assets off a shared one, and a forced rebuild of a version that's already out indexes the published RPMs instead of the ones it just built, since those are the bytes people can actually download. The set of release tags is the state, which is also what `check-kernel-version.sh` compares upstream against, so there's no version file to drift.

Deleting a release burns its tag name for good, so a version whose release went away can never be published again: `gh release create --draft` still works, but publishing it 422s with `tag_name was used by an immutable release` and it stays a draft forever. Two things follow. `gh release view` and `gh release download` both succeed on a draft, so existence is checked with `--json isDraft` - otherwise a stuck draft reads as published and this version never gets built again while `check-kernel-version.sh`, which ignores drafts, keeps ordering the build. And a version that can't be published is left out of the index entirely rather than failing the run, because a draft's assets 404 for everyone but the token that uploaded them, and the next kernel version publishes normally.

Each kept release is indexed on its own with `createrepo_c --baseurl` pointing at that release's download URL, then `mergerepo_c --all` stitches them into the single repo Pages serves. Every package keeps the `xml:base` of the release hosting it, which is what lets one dnf repo span several immutable releases. The `--all` is load-bearing - without it `mergerepo_c` keeps only the newest version of each package, which is exactly the older kernels this is meant to retain.

Which Fedora versions get published comes from the release tags that exist, unioned with whatever built this run, rather than from a hardcoded list. So a Fedora version that goes EOL and drops out of the build jobs keeps its repodata and its last few kernels stay installable, instead of the whole-site deploy quietly removing its directory and leaving everyone still on it with a repo that 404s. `dnf` doesn't skip an unreachable repo by default, so that would break unrelated installs too, not just kernel updates. Retiring a Fedora version for real means deleting its releases by hand.

The cost of that is re-downloading every kept RPM on each publish, for every Fedora version including the EOL ones, so it grows as versions accumulate. If that gets tiresome, the fix is to build each release's `repodata` while it's still a draft and attach it as an asset, so later runs fetch that instead of the RPMs - it has to go on before publishing, because nothing can be added afterwards.

The public key is committed at `pages/RPM-GPG-KEY-acs-override` rather than exported from the keyring at publish time, so changing the trust anchor consumers import takes a reviewed commit instead of a deploy. `publish-yum-repo.sh` checks that committed key's fingerprint against the key it's actually signing with and fails the run on a mismatch, since publishing the two out of sync would break `gpgcheck` for everyone who already imported it.

`setup-action-code.sh` handles both sides of the malcontent comparison, picking its image name and summary wording off `SIDE`, because the two were otherwise identical.

Values reach these scripts through `env:` rather than `${{ }}` interpolated into the script body, which keeps a crafted branch or tag name from being expanded as shell.

Linting is `shellcheck` plus an executable-bit check, via `VALIDATE_BASH` and `VALIDATE_BASH_EXEC` in the super-linter step of `pr-checks.yml`, and the `shellcheck` and `check-shebang-scripts-are-executable` pre-commit hooks locally. Both pick this directory up on their own; super-linter has no default path exclusions.
