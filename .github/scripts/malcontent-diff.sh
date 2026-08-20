#!/usr/bin/env bash
# Diff the prior and proposed Action code with malcontent, leaving a result file
# behind even when malcontent finds nothing to report.
#
# Needs GITHUB_WORKSPACE and OLD_ACTION_TYPE/NEW_ACTION_TYPE, plus
# OLD_ACTION_IMAGE/NEW_ACTION_IMAGE when both sides are Docker Actions.
set -euo pipefail

results="malcontent-results.md"
malcontent="cgr.dev/chainguard/malcontent:latest"

if [ "$OLD_ACTION_TYPE" = docker ] && [ "$NEW_ACTION_TYPE" = docker ]; then
  echo "comparing images ${OLD_ACTION_IMAGE} against ${NEW_ACTION_IMAGE}"
  docker run --rm --privileged \
    -v /var/run/docker.sock:/var/run/docker.sock --user 0 \
    -v "${GITHUB_WORKSPACE}:/tmp" "$malcontent" \
    --format=markdown diff -i "$OLD_ACTION_IMAGE" "$NEW_ACTION_IMAGE" >"$results"
else
  docker run --rm --user 0 -v "${GITHUB_WORKSPACE}:/tmp" "$malcontent" \
    --format=markdown --min-file-risk=high diff /tmp/prior-commit /tmp/current-commit >"$results"
fi

if [ ! -s "$results" ]; then
  printf '## malcontent detects no changes\n\nyou may want to investigate manually\n' >"$results"
fi
