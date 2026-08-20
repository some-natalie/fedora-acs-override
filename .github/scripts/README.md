scripts for the github actions build jobs go here

All of them run from the repo root and read their inputs from the environment, so they're callable straight from a `run:` step. They set their own `set -euo pipefail`, so the workflow doesn't need to, and they're invoked directly rather than piped to a shell, so they need their executable bit.

| script | called by | environment it needs |
| --- | --- | --- |
| `free-disk-space.sh` | `build-acs-kernel.yml`, both build jobs | nothing |
| `parse-action-diff.sh` | `malcontent-actions.yml`, `extract-action-repo` | `GH_TOKEN`, `PR_NUMBER`, `GITHUB_OUTPUT` |
| `setup-action-code.sh` | `malcontent-actions.yml`, `malcontent`, once per side | `SIDE` (`OLD`/`NEW`), `REPO`, `CHECKOUT`, `ACTION_DIR`, `GITHUB_ENV`, `GITHUB_STEP_SUMMARY` |
| `malcontent-diff.sh` | `malcontent-actions.yml`, `malcontent` | `GITHUB_WORKSPACE`, `OLD_ACTION_TYPE`, `NEW_ACTION_TYPE`, and the `*_ACTION_IMAGE` pair for Docker Actions |
| `comment-malcontent-results.sh` | `malcontent-actions.yml`, `comment` | `GH_TOKEN`, `REPO`, `PR_NUMBER` |

`setup-action-code.sh` handles both sides of the malcontent comparison, picking its image name and summary wording off `SIDE`, because the two were otherwise identical.

Values reach these scripts through `env:` rather than `${{ }}` interpolated into the script body, which keeps a crafted branch or tag name from being expanded as shell.

Linting is `shellcheck` plus an executable-bit check, via `VALIDATE_BASH` and `VALIDATE_BASH_EXEC` in the super-linter step of `pr-checks.yml`, and the `shellcheck` and `check-shebang-scripts-are-executable` pre-commit hooks locally. Both pick this directory up on their own; super-linter has no default path exclusions.
