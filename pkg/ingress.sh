#💡 Caddy Ingress
function ensure_ingress_caddy {
    # ❗ This ingress can't be used for sticky sessions
    # https://github.com/caddyserver/ingress/issues/74#issuecomment-962909479
    # It is great for On Demand TLS though: https://github.com/caddyserver/ingress?tab=readme-ov-file#on-demand-tls
    # Auth HTTPS erradicates the need for Cert Manager
    # rm: Delete ingress and cert-manager
    local d="./deploys/caddy" && mkdir -p "$d"
    local m="$d/manifest.yaml"
    test "${1:-}" = "rm" && {
        shw kubectl delete -f "$m"
        return
    }
    test -z "$EMAIL" && die "EMAIL not set" "Set \$EMAIL, required for SSL"
    echo -e "$T_CADDY_VALS" >"$d/values.yaml"
    shw helm template --namespace=caddy-system -f "$d/values.yaml" \
        --repo https://caddyserver.github.io/ingress/ \
        --atomic caddy caddy-ingress-controller >"$m"
    sed -i '/targetPort: http$/a \ \ \ \ \ \ nodePort: 30080' "$m"
    sed -i '/targetPort: https$/a \ \ \ \ \ \ nodePort: 30443' "$m"
    import render_namespace
    shw render_namespace "caddy-system" "$m"
    shw kubectl apply -f "$m"
    ok "Caddy deployed" "Logs: $0 log caddy"
}

T_CADDY_VALS="
replicaCount: 3
ingressController:
  config:
    debug: true
    email: $EMAIL
    onDemandTLS: false
    proxyProtocol: true
"

#💡 Ninx Ingress: A real ingresss which handles layer 7 based routing
function ensure_ingress_nginx {
    # supports sticky sessions
    local m l d="./deploys/nginx" rm=false && m="$d/manifest.yaml"

    while [[ -n "${1:-}" ]]; do case "$1" in
        --rm | rm) rm=true ;; # Remove ingress
        *) die "Unsupported" "$1" ;;
        esac && shift; done

    if $rm; then
        l="$(shw helm list -A)"
        grep -q ingress-nginx <<<"$l" && shw helm delete ingress-nginx -n ingress-nginx
        ok "No more ingress-nginx in your cluster"
        return
    fi

    mkdir -p "$d"

    ok "Adding nginx"
    echo -e "$T_NGINX_VALS" >"$d/values.yaml"
    shw helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    shw helm upgrade --install ingress-nginx ingress-nginx \
        --repo https://kubernetes.github.io/ingress-nginx \
        --namespace ingress-nginx --create-namespace -f "$d/values.yaml"
    ok "Nginx Ingress installed\n${L}Ensure also cert_manager and you can run 'test_http_svc_nginx'$O"

}

T_NGINX_VALS=$(
    # https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/
    cat <<'EOF'
controller:
  kind: DaemonSet
  service:
    externalIPs: []
    nodePorts:
      http: 30080
      https: 30443
  config:
    use-proxy-protocol: "true"
    use-forwarded-headers: "true" # when others set XForwFor we take it

EOF
)
#💡 For an actual service to be reachable via the ingress
function render_ingress_nginx {
    # ssl only  via letsencrypt-prod currently
    retval_=''
    local name="" namespace=default hostname="" stk=false ssl=true
    for arg in "$@"; do
        case "$arg" in
        N=* | namespace=*) namespace="${arg#*=}" ;;
        h=* | hostname=*) hostname="${arg#*=}" ;;
        n=* | name=*) name="${arg#*=}" ;;
        -n | --nossl) ssl=false ;;
        -s | --sticky-sessions) stk=true ;;
        *) out "ignoring arg: $arg" ;;
        esac
    done
    test -z "$name" && die "name not set" "💡 Use n <name>"
    test -z "$hostname" && die "hostname not set" "💡 Use h <hostname>"
    local a=''
    if [[ $ssl == true ]] || [[ $stk == true ]]; then
        a='annotations:\n'
        $ssl && a=''$a'    cert-manager.io/cluster-issuer: "letsencrypt-prod"\n'
        $stk && a=''$a'    kubernetes.io/tls-acme: "true"\n'
        $stk && a=''$a'    nginx.ingress.kubernetes.io/affinity: "cookie"\n'
        $stk && a=''$a'    nginx.ingress.kubernetes.io/session-cookie-name: "route"\n'
        $stk && a=''$a'    nginx.ingress.kubernetes.io/session-cookie-max-age: "172800"\n'
    fi
    retval_=$(
        cat <<EOF
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $name
  namespace: $namespace
  $a
spec:
  ingressClassName: nginx
  rules:
  - host: $hostname
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $name
            port:
              number: 80
  tls:
  - hosts:
    - $hostname
    secretName: $hostname-tls
EOF
    )
    echo -e "$retval_"
}

false && . ./tools.sh && . ./svc.sh || true
