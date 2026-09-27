#!/usr/bin/env bash
# Runs `terraform test` in the bootstrap and in every module that has a tests/ folder.
# Tests use mocked providers, so no AWS credentials are needed.
set -euo pipefail

cd "$(dirname "$0")/.."

# A separate data directory keeps tests away from roots already initialized with the S3
# backend (which would need credentials); the plugin cache avoids downloading the provider
# once per directory.
export TF_DATA_DIR=".terraform-test"
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

for tests_dir in bootstrap/tests modules/*/tests; do
  config_dir="$(dirname "$tests_dir")"
  echo "==> ${config_dir}"
  terraform -chdir="$config_dir" init -input=false -backend=false >/dev/null
  terraform -chdir="$config_dir" test
done
