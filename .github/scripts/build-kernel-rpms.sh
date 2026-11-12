#!/usr/bin/env bash
# Build the ACS kernel RPMs for one Fedora release in its own build container.
set -euo pipefail

action_dir="fc${FEDORA_RELEASE}-action"
image="kernel-acs-fc${FEDORA_RELEASE}"
# HOME inside the container, host side. The upload-artifact globs in
# build-acs-kernel.yml read the finished RPMs back out of this path.
build_home="${RUNNER_TEMP}/_github_home"

mkdir -p "$build_home"
docker build --tag "$image" "$action_dir"

# seccomp=unconfined is the whole reason this isn't a Docker Action: kernel.spec
# hmac-signs the kernel with sha512hmac, which hashes over an AF_ALG socket, and
# docker's builtin seccomp profile denies that socket on ubuntu-26.04 runners.
# A Docker Action takes no docker flags, so the run has to be spelled out here.
# The env and mounts below are what the runner used to set up for the action.
# GITHUB_OUTPUT goes nowhere because nothing consumes the entrypoint's
# kernel-version output - the check job is where the published versions come from.
docker run --rm \
  --security-opt seccomp=unconfined \
  --workdir /github/workspace \
  --env HOME=/github/home \
  --env GITHUB_OUTPUT=/dev/null \
  --env GITHUB_WORKSPACE=/github/workspace \
  --env "STUB=${STUB:-false}" \
  --volume "${build_home}:/github/home" \
  --volume "${GITHUB_WORKSPACE}:/github/workspace" \
  "$image"
