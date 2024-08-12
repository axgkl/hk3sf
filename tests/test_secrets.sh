#!/usr/bin/env bash
set -euo pipefail
test -z "${GITHUB_ACTIONS:-}" && . tests/environ # local testing
trap 'echo "Error on line $LINENO $BASH_COMMAND"' ERR

bash -c '. ./main.sh servers .id' # standalone call (only in bash)

. ./main.sh
test "$(servers)" == "$(. ./main.sh servers)"
digitalocean_dns_list | jq .id

echo success
set -x
report
echo foo
exit 1
