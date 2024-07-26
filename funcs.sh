#!/usr/bin/env bash
set -euo pipefail
# config ▶️
DFLT_IMG="${IMG:-ubuntu-24.04}" # https://github.com/vitobotta/hetzner-k3s/issues/387#issuecomment-2248702070 ff
DFLT_TYPE="${SERVER:-cx11}"

AUTOSCALED_COUNT="${AUTOSCALED_COUNT:-3}"
AUTOSCALED_IMG="${AUTOSCALED_IMG:-$DFLT_IMG}"
AUTOSCALED_TYPE="${AUTOSCALED_TYPE:-$DFLT_TYPE}"
PROXY_IMG="${PROXY_IMG:-$DFLT_IMG}"
PROXY_TYPE="${PROXY_TYPE:-$DFLT_TYPE}"
PROXY_LB="${PROXY_LB:-80;443}"
CIDR_CLUSTER="${CIDR_CLUSTER:-10.50.0.0/16}"
CIDR_SERVICE="${CIDR_SERVICE:-10.60.0.0/16}"
CNI="${CNI:-cilium}"
DNS_CLUSTER="${DNS_CLUSTER:-10.60.0.10}"
CACHE_DIR="${CACHE_DIR:-$(pwd)/tmp}"
CACHE_SECS="${CACHE_SECS:-60}"
FN_LOG="${FN_LOG:-$(pwd)/tmp/install.log}"
FN_CADDY="${FN_CADDY:-$(pwd)/bin/caddy-amd64}"
FN_SSH_KEY="${FN_SSH_KEY:-$HOME/.ssh/id_rsa}"
HCLOUD_TOKEN="${HCLOUD_TOKEN:-$(pass show HCloud/token)}"
HOST_NETWORK="${HOST_NETWORK:-0}" # 10.$HOST_NETWORK.0.0/16 net, named "ten-$HOST_NETWORK"
HOST_NETWORK_NAME="${HOST_NETWORK_NAME:-ten-$HOST_NETWORK}"
LOCATION="${LOCATION:-hel1}"
MASTERS_ARE_WORKERS="${MASTERS_ARE_WORKERS:-true}"
MASTERS_COUNT="${MASTERS_COUNT:-3}"
MASTERS_IMG="${MASTERS_IMG:-$DFLT_IMG}"
MASTERS_TYPE="${MASTERS_TYPE:-$DFLT_TYPE}"
NAME="${NAME:-k3s}"
REGISTRY_MIRROR="${REGISTRY_MIRROR:-true}"
SSH_PORT="${SSH_PORT:-22}"
URL_HETZNER_K3S="https://github.com/vitobotta/hetzner-k3s/releases/download/v2.0.0.rc2/hetzner-k3s-linux-amd64"
VER_K3S="${VER_K3S:-v1.30.2+k3s2}" # registry mirror requires k3s > 1.30.2
WORKERS_COUNT="${WORKERS_COUNT:-0}"
WORKERS_IMG="${WORKERS_IMG:-$DFLT_IMG}"
WORKERS_TYPE="${WORKERS_TYPE:-$DFLT_TYPE}"
# ◀️ config

IP_PROXY_=""
IP_PROXY_PRIV_=""
HOST_NETWORK_ID_=""
SSH_KEY_NAME_=""
SSH_KEY_FINGERPRINT_=""
SSH_="$(which ssh)"
START_TIME_=$(date +%s)
created=false && img="" && type="" && ip="" && ip_priv=""
force=false
no_die=false
me="${BASH_SOURCE[0]}"
function dt { local x="${1:-$START_TIME_}" && echo $(($(date +%s) - x)); }
function run {
	local res st
	echo -e "🟣 cmd $(dt) $*" | sed -e "s/$HCLOUD_TOKEN/<token>/g" >>"$FN_LOG"
	res="$("$@" 2>>"$FN_LOG")"
	st=$?
	echo -e "$res" >>"$FN_LOG"
	test "$st" != 0 && {
		die "Command failed: $*" "Check $FN_LOG for details"
		return 1
	}
	echo -e "$res"
}

function die { out "🟥 $S$1\n$L${2:-}" && $no_die || exit 1; }
function ok { out "$O✔️ $*"; }
function out { echo -e "$*$O" >/dev/stderr; }
function shw { out "$L󰊕 $*" && "$@"; }
function shw_code { type bat >/dev/null && echo "$2" | bat -pp --language "$1" 1>&2 || out "$2"; }
function newer { [ -f "$1" ] && (($(date +%s) - $(stat -c %Y "$1") < $2)); }

function prepare_local_dirs { mkdir -p "$CACHE_DIR" && mkdir -p "$(dirname "$FN_LOG")" && touch "$FN_LOG"; }
function by_name {
	local r && r="$($1 | jq -r '.'"$1"'[] | select(.name == "'"$2"'")')"
	test -z "$r" && die "$2 not in $1" "Check $FN_LOG for details"
	echo -e "$r"
}
function by_name_starts { $1 | jq -r '.'"$1"'[] | select(.name | startswith( "'"$2"'"))'; }

function hapi {
	local m pth && m="$1" && pth="$2" && shift 2
	local ico && ico="$(cut -d '/' -f 1 <<<"$pth")"
	ico="$(ico "$ico")"
	local cached && cached="$CACHE_DIR/$(echo "$pth" | tr '/' '_').json"
	test "$m" == "GET" && newer "$cached" "$CACHE_SECS" && cat "$cached" && return
	test "$m" == "DELETE" && out "❌$L󰛌 $ico $m $pth" && cached="$(dirname "$cached").json"
	test "$m" == "POST" && out "$L󰙴 $ico $m $pth"
	local ret && ret="$(run curl -s -X "$m" \
		-H "Authorization: Bearer $HCLOUD_TOKEN" \
		-H "Content-Type: application/json" \
		"https://api.hetzner.cloud/v1/$pth" "$@")"
	grep -v null <<<"$ret" | grep -q 'error' && die "Hetzner API error ${m}ing $pth" "$ret"
	test "$m" == "GET" && echo -e "$ret" >"$cached"
	test "$m" == "GET" || rm -f "$cached"
	echo -e "$ret"
}
function ssh {
	local stream=false
	test "$1" == 'stream' && shift && stream=true
	local host="$1" && shift
	local o1=StrictHostKeyChecking=accept-new
	$stream && "$SSH_" -p "$SSH_PORT" -o "SendEnv=HCLOUD_TOKEN" -o $o1 -i "$FN_SSH_KEY" "$host" "$@"
	$stream || run "$SSH_" -p "$SSH_PORT" -o $o1 -i "$FN_SSH_KEY" "$host" "$@"
}

function ensure_host_network {
	local id n nr net
	n="$HOST_NETWORK_NAME"
	nr="$HOST_NETWORK"
	grep -q "\"name\": \"$n\"" <<<"$(networks)" || {
		net="10.$nr.0.0"
		hapi POST networks -d "$(t_net "$n" "$net")" >/dev/null
		ok "$(ico networks) Created host network $n [$net]"
	}
	id="$(jq -r '.networks[] | select(.name == "'"$n"'") | .id' <<<"$(networks)")"
	test -n "$id" || die "Network not found" "Check $FN_LOG for details"
	HOST_NETWORK_ID_="$id"
}
function ico {
	local i=""
	test "$1" == "networks" && i='🖧 '
	test "$1" == "ssh_keys" && i='🔑'
	test "$1" == "servers" && i='🖥️'
	test "$1" == "load_balancers" && i=' '
	echo -n "$i"
}
function rm_known_hosts {
	local ip="$1"
	ssh-keygen -R "$ip"
	ssh-keygen -R "[${ip}]:22"
	ssh-keygen -R "[${ip}]:$SSH_PORT"
}
function ensure_server {
	# Ensure server by name
	# Args: name
	# ❗ When a server name is present, we do NOT go into checking if it's parameters, e.g. IMG match
	local name="$1" && shift
	created=false
	grep -q "\"name\": \"$name\"" <<<"$(servers)" || {
		local s
		s="$(hapi POST servers -d '{
        "name":        "'"$name"'",
        "server_type": "'"$type"'",
        "image":       "'"$img"'",
        "location":    "'"$LOCATION"'",
        "ssh_keys":    ["'"$SSH_KEY_NAME_"'"],
        "networks":    ['"$HOST_NETWORK_ID_"'],
        "public_net": {
            "enable_ipv4": true,
            "enable_ipv6": true
        },
        "labels": {"environment":"dev", "k3s": "'"$NAME"'"}
    }')"
		ip="$(jq -r '.server.public_net.ipv4.ip' <<<"$s")"
		ok "$(ico servers) Ordered server $name [$ip] - waiting for ssh 🕐 "
		run rm_known_hosts "$ip" >/dev/null 2>&1
		created=true
		no_die=true
		local port="$SSH_PORT"
		SSH_PORT=22
		for i in {1..2}; do
			for _ in {1..10}; do
				have="$(ssh "root@$ip" ls /etc 2>/dev/null || true)"
				grep -q "passwd" <<<"$have" && break
				sleep 1 && echo -n "."
			done
		done
		test "$port" != 22 && {
			echo "
          echo 'Port $port' >> /etc/ssh/sshd_config
          systemctl daemon-reload
          systemctl reload sshd || systemctl restart ssh
        " | ssh "root@$ip"
			SSH_PORT="$port"
		}
		no_die=false
	}
	ip_priv="$(jq -r '.servers[] | select(.name == "'"$name"'") | .private_net[0].ip' <<<"$(servers)")"
	ip=$(jq -r '.servers[] | select(.name == "'"$name"'") | .public_net.ipv4.ip' <<<"$(servers)")
	ok "Server $name [$ip / $ip_priv]"
}
function ensure_ip_forwarder {
	# Configures and starts IP forwarding on a server
	# Used for outgoing nat after proxy creation but maybe useful for other servers as well
	# Args: ip of server, normally $IP_PROXY_
	local ip="$1" u="ip_forwarder.service"
	local have
	have="$(ssh "root@$ip" ls /etc/systemd/system)"
	grep -q "$u" <<<"$have" && { ok "IP Forwarder already installed on $ip" && return; }
	echo -e "$T_UNIT_FWD" | ssh "root@$ip" tee /etc/systemd/system/$u
	echo "systemctl enable $u && systemctl start $u" | ssh "root@$ip"
	ok "IP Forwarder installed and started on $ip"
}

function postinstall {
	# Installs tools
	# Args: ip of server, normally $IP_PROXY_
	local ip="$1"
	have="$(ssh "root@$ip" ls /etc)"
	$force || { grep -q "postinstalled" <<<"$have" && { ok "server is postinstalled" && return; }; }
	run ssh "root@$ip" wget -q -N "$URL_HETZNER_K3S" -O hetzner-k3s >/dev/null
	ssh "root@$ip" <<'EOF'
    grep -q "HCLOUD_TOKEN" /etc/sshd/sshd_config || {
        echo 'AcceptEnv HCLOUD_TOKEN' >> /etc/ssh/sshd_config
        echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
        systemctl daemon-reload
        systemctl reload sshd || systemctl restart ssh
    }
    chmod +x hetzner-k3s
    test -e "/root/.ssh/id_ed25519" || ssh-keygen -t ecdsa -N '' -f "$HOME/.ssh/id_ed25519"
    which binenv || {
        wget -q "https://github.com/devops-works/binenv/releases/download/v0.19.11/binenv_linux_amd64" -O binenv
        chmod +x binenv && ./binenv update && ./binenv install binenv && rm binenv
        sed -i '1iexport PATH="$HOME/.binenv:$PATH"' ~/.bashrc
    }
    export PATH="$HOME/.binenv:$PATH"
    for t in helm kubectl; do which $t || binenv install "$t"; done
    touch /etc/postinstalled
EOF

	#     apt -y -qq update # post install...
	#     for p in fail2ban unattended-upgrades update-notifier-common; do apt -y -qq install "$p" systemctl enable "$p" systemctl start "$p" done
}
function ensure_default_route_via_proxy {
	set_proxy_ips
	shw ensure_host_network
	local old
	function act {
		hapi POST "networks/$HOST_NETWORK_ID_/actions/${1}_route" -d '{ "destination": "0.0.0.0/0", "gateway": "'"$2"'" }'
	}
	old="$(networks | jq -r '.networks[] | select(.id == '"$HOST_NETWORK_ID_"') | .routes[] | select(.destination == "0.0.0.0/0") | .gateway')"
	test -z "$old" || {
		test "$old" == "$IP_PROXY_PRIV_" && { ok "Default route already set via proxy" && return 0; }
		act delete "$old"
	}
	act add "$IP_PROXY_PRIV_" >/dev/null
}
function ensure_proxy_server {
	shw ensure_ssh_key
	shw ensure_host_network
	img="$PROXY_IMG" && type="$PROXY_TYPE"
	shw ensure_server "$NAME-proxy"
	shw ensure_default_route_via_proxy
	set_proxy_ips
	$created || return 0
	shw ensure_ip_forwarder "$IP_PROXY_"
	shw postinstall "$IP_PROXY_"
}
function fn_k3s_config { echo "$CACHE_DIR/hetzner-k3s-config.yaml"; }
function synthetize_config {
	local key && key="$(ssh "root@$IP_PROXY_" cat "/root/.ssh/id_ed25519.pub")"
	local lkey && lkey="$(cat "$FN_SSH_KEY".pub)"
	local cfg && cfg="$(echo -e "$T_HK3S_CFG_POST" | repl "SSH_KEY_BAST" "$key" | repl "SSH_KEY_LOCAL" "$lkey")"
	cfg="$T_HK3S_CFG\n$cfg"
	echo -e "$cfg" >"$(fn_k3s_config)"
	ok "Config in $(repl "$(pwd)" '.' <<<"$(fn_k3s_config)")"
}
function have_k3s_master { test -n "$(by_name_starts servers "$NAME-master")"; }

function ensure_k3s_via_proxy {
	$force || { shw have_k3s_master && ok "Skipped - found $NAME-master node. (Run $0 -f to force running 'hetzner-k3s create')" && return; }
	set_proxy_ips
	shw synthetize_config
	ssh "root@$IP_PROXY_" tee "config.yaml" <"$(fn_k3s_config)" >/dev/null
	export HCLOUD_TOKEN
	echo
	out "$S🫰 Kicking off hetzner-k3s from proxy host$L"
	out "${L}ssh -p $SSH_PORT -i '$FN_SSH_KEY' root@$IP_PROXY_$O"
	proxy_is_lb && (transfer_caddy_binary 'in background') & # speeding things up for next step
	local t0 && t0=$(date +%s)
	ssh stream "root@$IP_PROXY_" ./hetzner-k3s create --config config.yaml
	shw ensure_proxy_is_loadbalancer
	ok "🎇 Got the cluster [$(dt "$t0") sec]. Cost: $(cost)"
	report
}

function transfer_caddy_binary {
	no_die=true
	ssh "root@$IP_PROXY_" ls /opt/caddy/caddy >/dev/stderr && return
	no_die=false
	out "🕐 Copying caddy to proxy ${1:-}"
	test -f "$FN_CADDY" || die "Caddy binary not found" "Create xcaddy with lb4proxy binary and set \$FN_CADDY to it"
	ssh "root@$IP_PROXY_" 'cat > caddy' <"$FN_CADDY"
	ok "have caddy binary on proxy"
}

function proxy_is_lb { test -n "${PROXY_LB:-}"; }
function ensure_proxy_is_loadbalancer {
	proxy_is_lb || { ok "Skipped - No proxy loadbalancer ports configured, assuming hetzner lb is used (via ingress annotations for installed hetzner ccm) " && return; }
	set_proxy_ips
	shw destroy_by_type load_balancers
	transfer_caddy_binary
	local np s=''
	IFS=';' read -ra P <<<"$PROXY_LB"
	for p in "${P[@]}"; do
		np=$((p + 30000))
		s=''$s',\n"port'$p'": { "listen": [":'$p'", "[::]:'$p'"], "routes": [{ "handle": [{ "handler": "proxy", "proxy_protocol": "v2", "upstreams": [{ "dial": ["10.'$HOST_NETWORK'.0.5:'$np'"] }] }] }]}'
	done
	local c && c='{"logging":{"sink":{"writer":{"output":"stdout"}},"logs":{"default":{"level":"DEBUG"}}},"apps":{"layer4":{"servers":{'${s:1}'}}}}'
	c="$(echo -e "$c" | jq .)"
	setup_caddy "$IP_PROXY_" "$c"
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
	(echo "Name € IP DC" && jq -r '. | "\(.name) \(.price) \(.ip) \(.dc)"' <<<"$(lb_report)") | column -t
}

function cluster_servers { by_name_starts servers "$NAME-"; }

function server_report {
	local p && p='.server_type.prices[] | select(.location == "'"$LOCATION"'") | .price_monthly.gross | tonumber | round'
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
	local p && p='.load_balancer_type.prices[] | select(.location == "'"$LOCATION"'") | .price_monthly.gross | tonumber | round'
	local d && d='{
       name:.name, 
       dc:.location.name,
       ip:.public_net.ipv4.ip,
       price:('"$p"'),
   }'
	by_name_starts load_balancers "$NAME-" | jq -r "$d"
}

function set_proxy_ips {
	local s && s="$(by_name servers "$NAME-proxy")"
	IP_PROXY_="$(jq -r '.public_net.ipv4.ip' <<<"$s")"
	IP_PROXY_PRIV_="$(jq -r '.private_net[0].ip' <<<"$s")"
}

function ensure_ssh_key {
	local keys && keys="$(ssh_keys)"
	local fp && fp="$SSH_KEY_FINGERPRINT_"
	function n_ { jq -r '.ssh_keys[] | select(.fingerprint == "'"$fp"'") | .name' <<<"$keys"; }
	local n && n="$(n_)"
	if [ -z "$n" ]; then
		n="$NAME"
		function id_ { jq -r '.ssh_keys[] | select(.name == "'"$n"'") | .id' <<<"$keys"; }
		test -z "$(id_)" || hapi DELETE "ssh_keys/$(id_)"
		local k && k="$(cat "$FN_SSH_KEY.pub")"
		hapi POST ssh_keys -d '{ "name": "'"$n"'", "public_key": "'"$k"'" }'
		ok "Created ssh key [$n] on hetzner"
	fi
	ok "SSH key known to Hetzner ($n)"
	SSH_KEY_NAME_="$n"
}

function repl { python3 -c "import sys; print(sys.stdin.read().replace('$1', '$2'))"; }

function images { hapi GET images; }
function load_balancers { hapi GET load_balancers; }
function networks { hapi GET networks; }
function servers { hapi GET servers; }
function ssh_keys { hapi GET ssh_keys; }
function volumes { hapi GET volumes; }

function ensure_local_ssh_key {
	local fn && fn="${FN_SSH_KEY}"
	test -e "$fn" || run ssh-keygen -t ecdsa -N '' -f "$fn"
	run chmod 600 "$fn"
	ok "SSH key present [$fn]"
}
function check_requirements {
	type jq >/dev/null || die "jq not installed" "Install jq" && ok "jq installed"
	type curl >/dev/null || die "curl not installed" "Install jq" && ok "curl installed"
	test -z "$HCLOUD_TOKEN" && die "Missing environment variable HCLOUD_TOKEN." "Export or add to pass. Should be created in project space of the intended cluster." || ok "HCLOUD_TOKEN is set"
	networks >/dev/null

	test -e "$FN_SSH_KEY" && test -e "${FN_SSH_KEY}.pub" || die "SSH key not present" "Create SSH key pair in $FN_SSH_KEY or export fn_ssh_key=<location of your private key>" && ok "Have keys"
	SSH_KEY_FINGERPRINT_="$(ssh-keygen -l -E md5 -f "$FN_SSH_KEY.pub" | cut -d ':' -f 2- | cut -d ' ' -f 1)"
	test -z "$SSH_KEY_FINGERPRINT_" && die "SSH key fingerprint failed" "Check that $FN_SSH_KEY.pub is a valid SSH key" || ok "Have fingerprint"
}
function rmcache { rm -f "$CACHE_DIR/*.json"; }
function destroy_by_name {
	local n="$1"
	local have && have="$($2)"
	id="$(jq -r '.'"$2"'[] | select(.name == "'"$n"'") | .id' <<<"$have" 2>/dev/null)"
	test -z "$id" && { ok "No $n in $2" && return 0; }
	hapi DELETE "$2/$id" >/dev/null
}
function destroy_by_type {
	$1 | jq -r '.'"$1"'[] | select(.name | startswith( "'"$NAME"'-"))|.id' |
		while read -r id; do hapi DELETE "$1/$id" >/dev/null; done
}

function delete {
	no_die=true
	rmcache
	local n id have
	shw destroy_by_type servers
	#del_by_name "$NAME" servers
	shw destroy_by_name "$HOST_NETWORK_NAME" networks
	shw destroy_by_name "$NAME" ssh_keys
	shw destroy_by_type load_balancers
	echo "Volumes left:"
	volumes | jq .volumes
}
function enter {
	local host && host="$1"
	type tmux >/dev/null || die "tmux not installed" "Install tmux"
	servers | jq -r '.servers[] | select(.name | startswith( "'"$NAME"'"))|.id' |
		while read -r id; do hapi DELETE "servers/$id"; done
	ssh
}
function show_config {
	local e="config"
	local c && c="$(head -n 100 "$me" | grep -A 100 "# config" | grep -B 100 '◀️ config')"
	c="$(HCLOUD_TOKEN="xxx" && while IFS= read -r line; do eval "echo \"$line\""; done <<<"$c")"
	shw_code bash "$c"
}
function exit_help {
	out "${S}Installs NATed k3s on Hetzner Cloud, using vitobotta/hetzner-k3s$O"
	echo
	show_config
	exit
}

# --------------------------------------------------------------
# CLI Arguments
# --------------------------------------------------------------
function main {
	local func && func="help"
	while [[ -n "${1:-}" ]]; do
		case "$1" in
		-h | --help | help | \?) exit_help ;;
		-f | --force) force=true && shift ;;
		-x | --trace) set -x && shift ;;
		-*) die "Unknown option: $1" "-h for help" ;;
		e | enter) func="enter" && shift && break ;;
		i | create) func="create" && shift && break ;;
		rm | delete) func="delete" && shift && break ;;
		*) func="$1" && shift && break ;;
		esac
	done
	test "$func" == "help" && exit_help
	prepare_local_dirs || die "Can't prepare files" "Check your \$CACHE_DIR and \$FN_LOG config"
	echo "Starttime: $(date)" >"$FN_LOG"
	test "$func" == "create" && { show_config && return; }
	"$func" "$@"
	exit $?
}

# --------------------------------------------------------------
# Templates
# --------------------------------------------------------------
function t_net {
	echo '{ 
        "name":       "'"$1"'",
        "ip_range":   "'"${2}"'/16",
        "expose_routes_to_vswitch":false,
        "subnets": [{ "ip_range":   "'"${2}"'/24", "network_zone": "eu-central", "type": "cloud" }],
        "labels": {"environment":"dev", "k3s": "'"$NAME"'"}
    }'
}
function setup_caddy {
	local ip="$1"
	local cfg="$2"
	#cat <<EOF
	ssh "root@$ip" <<EOF
useradd caddy || true
mkdir -p /opt/caddy
mv /root/caddy /opt/caddy/caddy
chmod +x /opt/caddy/caddy
echo -e '$cfg' > /opt/caddy/config.json
chown -R caddy:caddy /opt/caddy
echo -e '
[Unit]
Description=Caddy Web Server
Documentation=https://caddyserver.com/docs/
After=network.target

[Service]
User=caddy
ExecStart=/opt/caddy/caddy run --config /opt/caddy/config.json
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
' > /etc/systemd/system/caddy.service
for a in enable daemon-reload restart; do systemctl \$a caddy; done
EOF
	ok "Caddy configured and started on ${PROXY_LB:-}"
}

T_UNIT_FWD="
[Unit]
Description=Bastion IP Forwarder

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'
ExecStart=/bin/bash -c 'iptables -t nat -A POSTROUTING -s "10.${HOST_NETWORK}.0.0/16" -o eth0 -j MASQUERADE'

[Install]
WantedBy=multi-user.target
"

T_HK3S_CFG='
---
cluster_name: "'"$NAME"'"
kubeconfig_path: "./kubeconfig"
k3s_version: "'"$VER_K3S"'"
networking:
  ssh:
    port: '"$SSH_PORT"'
    use_agent: false # set to true if your key has a passphrase
    public_key_path: "~/.ssh/id_ed25519.pub"
    private_key_path: "~/.ssh/id_ed25519"
  allowed_networks:
    ssh:
      - 0.0.0.0/0
    api:
      - 0.0.0.0/0
  public_network:
    ipv4: false
    ipv6: true
  private_network:
    enabled : true
    subnet: 10.'$HOST_NETWORK'.0.0/16
    existing_network_name: "'"$HOST_NETWORK_NAME"'"
  cni:
    enabled: true
    encryption: false
    mode: '"$CNI"'
  cluster_cidr: "'"$CIDR_CLUSTER"'"
  service_cidr: "'"$CIDR_SERVICE"'"
  cluster_dns: "'"$DNS_CLUSTER"'"
datastore:
  mode: etcd # etcd (default) or external
  external_datastore_endpoint: postgres://....
schedule_workloads_on_masters: '"$MASTERS_ARE_WORKERS"'

masters_pool:
  instance_type: "'"${MASTERS_TYPE}"'"
  instance_count: '"${MASTERS_COUNT}"'
  location: "'"${LOCATION}"'"
  image: "'"${MASTERS_IMG}"'"

worker_node_pools:
  - name: small-static
    instance_type: "'"${WORKERS_TYPE}"'"
    instance_count: '"${WORKERS_COUNT}"'
    location: "'"${LOCATION}"'"
    image: "'"${WORKERS_IMG}"'"
    # labels:
    #   - key: purpose
    #     value: blah
    # taints:
    #   - key: something
    #     value: value1:NoSchedule

  - name: medium-autoscaled
    instance_type: "'"${AUTOSCALED_TYPE}"'"
    instance_count: '"${AUTOSCALED_COUNT}"'
    location: "'"${LOCATION}"'"
    image: "'"${AUTOSCALED_IMG}"'"
    autoscaling:
      enabled: true
      min_instances: 0
      max_instances: '"${AUTOSCALED_COUNT}"'

embedded_registry_mirror:
  enabled: '"${REGISTRY_MIRROR}"'

additional_packages:
 - ifupdown
'

T_HK3S_CFG_POST='
post_create_commands:
- echo "Started" > /.status
- timedatectl set-timezone Europe/Berlin
- echo '\''SSH_KEY_BAST'\'' >> /root/.ssh/authorized_keys
- echo '\''SSH_KEY_LOCAL'\'' >> /root/.ssh/authorized_keys
- echo "root:$(head -c 50 /dev/urandom | base64)" | chpasswd
- mkdir -p /etc/network/interfaces.d
- iface="$(ip -o -4 addr list | grep " 10.'"$HOST_NETWORK"'." | cut -d " " -f 2)"
- |
  cat > /etc/network/interfaces.d/$iface <<EOF
  auto $iface
  iface $iface inet dhcp
    post-up ip route add default via 10.'"$HOST_NETWORK"'.0.1
    post-up ip route add 169.254.169.254 via 172.31.1.1
  EOF
- rm -f /etc/resolv.conf
- |
  cat > /etc/resolv.conf <<EOF
  nameserver 185.12.64.1
  nameserver 185.12.64.2
  edns edns0 trust-ad
  search .
  EOF
- ip route add 169.254.0.0/16 via 172.31.1.1
- ip route add default via 10.'"$HOST_NETWORK"'.0.1
- echo "Done" > /.status
'

e="\x1b" && S="$e[1m" && O="$e[0m" && L="$O$e[2m"
main "$@"
