#!/usr/bin/env bash
# gcp-use.sh — multi-account helper: list and switch named gcloud configurations.
# Usage:
#   gcp-use.sh list                                   show profiles + current identity
#   gcp-use.sh <profile> [--adc] [--impersonate SA]   switch profile
#   source gcp-use.sh <profile> [...]                 switch + export CLOUDSDK_ACTIVE_CONFIG_NAME

_gcp_use_sourced=0
if [ "${BASH_SOURCE[0]}" != "$0" ]; then _gcp_use_sourced=1; fi
if [ "$_gcp_use_sourced" = 0 ]; then set -euo pipefail; fi

gcp_use_main() {
  local cmd="${1:-list}"
  case "$cmd" in
    -h|--help)
      sed -n '2,6p' "${BASH_SOURCE[0]}"
      ;;
    list)
      gcloud config configurations list
      echo
      echo "active account: $(gcloud config get-value account 2>/dev/null)"
      echo "active project: $(gcloud config get-value project 2>/dev/null)"
      if gcloud auth application-default print-access-token >/dev/null 2>&1; then
        echo "ADC:            present"
      else
        echo "ADC:            missing/expired (run: gcloud auth application-default login)"
      fi
      ;;
    *)
      local profile="$cmd" adc=0 impersonate=""
      shift || true
      while [ $# -gt 0 ]; do
        case "$1" in
          --adc) adc=1; shift ;;
          --impersonate) impersonate="${2:?--impersonate needs an SA email}"; shift 2 ;;
          *) echo "unknown flag: $1" >&2; return 1 ;;
        esac
      done
      if ! gcloud config configurations describe "$profile" >/dev/null 2>&1; then
        echo "profile '$profile' does not exist. Create it first:" >&2
        echo "  gcloud config configurations create $profile" >&2
        echo "  gcloud config set account you@example.com --configuration=$profile" >&2
        echo "  gcloud config set project  PROJECT_ID       --configuration=$profile" >&2
        echo "  gcloud auth login --configuration=$profile" >&2
        return 1
      fi
      gcloud config configurations activate "$profile"
      export CLOUDSDK_ACTIVE_CONFIG_NAME="$profile"
      echo "active profile: $profile"
      echo "account:        $(gcloud config get-value account 2>/dev/null)"
      echo "project:        $(gcloud config get-value project 2>/dev/null)"
      if [ -n "$impersonate" ]; then
        gcloud auth application-default login --impersonate-service-account="$impersonate"
      elif [ "$adc" = 1 ]; then
        gcloud auth application-default login
      elif ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
        echo "warning: ADC missing/expired — re-run with --adc or --impersonate <SA>" >&2
      else
        echo "note: ADC is global; if it belongs to another account, re-run with --adc"
      fi
      if [ "$_gcp_use_sourced" = 0 ]; then
        echo
        echo "tip: 'source ${BASH_SOURCE[0]} $profile' to export CLOUDSDK_ACTIVE_CONFIG_NAME here"
      fi
      ;;
  esac
}

gcp_use_main "$@"
