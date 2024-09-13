#!/usr/bin/env bash
trap 'echo "Error on line $LINENO $BASH_COMMAND"' ERR
d="$(builtin cd "$(dirname "$0")" && pwd)"
source "$d/../main.sh" "$@"
report

false && . ../setup.sh && . ../main.sh && . ../pkg/ingress.sh || true
