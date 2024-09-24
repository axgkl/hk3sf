#!/usr/bin/env bash
d="$(builtin cd "$(dirname "$0")" && pwd)"
. "$d/environ"
. "$d/../main.sh" "$@"
report

false && . ../setup.sh && . ../main.sh && . ../pkg/ingress.sh || true
