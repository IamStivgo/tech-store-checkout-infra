#!/usr/bin/env bash
# Runs `terraform test` in the bootstrap and in every module that has a tests/ folder.
# Tests use mocked providers, so no AWS credentials are needed.
set -euo pipefail

cd "$(dirname "$0")/.."

for tests_dir in bootstrap/tests modules/*/tests; do
  config_dir="$(dirname "$tests_dir")"
  echo "==> ${config_dir}"
  terraform -chdir="$config_dir" init -input=false -backend=false >/dev/null
  terraform -chdir="$config_dir" test
done
