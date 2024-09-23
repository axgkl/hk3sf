DFLT_IMG="${IMG:-ubuntu-24.04}" # https://github.com/vitobotta/hetzner-k3s/issues/387#issuecomment-2248702070 ff
DFLT_TYPE="${SERVER:-cx22}"

: "${NAME:=k3s}"

: "${HK_AUTOSCALED_COUNT:=3}"
: "${HK_AUTOSCALED_IMG:=$DFLT_IMG}"
: "${HK_AUTOSCALED_TYPE:=$DFLT_TYPE}"
: "${PROXY_IMG:=$DFLT_IMG}"
: "${PROXY_TYPE:=$DFLT_TYPE}"
# Ports the external LB will listen on. After changes: ensure_proxy_is_loadbalancer and ensure_ingress_nginx_with_certmgr
: "${PROXY_LB:=80;443}"
: "${CACHE_DIR:=$(pwd)/tmp.$NAME}"
# how long hcloud api GET results are remembered, w/o triggering now api calls. Non GET ops autoclear the cache.
: "${CACHE_SECS:=60}"
: "${HK_CIDR_CLUSTER:=10.50.0.0/16}"
: "${HK_CIDR_SERVICE:=10.60.0.0/16}"
# flannel or cilium
: "${HK_CNI:=cilium}"
: "${HK_DNS_CLUSTER:=10.60.0.10}"
# for certmanager
: "${EMAIL:=}"
: "${DNS_PROVIDER:=}"
: "${DNS_API_TOKEN:=}"
: "${DNS_TTL:=1800}"
: "${DOMAIN:=example.com}"
: "${FN_KUBECONFIG:=$HOME/.kube/$NAME.yml}"
: "${FN_LINK_KUBECONFIG:=$HOME/.kubeconfig}"
: "${FN_LOG:=$CACHE_DIR/install.log}"
: "${FN_SSH_KEY:=$HOME/.ssh/id-$NAME}"

# Optional. token needs only content r/w rights on the repo
: "${GITOPS_BRANCH:=main}"
: "${GITOPS_HOST:=gh}"
: "${GITOPS_OWNER:=}"
: "${GITOPS_PATH:=}"
: "${GITOPS_REPO:=}"
: "${GITOPS_TOKEN:=}"

# Read only token - in use for most functions:
: "${HCLOUD_TOKEN:=}"
: "${HCLOUD_TOKEN_WRITE:=}"
: "${HK_HOST_NETWORK:=0}" # 10.$HK_HOST_NETWORK.0.0/16 net, named "ten-$HK_HOST_NETWORK"
: "${HK_HOST_NETWORK_NAME:=ten-$HK_HOST_NETWORK}"
: "${HK_LOCATION:=hel1}"
: "${HK_MASTERS_ARE_WORKERS:=true}"
: "${HK_MASTERS_COUNT:=3}"
: "${HK_MASTERS_IMG:=$DFLT_IMG}"
: "${HK_MASTERS_TYPE:=$DFLT_TYPE}"
: "${HK_REGISTRY_MIRROR:=true}"
: "${HK_SSH_PORT:=22}"
: "${LOG_DBG_CLR:=2;37}"
: "${SSH_TUNNEL_PORT:=16443}"
# Optional - otherwise created
: "${SSH_KEY_PRIV:=}"
# Until v2 is released, this contains a few patches:
#: "${URL_HETZNER_K3S:=https://github.com/axgkl/binaries/raw/master/hetzner-k3s}"
# xcaddy with lb4 module added - in use when proxy is lb:
: "${URL_CADDY:=https://github.com/axgkl/binaries/raw/master/caddy-amd64}"
: "${URL_BINENV_PATCHES:=https://github.com/axgkl/binaries/raw/master/distributions.patch.yaml}"
: "${HK_VER:=}"
: "${HK_VER_K3S:=v1.30.2+k3s2}" # registry mirror requires k3s > 1.30.2
: "${HK_WORKERS_COUNT:=0}"
: "${HK_WORKERS_IMG:=$DFLT_IMG}"
: "${HK_WORKERS_TYPE:=$DFLT_TYPE}"
#URL_HETZNER_K3S="https://github.com/vitobotta/hetzner-k3s/releases/download/v2.0.0.rc2/hetzner-k3s-linux-amd64"
