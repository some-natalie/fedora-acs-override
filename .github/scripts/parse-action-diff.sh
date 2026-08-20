#!/usr/bin/env bash
# Work out which Action a pull request re-pinned, by diffing its `uses:` lines.
#
# Needs GH_TOKEN, PR_NUMBER, and GITHUB_OUTPUT. Sets `changed=false` and exits
# clean when the PR touched a workflow without moving an Action pin.
set -euo pipefail

gh pr diff "$PR_NUMBER" >pr.diff

old_line=$(grep '^-' pr.diff | grep 'uses:' | tail -1 || true)
new_line=$(grep '^+' pr.diff | grep 'uses:' | tail -1 || true)

if [ -z "$old_line" ] || [ -z "$new_line" ]; then
  echo "changed=false" >>"$GITHUB_OUTPUT"
  echo "::notice::no Action pin moved in this PR, nothing to analyze"
  exit 0
fi

# `uses: org/repo@ref` or `uses: org/repo/sub/dir@ref`, still carrying its diff
# marker and possibly a trailing `# v1.2.3` version comment
parse_uses() {
  local line=$1 prefix=$2
  local use path rest org repo dir ref

  use=$(sed -E 's/^[-+][[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//' <<<"$line")
  ref=${use##*@}
  path=${use%@*}
  org=${path%%/*}
  rest=${path#*/}
  repo=${rest%%/*}
  dir=${rest#"$repo"}
  dir=${dir#/}

  {
    echo "${prefix}_action_org=${org}"
    echo "${prefix}_action_repo=${repo}"
    echo "${prefix}_action_dir=${dir}"
    echo "${prefix}_ref=${ref}"
  } >>"$GITHUB_OUTPUT"

  echo "${prefix}: org=${org} repo=${repo} dir=${dir:-<none>} ref=${ref}"
}

parse_uses "$old_line" old
parse_uses "$new_line" new
echo "changed=true" >>"$GITHUB_OUTPUT"
