#!/usr/bin/env bash
# Post the malcontent results to the pull request that triggered this run.
#
# Needs GH_TOKEN, REPO, and PR_NUMBER, with malcontent-results.md alongside.
set -euo pipefail

gh pr comment "$PR_NUMBER" --repo "$REPO" --body-file malcontent-results.md
