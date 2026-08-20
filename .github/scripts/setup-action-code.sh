#!/usr/bin/env bash
# Work out how a checked-out Action is built, and build it if it's a Docker one,
# so malcontent has something comparable on both sides of the diff.
#
# Run from the repo root. Needs SIDE (OLD or NEW), REPO, CHECKOUT (where the
# Action under test was checked out), ACTION_DIR (the Action's subdirectory
# within that checkout, may be empty), GITHUB_ENV, and GITHUB_STEP_SUMMARY.
set -euo pipefail

case "$SIDE" in
  OLD) image_name=prior-action-image label=original ;;
  NEW) image_name=new-action-image label="proposed new" ;;
  *)
    echo "::error::SIDE must be OLD or NEW, got '${SIDE}'"
    exit 1
    ;;
esac

cd "$CHECKOUT"
if [ -n "$ACTION_DIR" ]; then
  echo "changing directory to ${ACTION_DIR}"
  cd "$ACTION_DIR"
fi

# the reads below assume action.yml, but upstream may spell it action.yaml
if [ -f action.yaml ]; then
  mv action.yaml action.yml
fi

type=$(yq '.runs.using' action.yml)
echo "${SIDE}_ACTION_TYPE=${type}" >>"$GITHUB_ENV"

case "$type" in
  docker)
    image=$(yq '.runs.image' action.yml)
    if [ "$image" = "Dockerfile" ]; then
      echo "this Action ships a Dockerfile, building it"
      tag="ghcr.io/${REPO}/${image_name}:latest"
      docker build -t "$tag" .
      docker push "$tag"
      echo "${SIDE}_ACTION_IMAGE=${tag}" >>"$GITHUB_ENV"
    else
      echo "this Action uses a pre-built image: ${image}"
      echo "${SIDE}_ACTION_IMAGE=$(cut -d/ -f3- <<<"$image")" >>"$GITHUB_ENV"
    fi
    ;;
  node*)
    echo "this Action runs on Node.js, installing dependencies"
    npm install
    ;;
  composite*)
    echo "the ${label} Action is a composite Action, skipping build." >>"$GITHUB_STEP_SUMMARY"
    ;;
esac
