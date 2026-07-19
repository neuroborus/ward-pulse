#!/usr/bin/env bash
set -euo pipefail

readonly VALIDATOR_VERSION="1.7.0"
readonly VALIDATOR_ASSET_ID="464497818"
readonly VALIDATOR_SHA256="3a10def0521ab97f41ab1b7e27a35649370af51580603b5bf656604d88f1aa29"

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}"
validator_dir="${cache_root}/wardpulse/wff-validator/${VALIDATOR_VERSION}"
validator_jar="${validator_dir}/wff-validator.jar"

validator_is_valid() {
  [[ -f "${validator_jar}" ]] &&
    printf '%s  %s\n' "${VALIDATOR_SHA256}" "${validator_jar}" |
      sha256sum --check --status
}

if ! validator_is_valid; then
  mkdir -p "${validator_dir}"
  temporary_jar="$(mktemp "${validator_jar}.tmp.XXXXXX")"
  trap 'rm -f -- "${temporary_jar}"' EXIT

  curl -fsSL \
    -H "Accept: application/octet-stream" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/google/watchface/releases/assets/${VALIDATOR_ASSET_ID}" \
    -o "${temporary_jar}"
  printf '%s  %s\n' "${VALIDATOR_SHA256}" "${temporary_jar}" | sha256sum --check
  mv -- "${temporary_jar}" "${validator_jar}"
  trap - EXIT
fi

java -jar "${validator_jar}" \
  1 \
  "${repo_root}/apps/watchface_wff/src/main/res/raw/watchface.xml"
