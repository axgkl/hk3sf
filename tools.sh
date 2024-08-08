#!/usr/bin/env bash
# Always loaded

here="$(cd "$(dirname "$me")" && pwd)"
declare -A icons=(
    ["networks"]='🖧 '
    ["ssh_keys"]='🔑'
    ["servers"]='🖥️'
    ["load_balancers"]=' '
    ["images"]='🐧'
    ["volumes"]='💾 '
)

created=false && img="" && type="" && ip="" && ip_priv=""
force=false
retval_=""
no_die=false
IP_PROXY_=""
IP_PROXY_PRIV_=""
SSH_KEY_FINGERPRINT_=""
START_TIME_=$(date +%s)

SSH_="$(which ssh)"
KBCTL="$(which kubectl)"

function dt { local x="${1:-$START_TIME_}" && echo $(($(date +%s) - x)); }
function run {
    local res st
    local shcmd="${*//$HCLOUD_TOKEN/<token>}"
    test -z "$HCLOUD_TOKEN_WRITE" || shcmd="${shcmd//$HCLOUD_TOKEN_WRITE/<hcloud token write>}"
    test -z "$DNS_API_TOKEN" || shcmd="${shcmd//$DNS_API_TOKEN/<dns token>}"
    echo -e "🟣 cmd $(dt) $shcmd" >>"$FN_LOG"
    res="$("$@" 2>>"$FN_LOG")" && st=0 || st=1
    echo -e "$res" >>"$FN_LOG"
    test "$st" != 0 && {
        die "Command failed: $shcmd" "Check $FN_LOG for details"
        return 1
    }
    test -z "$res" && return 0
    echo -e "$res"
}

function die { $no_die && return 1 || out "🟥 $S$1\n$L${2:-}" && exit 1; }
function out { echo -e "$*$O" | tee -a "$FN_LOG" >/dev/stderr; }
function shw { out "$L󰊕 $*" && "$@"; }
function shw_code { type bat >/dev/null && echo "$2" | bat -pp --language "$1" 1>&2 || out "$2"; }
function newer { [ -f "$1" ] && (($(date +%s) - $(stat -c %Y "$1") < $2)); }
function ok {
    local m="$1" && shift
    test -z "${1:-}" || m="$m\n$L💡$*"
    out "$O✔️ $m"
}

function prepare_local_dirs { mkdir -p "$CACHE_DIR" && mkdir -p "$(dirname "$FN_LOG")" && touch "$FN_LOG"; }
function by_name {
    local r && r="$($1 | jq -r '.'"$1"'[] | select(.name == "'"$2"'")')"
    test -z "$r" && die "$2 not in $1" "Check $FN_LOG for details"
    echo -e "$r"
}
function by_name_starts { $1 | jq -r '.'"$1"'[] | select(.name | startswith( "'"$2"'"))'; }

function ico { echo -n "${icons[$1]}"; }
function curl_ {
    local v="$1" t="$2" url="$3" && shift 3
    run curl -s -f -X "$v" \
        -H "Authorization: Bearer $t" \
        -H "Content-Type: application/json" "$url" "$@"
}
function hapi {
    local v="$1" pth="$2" && shift 2
    local ico && ico="$(ico "$(cut -d '/' -f 1 <<<"$pth")")"
    local cached && cached="$CACHE_DIR/$(echo "$pth" | tr '/' '_').json"
    test "$v" == "GET" && newer "$cached" "$CACHE_SECS" && cat "$cached" && return
    test "$v" == "DELETE" && out "❌$L󰛌 $ico $v $pth" && cached="$(dirname "$cached").json"
    test "$v" == "POST" && out "$L󰙴 $ico $v $pth"
    local t="$HCLOUD_TOKEN"
    test "$v" != "GET" && t="$HCLOUD_TOKEN_WRITE"
    test -z "$t" && die "No hcloud token for $v $pth"
    local ret && ret="$(curl_ "$v" "$t" "https://api.hetzner.cloud/v1/$pth" "$@")"
    grep -v null <<<"$ret" | grep -q 'error' && die "Hetzner API error ${v}ing $pth" "$ret"
    test "$v" == "GET" && {
        test -z "$ret" && die "Hetzner API error ${v}ing $pth" "$ret"
        echo -e "$ret" >"$cached"
    }
    test "$v" == "GET" || rm -f "$cached"
    echo -e "$ret"
}
function ssh {
    local stream=false && test "$1" == 'stream' && shift && stream=true
    local sa='' && test "$1" == 'sshargs' && sa="$2" && shift 2
    local host="$1" && shift
    local o1=StrictHostKeyChecking=accept-new
    local a="-p $SSH_PORT -o SendEnv=HCLOUD_TOKEN $sa -o $o1 -i $FN_SSH_KEY $host "
    # shellcheck disable=SC2086
    $stream && "$SSH_" $a "$@"
    # shellcheck disable=SC2086
    $stream || run "$SSH_" $a "$@" # oneshot
}

function show_funcs {
    out "$S\n󰊕 Module $1:$O"
    grep -E '^function [a-z_]+ {' <"$1.sh" | sed -e 's/function //' | cut -d '{' -f 1 | sort
}
function exit_help {
    out "${S}Installs NATed k3s on Hetzner Cloud, using vitobotta/hetzner-k3s$O"
    out "\n⚙️ Config:"
    show_config
    show_funcs main | sort
    show_funcs setup | sort
    show_funcs test | sort
    for k in "pkg"/*.sh; do show_funcs "${k//.sh/}" | sort; done
    out "\n$L💡 Provide module name when calling non main functions from CLI\nExample: $(basename "$0") setup get_kubeconfig$O"
    exit
}
function repl { python3 -c "import sys; print(sys.stdin.read().replace('$1', '$2'))"; }

function get_ips {
    local s && s="$(by_name servers "$NAME-$1")"
    ip="$(jq -r '.public_net.ipv4.ip' <<<"$s")"
    ip_priv="$(jq -r '.private_net[0].ip' <<<"$s")"
}

function chk_have { type "$1" 2>/dev/null | grep -q function; }
#chk || die "Not supported: $func" "$0 -h for all funcs"
function import() {
    chk_have "$1" && return
    local cnt mod funcn="$1"
    mod="$(find . pkg -maxdepth 1 -type f -exec grep -l 'function '"$funcn"' ' {} \; | grep -v main.sh | sort -u || true)"
    cnt="$(echo -e "$mod" | wc -l)"
    test -z "$mod" && die "Not supported: $funcn" "$0 -h for all funcs"
    # we can allow later to supply dir for custom mods and when given add as first to the find above
    test "$cnt" -gt 1 && out "❗ Ambiguous: $funcn" && mod="$(mod | head -n 1)"
    ok "${L}Loading module $mod$O"
    . "$mod"
    chk_have "$funcn" || die "Could not load $mod"
}

function load_pkgs() {
    for k in "$here/pkg"/*.sh; do
        k="${k##*/}" && ok "Loading $k"
        # shellcheck source=./pkg/base.sh
        . "$here/pkg/$k"
    done
}
e="\x1b" && S="$e[1m" && O="$e[0m" && L="$O$e[2m"
false && . ./conf.sh || true
