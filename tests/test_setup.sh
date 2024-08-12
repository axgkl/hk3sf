#!/usr/bin/env bash
test -z "${GITHUB_ACTIONS:-}" && . tests/environ # local testing
trap 'echo "Error on line $LINENO $BASH_COMMAND"' ERR

source "./main.sh" "$@"
report && echo donereport
ensure_requirements
ensure_proxy_server
ensure_k3s_via_proxy
ensure_proxy_is_loadbalancer
enable_local_kubectl
ensure_ingress_nginx_with_certmgr
report && echo reported
echo foo
