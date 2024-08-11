#!/usr/bin/env bash

source "./main.sh" import

ensure_local_ssh_key # call, when $FN_SSH_KEY possibly not present
check_requirements
#images
#ssh_keys
#ensure_ip_forwarder "37.27.193.230"
#postinstall "37.27.193.230"
ensure_proxy_server
#postinstall "37.27.193.230"
ensure_k3s_via_proxy
ensure_proxy_is_loadbalancer
enable_local_kubectl

ensure_ingress_nginx_with_certmgr

# test_autoscale
report
#
