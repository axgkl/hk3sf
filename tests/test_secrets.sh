#!/usr/bin/env bash
set -euo pipefail

trap 'echo "Error on line $LINENO $BASH_COMMAND"' ERR

bash -c '. ./main.sh servers .id'

. ./main.sh import
test "$(servers)" == "$(. ./main.sh servers)"

digitalocean_dns_list | jq .name
echo success
