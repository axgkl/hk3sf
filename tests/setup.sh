#!/usr/bin/env bash
source "tests/environ"
source "./main.sh" "$@"
shw ensure_requirements
shw ensure_proxy_server
shw ensure_k3s_via_proxy
shw ensure_proxy_is_loadbalancer
shw ensure_local_kubectl
shw ensure_ingress_nginx
shw ensure_cert_manager
report

false && . ../setup.sh && . ../main.sh && . ../pkg/ingress.sh || true
