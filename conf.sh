DFLT_IMG="${IMG:-ubuntu-24.04}" # https://github.com/vitobotta/hetzner-k3s/issues/387#issuecomment-2248702070 ff
DFLT_TYPE="${SERVER:-cx22}"

: "${NAME:=k3s}"
: "${AUTOSCALED_COUNT:=3}"
: "${AUTOSCALED_IMG:=$DFLT_IMG}"
: "${AUTOSCALED_TYPE:=$DFLT_TYPE}"
: "${PROXY_IMG:=$DFLT_IMG}"
: "${PROXY_TYPE:=$DFLT_TYPE}"
# Ports the external LB will listen on. After changes: ensure_proxy_is_loadbalancer and ensure_ingress_nginx_with_certmgr
: "${PROXY_LB:=80;443}"
: "${CACHE_DIR:=$(pwd)/tmp}"
# how long hcloud api GET results are remembered, w/o triggering now api calls. Non GET ops autoclear the cache.
: "${CACHE_SECS:=60}"
: "${CIDR_CLUSTER:=10.50.0.0/16}"
: "${CIDR_SERVICE:=10.60.0.0/16}"
# flannel or cilium
: "${CNI:=cilium}"
: "${DNS_CLUSTER:=10.60.0.10}"
: "${EMAIL:=}"
: "${DNS_PROVIDER:=}"
: "${DNS_API_TOKEN:=}"
: "${DOMAIN:=example.com}"
: "${FN_KUBECONFIG:=$HOME/.kube/$NAME.yml}"
: "${FN_LINK_KUBECONFIG:=$HOME/.kubeconfig}"
: "${FN_LOG:=$(pwd)/tmp/install.log}"
: "${FN_SSH_KEY:=$HOME/.ssh/id_rsa}"
# Read only token - in use for most functions:
: "${HCLOUD_TOKEN:=}"
: "${HCLOUD_TOKEN_WRITE:=}"
: "${HOST_NETWORK:=0}" # 10.$HOST_NETWORK.0.0/16 net, named "ten-$HOST_NETWORK"
: "${HOST_NETWORK_NAME:=ten-$HOST_NETWORK}"
: "${LOCATION:=hel1}"
: "${LOG_DBG_CLR:=2;37}"
: "${MASTERS_ARE_WORKERS:=true}"
: "${MASTERS_COUNT:=3}"
: "${MASTERS_IMG:=$DFLT_IMG}"
: "${MASTERS_TYPE:=$DFLT_TYPE}"
: "${REGISTRY_MIRROR:=true}"
: "${SSH_PORT:=22}"
: "${SSH_TUNNEL_PORT:=16443}"
# Until v2 is released, this contains a few patches:
: "${URL_HETZNER_K3S:=https://github.com/axgkl/binaries/raw/master/hetzner-k3s}"
# xcaddy with lb4 module added - in use when proxy is lb:
: "${URL_CADDY:=https://github.com/axgkl/binaries/raw/master/caddy-amd64}"
: "${VER_K3S:=v1.30.2+k3s2}" # registry mirror requires k3s > 1.30.2
: "${WORKERS_COUNT:=0}"
: "${WORKERS_IMG:=$DFLT_IMG}"
: "${WORKERS_TYPE:=$DFLT_TYPE}"

#URL_HETZNER_K3S="https://github.com/vitobotta/hetzner-k3s/releases/download/v2.0.0.rc2/hetzner-k3s-linux-amd64"
