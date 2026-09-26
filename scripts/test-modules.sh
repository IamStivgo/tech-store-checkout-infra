#!/usr/bin/env bash
# Runs `terraform test` in every module that has a tests/ folder. Tests use mocked
# providers, so no AWS credentials are needed.
set -euo pipefail

cd "$(dirname "$0")/.."

for tests_dir in modules/*/tests; do
  module_dir="$(dirname "$tests_dir")"
  echo "==> ${module_dir}"
  terraform -chdir="$module_dir" init -input=false -backend=false >/dev/null
  terraform -chdir="$module_dir" test
done
