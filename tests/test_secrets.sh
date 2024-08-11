#!/usr/bin/env bash
set -euo pipefail

trap 'echo "Error on line $LINENO $BASH_COMMAND"' ERR

bash -c '. ./main.sh servers .id' # standalone call (only in bash)

. ./main.sh import
test "$(servers)" == "$(. ./main.sh servers)"

echo "$DOMAIN"
echo "xxx$DOMAIN"
digitalocean_dns_list | jq .id
echo success
