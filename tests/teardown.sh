#!/usr/bin/env bash

test -z "${GITHUB_ACTIONS:-}" && . tests/environ # local testing
source "./main.sh" --force rm
