#!/usr/bin/env bash
# shellcheck disable=SC2034 # Unused vars
# Always loaded

declare -A icons=(
    ["networks"]='🖧 '
    ["ssh_keys"]='🔑'
    ["servers"]='🖥️'
    ["load_balancers"]=' '
    ["images"]='🐧'
    ["volumes"]='💾 '
)

created=false
force=false
dryrun=false
img=""
ip=""
ip_priv=""
no_die=false
retval_=""
tailpid=""
type=""
hir_="${hir_:-0}"

IP_PROXY_=""
IP_PROXY_PRIV_=""
SSH_="$(which ssh)"
SSH_KEY_FINGERPRINT_=""
START_TIME_=$(date +%s)

function dt { local x="${1:-$START_TIME_}" && echo $(($(date +%s) - x)); }
function run {
    local res st
    local shcmd="${*//$HCLOUD_TOKEN/<token>}"
    test -z "$HCLOUD_TOKEN_WRITE" || shcmd="${shcmd//$HCLOUD_TOKEN_WRITE/<hcloud token write>}"
    test -z "$DNS_API_TOKEN" || shcmd="${shcmd//$DNS_API_TOKEN/<dns token>}"
    echo -e "🟣 cmd $(dt) $shcmd" >>"$FN_LOG"
    res="$(exec_or_dry "$@" 2>>"$FN_LOG")" && st=0 || st=1
    echo -e "$res" >>"$FN_LOG"
    test "$st" != 0 && {
        die "Command failed: $shcmd" "Check $FN_LOG for details"
        return 1
    }
    test -z "$res" && return 0
    echo -e "$res"
}
function exec_or_dry {
    test "${dryrun:-}" = true && out "🟡 $* $L [dryrun set]$O" && return 0
    "$@"
}
function die { $no_die && return 1 || out "🟥 $S$1\n$L${2:-}" && exit 1; }
function out { echo -e "$*$O" | tee -a "$FN_LOG" >/dev/stderr; }
function shw {
    out "$L󰊕 $(hirindent)$*"
    hirset 1
    exec_or_dry "$@"
    hirset -1 $?
}

hirindent() {
    test "${hir_:-}" == '0' && return
    local c="└─"
    for ((i = 1; i < hir_; i++)); do c="└─$c"; done
    echo -n "$c "
}

hirset() {
    hir_=$((hir_ + $1)) && return "${2:-0}"
}
function shw_code { type bat >/dev/null && echo "$2" | bat -pp --language "$1" 1>&2 || out "$2"; }
function newer { [ -f "$1" ] && (($(date +%s) - $(stat -c %Y "$1") < $2)); }
function ok {
    local m="$1" && shift
    test -z "${1:-}" || m="$m\n$L💡$*"
    out "$O✔️ $m"
}

function prepare_local_dirs {
    for d in "$HOME/.ssh" "$HOME/.kube" "$CACHE_DIR" "$(dirname "$FN_LOG")"; do mkdir -p "$d"; done
    touch "$HOME/.ssh/config" && touch "$FN_LOG"
}
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
    test "$v" = "GET" && newer "$cached" "$CACHE_SECS" && cat "$cached" && return
    test "$v" = "DELETE" && out "❌$L󰛌 $ico $v $pth" && cached="$(dirname "$cached").json"
    test "$v" = "POST" && out "$L󰙴 $ico $v $pth"
    local t="$HCLOUD_TOKEN"
    test "$v" != "GET" && t="$HCLOUD_TOKEN_WRITE"
    test -z "$t" && die "No hcloud token for $v $pth"
    local ret && ret="$(curl_ "$v" "$t" "https://api.hetzner.cloud/v1/$pth" "$@")"
    grep -v null <<<"$ret" | grep -q 'error' && die "Hetzner API error ${v}ing $pth" "$ret"
    test "$v" = "GET" && {
        test -z "$ret" && die "Hetzner API error ${v}ing $pth" "$ret"
        echo -e "$ret" >"$cached"
    }
    test "$v" = "GET" || rm -f "$cached"
    echo -e "$ret"
}
function ssh {
    local stream=false && test "$1" = 'stream' && shift && stream=true
    local sa='' && test "$1" = 'sshargs' && sa="$2" && shift 2
    local host="$1" && shift
    local o1=StrictHostKeyChecking=accept-new
    export HCLOUD_TOKEN #="$HCLOUD_TOKEN_WRITE"
    local a="-p $HK_SSH_PORT -o SendEnv=HCLOUD_TOKEN $sa -o $o1 -i $FN_SSH_KEY $host "
    # shellcheck disable=SC2086
    $stream && "$SSH_" $a "$@"
    # shellcheck disable=SC2086
    $stream || run "$SSH_" $a "$@" # oneshot
}

function show_funcs {
    local m="" && test -z "${2:-}" || m="[$2]"
    out "$S\n󰊕 Module $1 $m:$O"
    grep -E '^function [a-z_]+ {' <"$1.sh" | grep -iE "${2:-}" | sed -e 's/function //' | cut -d '{' -f 1 | sort || true
}

function grepfunc {
    vi -c "lua require('telescope.builtin').live_grep({prompt_title = 'Functions. Ctrl-c supported', default_text = '^function.*$1', prompt_prefix='󰊕 🔍 ', attach_mappings = function(_, map) map('i', '<C-c>', function() vim.cmd('qa!') end); return true end  })" ./conf.sh
    exit
}

function exit_help {
    test -z "${1:-}" || grepfunc "$1"
    out "${S}Installs NATed k3s on Hetzner Cloud, using vitobotta/hetzner-k3s$O"
    show_config "$@"
    show_funcs main "$@" | sort
    show_funcs setup "$@" | sort
    for k in "pkg"/*.sh; do show_funcs "${k//.sh/}" "$@" | sort; done
    #out "\n$L💡 Provide module name when calling non main functions from CLI\nExample: $(basename "$exe") setup get_kubeconfig$O"
    exit
}
function repl { python3 -c "import sys; print(sys.stdin.read().replace('$1', '''$2'''))"; }

function get_ips {
    test -z "$1" && die "get_ips: No name given"
    local s && s="$(by_name servers "$NAME-$1")"
    ip="$(jq -r '.public_net.ipv4.ip' <<<"$s")"
    ip_priv="$(jq -r '.private_net[0].ip' <<<"$s")"
}

function proxy_is_lb { test -n "${PROXY_LB:-}"; }

function chk_have { type "$1" 2>/dev/null | grep -q function; }
#chk || die "Not supported: $func" "$exe -h for all funcs"
function import() {
    chk_have "$1" && return
    local cnt mod funcn="$1"
    mod="$(find "${here:-}/pkg" -maxdepth 1 -type f -exec grep -l '^function '"$funcn"' ' {} \; | grep -v main.sh | sort -u || true)"
    echo "${mod:-}"
    cnt="$(echo -e "$mod" | wc -l)"
    test -z "$mod" && die "Not supported: $funcn" "$exe -h for all funcs"
    # we can allow later to supply dir for custom mods and when given add as first to the find above
    test "$cnt" -gt 1 && out "❗ Ambiguous: $funcn" && mod="$(mod | head -n 1)"
    ok "${L}Loading module $mod$O"
    . "$mod"
    chk_have "$funcn" || die "Could not load $mod"
}

function load_pkgs() {
    for k in "$here/pkg"/*.sh; do
        k="${k##*/}" && ok "${L}Loading module $k$O"
        # shellcheck source=./pkg/base.sh
        . "$here/pkg/$k"
    done
}
e="\x1b" && S="$e[1m" && O="$e[0m" && L="$O$e[2m"

false && . ./conf.sh && . ./main.sh || true
