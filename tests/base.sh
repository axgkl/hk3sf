#!/usr/bin/env bash
set -euo pipefail
source "tests/environ"
bash -c '. ./main.sh servers .id' # standalone call (only in bash)

. ./main.sh
test "$(shw servers)" == "$(. ./main.sh servers)"
shw digitalocean_dns_list | jq .id

echo success
