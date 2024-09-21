# functions to setup the cluster from scratch

HOST_NETWORK_ID_=""
SSH_KEY_NAME_=""

function ensure_local_ssh_key {
    local fn d && fn="${FN_SSH_KEY}" && d="$(dirname "$fn")"
    test -n "$fn.pub" && test -n "$fn" && ok "SSH key present [$fn]" && return
    test ! -e "$d" && mkdir -p "$d" && chmod 700 "$d"
    rm -f "$fn.previous"
    if [ -e "$fn" ]; then cp "$fn" "$fn.previous"; fi
    if [ -n "$SSH_KEY_PRIV" ]; then
        echo -e "$SSH_KEY_PRIV" | grep . >"$fn" && chmod 600 "$fn"
        out "Creating $fn.pub"
        ssh-keygen -y -f "$fn" >"$fn.pub"
    else
        run ssh-keygen -q -t ecdsa -N '' -f "$fn"
    fi
    run chmod 600 "$fn"
    if [ -e "$fn.previous" ]; then
        if cmp -s "$fn" "$fn.previous"; then
            out "🔑 SSH key unchanged"
        else
            out "🔑 SSH key changed - previous one in $fn.previous"
        fi
    fi
    ok "SSH key present [$fn]"
}

function ensure_ssh_key {
    local keys && keys="$(ssh_keys)"
    local fp && fp="$SSH_KEY_FINGERPRINT_"
    function n_ { jq -r '.ssh_keys[] | select(.fingerprint == "'"$fp"'") | .name' <<<"$keys"; }
    local n && n="$(n_)"
    if [ -z "$n" ]; then
        n="$NAME"
        out "fingerprint of key '$n' does not match ours - recreating"
        function id_ { jq -r '.ssh_keys[] | select(.name == "'"$n"'") | .id' <<<"$keys"; }
        test -z "$(id_)" || hapi DELETE "ssh_keys/$(id_)"
        local k && k="$(cat "$FN_SSH_KEY.pub")"
        hapi POST ssh_keys -d '{ "name": "'"$n"'", "public_key": "'"$k"'" }' >/dev/null
        ok "Created ssh key '$n' on hetzner"
    fi
    ok "SSH key known to Hetzner ($n)"
    SSH_KEY_NAME_="$n"
}

function transfer_caddy_binary {
    test -z "$IP_PROXY_" && get_proxy_ips
    (ssh "root@$IP_PROXY_" "[ -f /root/caddy ] || [ -f /opt/caddy/caddy ]" 2>/dev/null) && return
    out "🕐 Copying caddy to proxy ${1:-}"
    ssh "root@$IP_PROXY_" "wget '$URL_CADDY' -O caddy"
    ok "have caddy binary on proxy"
}

#💡 Turn the proxy node into a loadbalancer replacement
function ensure_proxy_is_loadbalancer {
    # No need to pay for a loadbalancer when we can use the proxy node
    # Straight forward transferral of setup to on premise k3s + existing LB
    # Downside:
    # 1. No HA - when it breaks you have to create a new one and configure DNS to it
    # 2. No CCM for it - i.e. for new *external* ports you do have to recreate the config AND configure NodePort 30000+that port
    # Note: New webservices within the cluster are typically done on 443/80 and specific hostnames, not touching the LB
    proxy_is_lb || { ok "Skipped - No proxy loadbalancer ports configured, assuming hetzner lb is used (via ingress annotations for installed hetzner ccm) " && return; }
    get_proxy_ips
    shw destroy_by_type load_balancers
    shw transfer_caddy_binary
    local np s=''
    IFS=';' read -ra P <<<"$PROXY_LB"
    for p in "${P[@]}"; do
        np=$((p + 30000))
        s=''$s',\n"port'$p'": { "listen": [":'$p'", "[::]:'$p'"], "routes": [{ "handle": [{ "handler": "proxy", "proxy_protocol": "v2", "upstreams": [{ "dial": ["10.'$HK_HOST_NETWORK'.0.5:'$np'"] }] }] }]}'
    done
    local c && c='{"logging":{"sink":{"writer":{"output":"stdout"}},"logs":{"default":{"level":"DEBUG"}}},"apps":{"layer4":{"servers":{'${s:1}'}}}}'
    c="$(echo -e "$c" | jq .)"
    shw setup_ext_lb_caddy "$IP_PROXY_" "$c"
    test -z "$DNS_PROVIDER" && ok "Loadbalancer is configured" "Make sure you have DNS configured ($ME dns_add)"
    . pkg/dns.sh
    shw dns_add "$IP_PROXY_"
}

function ensure_host_network {
    local id n nr net
    n="$HK_HOST_NETWORK_NAME"
    nr="$HK_HOST_NETWORK"
    test -z "$(by_name networks "$n")" && {
        net="10.$nr.0.0"
        hapi POST networks -d "$(t_net "$n" "$net")" >/dev/null
        ok "$(ico networks) Created host network $n [$net]"
    }
    id="$(by_name networks "$n" | jq .id)"
    test -n "$id" || die "Network not found" "Check $FN_LOG for details"
    HOST_NETWORK_ID_="$id"
}

function ensure_server {
    # Ensure server by name
    # Args: name
    # ❗ When a server name is present, we do NOT go into checking if it's parameters, e.g. IMG match
    local shortname="$1"
    local name="$NAME-$shortname" && shift
    created=false
    grep -q "\"name\": \"$name\"" <<<"$(servers)" || {
        local s
        s="$(hapi POST servers -d '{
        "name":        "'"$name"'",
        "server_type": "'"$type"'",
        "image":       "'"$img"'",
        "location":    "'"$HK_LOCATION"'",
        "ssh_keys":    ["'"$SSH_KEY_NAME_"'"],
        "networks":    ['"$HOST_NETWORK_ID_"'],
        "public_net": {
            "enable_ipv4": true,
            "enable_ipv6": true
        },
        "labels": {"environment":"dev", "k3s": "'"$NAME"'"}
    }')"
        get_ips "$shortname"
        ok "$(ico servers) Ordered server $name [$ip] - waiting for ssh 🕐 "
        shw clear_ip_from_known_hosts "$ip" >/dev/null 2>&1
        created=true
        local fn="$CACHE_DIR/tst"
        rm -f "$fn" && touch "$fn"
        local port="$HK_SSH_PORT"
        SSH_PORT=22 # until configured
        for __ in {1..2}; do
            for _ in {1..10}; do
                (ssh "root@$ip" ls /etc 2>/dev/null >"$fn") || true
                grep -q "passwd" <"$fn" && break || true
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
    }
    ip_priv=''
    while true; do
        get_ips "$shortname"
        test "$ip_priv" = "null" && ip_priv=''
        test -z "$ip_priv" || break
        out "waiting for private IP..."
        sleep 2
    done
    ok "Server $name [$ip / $ip_priv]"
}

#💡 Configures and starts IP forwarding on a server
function ensure_ip_forwarder {
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

function download_hetzner_k3s { run ssh "$1" wget -q -N "$2" -O hetzner-k3s >/dev/null; }
function ensure_base_cfg_proxy { echo -e "$T_SSHD" | ssh "$1" bash -; }
function ensure_tools_proxy { echo -e "$T_INST_TOOLS" | ssh "$1" bash -; }
function ensure_tools_local { eval "$T_INST_TOOLS"; }

#💡 Installs tools on a new server (hk3s, binenv, kubectl, helm)
function postinstall {
    # Args: ip of server, normally $IP_PROXY_
    get_proxy_ips
    local ip="${1:-$IP_PROXY_}"
    have="$(ssh "root@$ip" ls /etc)"
    $force || { grep -q "postinstalled" <<<"$have" && { ok "server is postinstalled" && return; }; }
    #shw download_hetzner_k3s "root@$ip" "$URL_HETZNER_K3S"
    shw ensure_base_cfg_proxy "root@$ip"
    shw ensure_tools_proxy "root@$ip" # can't do in bg, since hk3s checks for kubectl presence. might mock that later to speed things up, will only be needed after k3s is installed
    #     apt -y -qq update # post install...
    #     for p in fail2ban unattended-upgrades update-notifier-common; do apt -y -qq install "$p" systemctl enable "$p" systemctl start "$p" done
}
function ensure_default_route_via_proxy {
    get_proxy_ips
    shw ensure_host_network
    local old
    function act {
        hapi POST "networks/$HOST_NETWORK_ID_/actions/${1}_route" -d '{ "destination": "0.0.0.0/0", "gateway": "'"$2"'" }'
    }
    old="$(networks | jq -r '.networks[] | select(.id == '"$HOST_NETWORK_ID_"') | .routes[] | select(.destination == "0.0.0.0/0") | .gateway')"
    test -z "$old" || {
        test "$old" = "$IP_PROXY_PRIV_" && { ok "Default route already set via proxy" && return 0; }
        act delete "$old"
    }
    act add "$IP_PROXY_PRIV_" >/dev/null
}
function ensure_proxy_server {
    shw ensure_ssh_key
    shw ensure_host_network
    img="$PROXY_IMG" && type="$PROXY_TYPE"
    shw ensure_server "proxy"
    shw ensure_default_route_via_proxy
    get_proxy_ips
    $created || return 0
    shw ensure_ip_forwarder "$IP_PROXY_"
    shw postinstall "$IP_PROXY_"
}
function fn_k3s_config { echo "$CACHE_DIR/hetzner-k3s-config.yaml"; }
function synthetize_hk3s_config {
    local key && key="$(ssh "root@$IP_PROXY_" cat "/root/.ssh/id_ed25519.pub")"
    local lkey && lkey="$(cat "$FN_SSH_KEY".pub)"
    local cfg && cfg="$(echo -e "$T_HK3S_POST_CREATE_CMDS" | repl "SSH_KEY_BAST" "$key" | repl "SSH_KEY_LOCAL" "$lkey")"
    cfg="$T_HK3S_CFG\n$cfg"
    echo -e "$cfg" >"$(fn_k3s_config)"
    ok "Config in $(repl "$(pwd)" '.' <<<"$(fn_k3s_config)")"
}
function have_k3s_master { test -n "$(by_name_starts servers "$NAME-master")"; }

function ensure_k3s_via_proxy {
    $force || { shw have_k3s_master && ok "Skipped - found $NAME-master node. (Run $exe -f install to force running 'hetzner-k3s create')" && return; }
    get_proxy_ips
    shw synthetize_hk3s_config
    ssh "root@$IP_PROXY_" tee "config.yaml" <"$(fn_k3s_config)" >/dev/null
    export HCLOUD_TOKEN
    echo
    out "$S🫰 Kicking off hetzner-k3s from proxy host$L"
    out "${L}ssh -p $HK_SSH_PORT -i '$FN_SSH_KEY' root@$IP_PROXY_$O"
    proxy_is_lb && (transfer_caddy_binary 'in background') & # speeding things up for next step
    local t0 && t0=$(date +%s)
    (
        export HCLOUD_TOKEN="$HCLOUD_TOKEN_WRITE"
        ssh stream "root@$IP_PROXY_" hetzner-k3s create --config config.yaml
    )
    ok "🎇 Got the cluster [$(dt "$t0") sec]. Cost: $(cost)"
}

function ensure_local_kubectl {
    shw get_kubeconfig
    shw set_ssh_config
    shw "$exedir/$exe" k get nodes
}
function get_kubeconfig {
    test -z "$IP_PROXY_" && get_proxy_ips
    shw clear_ip_from_known_hosts "$IP_PROXY_" >/dev/null 2>&1
    ssh "root@$IP_PROXY_" cat kubeconfig >"$FN_KUBECONFIG"
    chmod 600 "$FN_KUBECONFIG"
    test -z "FN_LINK_KUBECONFIG" || shw link_kubeconfig
    proxy_is_lb && shw set_localhost_to_kubeconfig
}
function link_kubeconfig {
    run rm -f "$FN_LINK_KUBECONFIG"
    run ln -s "$FN_KUBECONFIG" "$FN_LINK_KUBECONFIG"
}
function set_localhost_to_kubeconfig {
    sed -i 's|server: https://.*:6443|server: https://127.0.0.1:'"$SSH_TUNNEL_PORT"'|' "$FN_KUBECONFIG"
}
function ssh_config_add_master_host {
    get_ips "master$1"
    echo "Host $NAME-m$1
    HostName $ip_priv
    User root
    Port $HK_SSH_PORT
    ProxyCommand ssh -W %h:%p $NAME-proxy"
}
function ssh_config_add_proxy_host {
    echo "Host $NAME-proxy
    HostName $IP_PROXY_
    User root
    Port $HK_SSH_PORT
    LocalForward $SSH_TUNNEL_PORT $ip_priv:6443"
}

function set_ssh_config {
    get_proxy_ips
    get_ips "master1" # our forwarding destination for kubectl
    local sep="# ---- cluster $NAME"
    local fn="$HOME/.ssh/config"
    local hosts && hosts="$(shw ssh_config_add_proxy_host)"
    for i in 1 2 3; do hosts="$hosts\n$(shw ssh_config_add_master_host $i)"; done
    sed -i "/$sep/,/$sep/d" "$fn"
    echo -e "$sep\n$hosts\n$sep" >>"$fn"
    ok "Cluster hosts added" "E.g. ssh $NAME-proxy or ssh $NAME-m1"
}

# --------------------------------------------------------------
# Templates
# --------------------------------------------------------------
t_net() {
    echo '{ 
        "name":       "'"$1"'",
        "ip_range":   "'"${2}"'/16",
        "expose_routes_to_vswitch":false,
        "subnets": [{ "ip_range":   "'"${2}"'/24", "network_zone": "eu-central", "type": "cloud" }],
        "labels": {"environment":"dev", "k3s": "'"$NAME"'"}
    }'
}
function setup_ext_lb_caddy {
    local ip="${1:?Please supply an IP address}"
    local cfg="${2:?Argument 2 must be the full caddy config}"
    #cat <<EOF
    ssh "root@$ip" <<EOF
useradd caddy || true
mkdir -p /opt/caddy
test -f /root/caddy && mv /root/caddy /opt/caddy/caddy
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
ExecStart=/bin/bash -c 'iptables -t nat -A POSTROUTING -s "10.${HK_HOST_NETWORK}.0.0/16" -o eth0 -j MASQUERADE'

[Install]
WantedBy=multi-user.target
"

T_HK3S_CFG='
---
cluster_name: "'"$NAME"'"
kubeconfig_path: "./kubeconfig"
k3s_version: "'"$HK_VER_K3S"'"
networking:
  ssh:
    port: '"$HK_SSH_PORT"'
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
    subnet: 10.'$HK_HOST_NETWORK'.0.0/16
    existing_network_name: "'"$HK_HOST_NETWORK_NAME"'"
  cni:
    enabled: true
    encryption: false
    mode: '"$HK_CNI"'
  cluster_cidr: "'"$HK_CIDR_CLUSTER"'"
  service_cidr: "'"$HK_CIDR_SERVICE"'"
  cluster_dns: "'"$HK_DNS_CLUSTER"'"
datastore:
  mode: etcd # etcd (default) or external
  external_datastore_endpoint: postgres://....
schedule_workloads_on_masters: '"$HK_MASTERS_ARE_WORKERS"'

masters_pool:
  instance_type: "'"${HK_MASTERS_TYPE}"'"
  instance_count: '"${HK_MASTERS_COUNT}"'
  location: "'"${HK_LOCATION}"'"
  image: "'"${HK_MASTERS_IMG}"'"

worker_node_pools:
  - name: '"${NAME}"'-small-static
    instance_type: "'"${HK_WORKERS_TYPE}"'"
    instance_count: '"${HK_WORKERS_COUNT}"'
    location: "'"${HK_LOCATION}"'"
    image: "'"${HK_WORKERS_IMG}"'"
    # labels:
    #   - key: purpose
    #     value: blah
    # taints:
    #   - key: something
    #     value: value1:NoSchedule

  - name: '"${NAME}"'-medium-autoscaled
    instance_type: "'"${HK_AUTOSCALED_TYPE}"'"
    instance_count: '"${HK_AUTOSCALED_COUNT}"'
    location: "'"${HK_LOCATION}"'"
    image: "'"${HK_AUTOSCALED_IMG}"'"
    autoscaling:
      enabled: true
      min_instances: 0
      max_instances: '"${HK_AUTOSCALED_COUNT}"'

embedded_registry_mirror:
  enabled: '"${HK_REGISTRY_MIRROR}"'

additional_packages:
 - ifupdown
api_server_hostname: '"${API_SERVER_HOSTNAME:-first_master}"'
'
T_HK3S_POST_CREATE_CMDS='
post_create_commands:
- echo "Started" > /.status
- timedatectl set-timezone Europe/Berlin
- echo '\''SSH_KEY_BAST'\'' >> /root/.ssh/authorized_keys
- echo '\''SSH_KEY_LOCAL'\'' >> /root/.ssh/authorized_keys
- echo "root:$(head -c 50 /dev/urandom | base64)" | chpasswd
- mkdir -p /etc/network/interfaces.d
- iface="$(ip -o -4 addr list | grep " 10.'"$HK_HOST_NETWORK"'." | cut -d " " -f 2)"
- |
  cat > /etc/network/interfaces.d/$iface <<EOF
  auto $iface
  iface $iface inet dhcp
    post-up ip route add default via 10.'"$HK_HOST_NETWORK"'.0.1
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
- ip route add default via 10.'"$HK_HOST_NETWORK"'.0.1
- echo "Done" > /.status
'

# tools in fast mode done in bg - still we need that binenv path set at next login
T_SSHD=$(
    cat <<'EOF'
grep -q "HCLOUD_TOKEN" /etc/sshd/sshd_config || {
    echo 'AcceptEnv HCLOUD_TOKEN' >> /etc/ssh/sshd_config
    echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
    echo 'ClientAliveInterval 60' >> /etc/ssh/sshd_config
    echo 'ClientAliveCountMax 4' >> /etc/ssh/sshd_config
    systemctl daemon-reload
    systemctl reload sshd || systemctl restart ssh
}
type binenv 2>/dev/null || sed -i '1iexport PATH="$HOME/.binenv:$PATH"' ~/.bashrc
test -e "/root/.ssh/id_ed25519" || ssh-keygen -q -t ecdsa -N '' -f "$HOME/.ssh/id_ed25519" >/dev/null
touch /etc/postinstalled
EOF
)
T_INST_TOOLS=$(
    cat <<EOF
function have_ { type "\$1" >/dev/null 2>&1; }
if ! have_ kubectl || ! have_ helm || have_ hetzner-k3s; then
    wget -q "https://github.com/devops-works/binenv/releases/download/v0.19.11/binenv_linux_amd64" -O binenv
    chmod +x binenv && ./binenv update && ./binenv install binenv && rm binenv
    p='${URL_BINENV_PATCHES:-}'
    test -z "\$p" || wget -O - -q "\$p" | grep '^ ' >>\$HOME/.config/binenv/distributions.yaml
    type binenv 2>/dev/null || sed -i '1iexport PATH="\$HOME/.binenv:\$PATH"' ~/.bashrc
    export PATH="\$HOME/.binenv:\$PATH"
    for t in helm kubectl hetzner-k3s; do 
        which "\$t" && continue
        echo "Installing '\$t'"
        binenv install "\$t" && continue
        binenv update -f "\$t" # new in distribution.patch.yaml
        binenv install "\$t"
        which "\$t" && continue
        echo "\$t install failed" && exit 1
    done
fi
EOF
)
#echo -e "$T_INST_TOOLS"

false && . ./tools.sh && . ./main.sh || true # for LSP
