#!/usr/bin/env bash
set -euo pipefail
me="${BASH_SOURCE[0]}"
builtin cd "$(dirname "$me")"
ME="$(basename $0)"
source "./conf.sh"
source "./tools.sh"

trap 'test -z "$tailpid" || kill $tailpid' EXIT SIGINT

function clear_ip_from_known_hosts { local fn="$HOME/.ssh/known_hosts" && mkdir -p "$HOME/.ssh" && touch "$fn" && sed -i '/'"$1"'/d' "$fn"; }

# will establish a tunnel to the proxy server and keep it up:
function start_ssh_tunnel {
    nohup "$0" ssh sshargs '-f -N' "$NAME-proxy" >/dev/null 2>&1 || true
    ok "ssh tunnel to $NAME-proxy established permanently" "$0 stop_ssh_tunnel to kill it"
}
function stop_ssh_tunnel { kill "$(pgrep -f "ssh.*$NAME-proxy")" 2>/dev/null || true; }

function kubectl { kube kubectl "$@"; }
function helm { kube helm "$@"; }
function kube {
    local b f="$1" && shift
    b="$(type -P "$f")" || die "You have no local $f in your \$PATH"
    local stream=false && test "$1" = 'stream' && shift && stream=true
    export KUBECONFIG="$FN_KUBECONFIG"
    ss -tuln | grep -q "$SSH_TUNNEL_PORT" || shw start_ssh_tunnel
    $stream && "$b" "$@"
    $stream || run "$b" "$@"
}
function cost {
    local s && s=$(server_report | jq -s '[.[] | .price] | add')
    local l && l=$(lb_report | jq -s '[.[] | .price] | add')
    echo -e "Server $S$s$O€, LB $S$l$O€"
}

function report {
    echo -e "${S}Server$O"
    (echo -e "Name € IP HW DC" && jq -r '. | "\(.name) \(.price) \(.ip) \(.cores)C\u00A0\(.mem)GB\u00A0\(.disk)TB \(.dc)"' <<<"$(server_report)") | column -t
    echo -e "${S}Loadbalancer$O"
    (echo "Name € IP DC" && jq -r '. | "\(.name) \(.price) \(.ip) \(.dc)"' <<<"$(lb_report)")
    (echo "Name € IP DC" && jq -r '. | "\(.name) \(.price) \(.ip) \(.dc)"' <<<"$(lb_report)") | column -t || true
    (echo "Name € IP DC" && jq -r '. | "\(.name) \(.price) \(.ip) \(.dc)"' <<<"$(lb_report)") | column -t
}

function cluster_servers { by_name_starts servers "$NAME-"; }

function server_report {
    local p && p='.server_type.prices[] | select(.location == "'"$HK_LOCATION"'") | .price_monthly.gross | tonumber | round'
    local d && d='{
       name:.name, 
       dc:.datacenter.name, 
       price:('"$p"'),
       ip:.public_net.ipv4.ip,
       cores:.server_type.cores, 
       mem:(.server_type.memory|round), 
       disk:.server_type.disk
   }'
    cluster_servers | jq -r "$d"
}

function lb_report {
    local p && p='.load_balancer_type.prices[] | select(.location == "'"$HK_LOCATION"'") | .price_monthly.gross | tonumber | round'
    local d && d='{
       name:.name, 
       dc:.location.name,
       ip:.public_net.ipv4.ip,
       price:('"$p"'),
   }'
    by_name_starts load_balancers "$NAME-" | jq -r "$d"
}

function get_proxy_ips {
    get_ips proxy && IP_PROXY_="$ip" && IP_PROXY_PRIV_="$ip_priv"
    test -z "$ip" && die "Require proxy server" || true
}

function api_get {
    local obj="$1"
    test -z "${2:-}" && hapi GET "$obj" && return
    hapi GET "$obj" | jq -r '.'"$obj"'[]' | jq -r "$2"
}
function images { api_get images "$@"; }
function load_balancers { api_get load_balancers "$@"; }
function networks { api_get networks "$@"; }
function servers { api_get servers "$@"; }
function ssh_keys { api_get ssh_keys "$@" | tr -d '\n'; }
function volumes { api_get volumes "$@"; }
function have { type "$1" >/dev/null 2>&1; }

function ensure_requirements {
    have jq || die "jq not installed" "Install jq" && ok "jq installed"
    have curl || die "curl not installed" "Install jq" && ok "curl installed"
    test -z "$HCLOUD_TOKEN" && die "Missing environment variable HCLOUD_TOKEN." "Export or add to pass. Should be created in project space of the intended cluster." || ok "HCLOUD_TOKEN is set"
    shw ensure_local_ssh_key # call, when $FN_SSH_KEY possibly not present
    test -e "$FN_SSH_KEY" && test -e "${FN_SSH_KEY}.pub" || die "SSH key not present" "Create SSH key pair in $FN_SSH_KEY or export fn_ssh_key=<location of your private key>" && ok "Have keys"
    SSH_KEY_FINGERPRINT_="$(ssh-keygen -l -E md5 -f "$FN_SSH_KEY.pub" | cut -d ':' -f 2- | cut -d ' ' -f 1)"
    test -z "$SSH_KEY_FINGERPRINT_" && die "SSH key fingerprint failed" "Check that $FN_SSH_KEY.pub is a valid SSH key" || ok "Have fingerprint"
    ensure_tools_local &
    ok "Requirements met"
}

function rmcache { rm -f "$CACHE_DIR"/*.json; }
function destroy_by_name {
    local id && id="$(by_name "$2" "$1" 2>/dev/null | jq .id)"
    test -z "$id" && { ok "No $1 in $2" && return 0; }
    hapi DELETE "$2/$id" >/dev/null
}
function destroy_by_type {
    $1 | jq -r '.'"$1"'[] | select(.name | startswith( "'"$NAME"'-"))|.id' |
        while read -r id; do hapi DELETE "$1/$id" >/dev/null; done
}

function destroy {
    rmcache
    no_die=true
    local n id have
    shw destroy_by_type servers
    #del_by_name "$NAME" servers
    shw destroy_by_name "$HK_HOST_NETWORK_NAME" networks
    shw destroy_by_name "$NAME" ssh_keys
    shw destroy_by_type load_balancers
    echo "Volumes left:"
    volumes | jq .volumes
    stop_ssh_tunnel
    no_die=false
}

function show_config {
    out "\n⚙️ Config:"
    local c && c="$(
        for key in $(grep '^:' <conf.sh | grep -iE ''${1:-}'' | cut -d '{' -f 2 | cut -d ':' -f 1); do
            if [[ $key =~ (TOKEN|KEY) && ! $key =~ FN_ ]]; then echo "$key=${!key:0:3}..."; else echo "$key=${!key}"; fi
        done

    )"
    shw_code bash "$c"
}

# --------------------------------------------------------------
# Convenience functions
# --------------------------------------------------------------

function nodes() { kubectl get nodes; }
function pods() { kubectl get pods --all-namespaces; }

function log() {
    local flow=false match=''
    local m="${1:?Require match string}" && shift
    while [[ -n "${1:-}" ]]; do
        case "$1" in
        -f) flow=true && shift ;;
        -m) match="$2" && shift 2 ;;
        esac
    done
    local pods && pods=$(kubectl get pods --all-namespaces | grep -v NAME | grep -E "$m" | awk '{print $2 "\n" $1}')
    while read -r p && read -r n; do
        $flow || run kubectl logs "$p" -n "$n" | grep -E "$match" || true
        #$flow && (kubectl logs "$p" -n "$n" --tail=5 -f | grep -E "$match") &
        $flow && shw kubectl stream logs "$p" -n "$n" --tail=5 -f | grep -E "$match" &
    done <<<"$pods"
    $flow && while true; do sleep 1; done
}

# --------------------------------------------------------------
# CLI Arguments
# --------------------------------------------------------------
main() {
    local func && func="import"
    prepare_local_dirs || die "Can't prepare files" "Check your \$CACHE_DIR and \$FN_LOG config"
    echo "Starttime: $(date)" >"$FN_LOG"
    while [[ -n "${1:-}" ]]; do
        case "$1" in
        -h | --help | help | \?) shift && exit_help "$@" ;;
        -f | --force) force=true && shift ;;
        -x | --trace) set -x && shift ;;
        -d | --debug)
            tail -f "$FN_LOG" | awk '{ printf "\033['"$LOG_DBG_CLR"'m%s\033[0m\n", $0 }' >&2 &
            tailpid=$!
            shift
            ;;
        -*) die "Unknown option: $1" "-h for help" ;;
        e | enter) func="enter" && shift && break ;;
        k | kubectl) func="kubectl" && shift && break ;;
        i | create) func="create" && shift && break ;;
        rm | destroy) func="destroy" && shift && break ;;
        *) func="$1" && shift && break ;;
        esac
    done
    test "$func" = "help" && exit_help "$@"
    test "$func" = "import" && {
        load_pkgs
        #show_config
        rmcache
        . ./setup.sh # the only non pkg not always loaded
        return       # calling script can set up w/o imports now
    }
    import "$func"
    "$func" "$@"
    exit "$?"
}

main "$@"
