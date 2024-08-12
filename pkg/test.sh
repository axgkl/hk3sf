# --------------------------------------------------------------
# Tests
# --------------------------------------------------------------

# 💡 Scheduling pods over all nodes, incl. autoscaled ones
function test_autoscale {
    # We schedule as many replicas as possible nodes in your setup,
    # with a taint to have them only on seperate nodes - which causes autoscale
    # Autoscaler has a long (minute) time until it creates nodes.
    # and even longer to delete them. So please be patient with this test.
    # ❗ Do NOT delete nodes via kubectl. They will remain up but not outside the cluster.
    local d="$CACHE_DIR/test_autoscale" && mkdir -p "$d"
    local m="$d/manifest.yaml"
    test "$HK_AUTOSCALED_COUNT" == "0" && {
        ok "Skipping autoscale test - you have no autoscaled nodes" "Set \$HK_AUTOSCALED_COUNT to > 0"
        return 0
    }
    local replicas && replicas="$((MASTERS_COUNT + WORKERS_COUNT + AUTOSCALED_COUNT))"
    out "Applying $replicas replicas with node taint"
    r_autoscale_manifest "$replicas" >"$m"
    run kubectl apply -f "$m"
    ok "Applied $replicas replicas." "$0 log 'autoscale|controller-manager' # in another terminal"
    local n shwn=''
    while true; do
        n="$(kubectl get nodes && kubectl get pods -n default -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}' | grep autoscaled-hello)"
        test "$shwn" != "$n" && out "$n" && shwn="$n"
        test "$(grep -c "Running" <<<"$n")" == "$replicas" && break
        sleep 2
    done
    report
    ok "🟩 Success. All $replicas pods are running - scaling down again" "Nodes should be gone within 10-20 minutes if there is no other workload on them. Logs: $ME log 'autoscale|controller-manager' -f"
    shw kubectl delete -f "$m"
}

r_autoscale_manifest() {
    local replicas="${1:?Require replicas}"
    cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: autoscaled-hello-world
spec:
  replicas: $replicas
  selector:
    matchLabels:
      app: autoscaled-hello-world
  template:
    metadata:
      labels:
        app: autoscaled-hello-world
    spec:
      containers:
      - name: autoscaled-hello-world
        image: k8s.gcr.io/echoserver:1.4
        ports:
        - containerPort: 8080
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: "app"
                operator: In
                values: 
                - autoscaled-hello-world
            topologyKey: "kubernetes.io/hostname"
EOF
}

# 💡 Creating a test service with all std http feats
function test_http_svc_nginx {
    # SSL + Proxy Protocol
    # Session Stickyness
    # -k: Keep, do not delete after success
    # rm: Delete the service
    local no_rm=false && test "${1:-}" == "-k" && no_rm=true
    test "${keep:-}" == "true" && no_rm=true
    get_proxy_ips
    local d="$CACHE_DIR/test_ssl_and_proxy_protocol_nginx" && mkdir -p "$d"
    local m="$d/manifest.yaml"
    test "${1:-}" == "rm" && {
        shw kubectl delete -f "$m"
        ok "Deleted test service"
        return
    }
    test -z "$DOMAIN" && die "DOMAIN not set" "Configure \$DOMAIN, required for SSL"
    local h="hello-world.$DOMAIN"
    while true; do
        shw dig +short "$h" | grep -q "^$IP_PROXY_$" && break
        out "Please configure $h resolving to our proxy lb ip: $IP_PROXY_\n${L}Best is, you create a wildcard resolution for *.$DOMAIN pointing to the ip of the external loadbalancer."
        sleep 3
    done
    ok "$h resolves to $NAME-proxy [$IP_PROXY_]"
    out "Creating test http server at $h"
    import render_svc
    render_svc hostname="$h" \
        name="hello-world" \
        replicas=3 \
        image="rancher/hello-world" \
        --sticky-sessions
    echo -e "$retval_" >"$m"
    shw kubectl apply -f "$m"
    local ipl && ipl="$(shw curl -4 -s ifconfig.me)"
    out "Our current external IP: $ipl"
    local t=false fnc="$CACHE_DIR/cookies.txt"
    local url="https://$h/"
    ok "Waiting max 60s for certification of $url ..."
    for _ in {1..30}; do sleep 2 && curl -s "$url" >/dev/null && break || echo -n '.'; done
    curl -s "$url" >/dev/null || die "SSL test failed" "Maybe run again in a while (letsecrypt rate limit)"
    ok "SSL test passed, testing proxy proto"
    for _ in {1..30}; do sleep 1 && curl -s "$url" | grep -q "$ipl" && break || echo -n '.'; done
    curl -s "$url" | grep "$ipl" || die "Proxy protocol test failed"
    ok "Proxy Protocol test passed"
    local pod && pod="$(curl -b "$fnc" -s "$url" | grep "Pod")"
    out "Testing session stickyness... \n$L  Pod:$pod\n  Cookie file: $fnc$O"
    t=true
    for _ in {1..5}; do
        test "$pod"="$(curl -b "$fnc" -s "$url" | grep "Pod")" || t=false
    done
    $t || die "Session stickyness test failed" "Curling $h did not return the same pod"
    ok "Session stickiness test passed, got 5 times the same pod"
    local msg="🟩 Success. Visit https://$h 🎇"

    $no_rm && ok "$msg" "Note: \$keep was set -> call this with rm to delete the service" && return
    shw kubectl delete -f "$m"
    ok "$msg" "You can run this func with -k (keep) or export keep=true, and I will not destroy the server"
}

false && . ./tools.sh && . ./pkg/svc.sh || true
