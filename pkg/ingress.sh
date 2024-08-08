# 💡 Caddy Ingress
function ensure_ingress_caddy {
    # ❗ This ingress can't be used for sticky sessions
    # https://github.com/caddyserver/ingress/issues/74#issuecomment-962909479
    # It is great for On Demand TLS though: https://github.com/caddyserver/ingress?tab=readme-ov-file#on-demand-tls
    # Auth HTTPS erradicates the need for Cert Manager
    # rm: Delete ingress and cert-manager
    local d="./deploys/caddy" && mkdir -p "$d"
    local m="$d/manifest.yaml"
    test "${1:-}" == "rm" && {
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
    shw add_namespace "caddy-system" "$m"
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

# 💡 Ninx Ingress: A real ingresss which handles layer 7 based routing
function ensure_ingress_nginx_with_certmgr {
    # supports sticky sessions
    # rm: Delete ingress and cert-manager
    local l d="./deploys/nginx" && mkdir -p "$d"
    local m="$d/manifest.yaml"
    test "${1:-}" == "rm" && {
        l="$(shw helm list -A)"
        grep -q ingress-nginx <<<"$l" && shw helm delete ingress-nginx -n ingress-nginx
        grep -q cert-manager <<<"$l" && shw helm delete cert-manager -n cert-manager
        ok "No ingress-nginx and cert-manager in your cluster"
        return
    }
    test -z "$EMAIL" && die "EMAIL not set" "Set \$EMAIL, required for SSL"

    ok "Adding nginx"
    echo -e "$T_NGINX_VALS" >"$d/values.yaml"
    shw helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    shw helm upgrade --install ingress-nginx ingress-nginx \
        --repo https://kubernetes.github.io/ingress-nginx \
        --namespace ingress-nginx --create-namespace -f "$d/values.yaml"

    ok "Adding cert manager"
    shw helm repo add jetstack https://charts.jetstack.io
    shw helm upgrade --install --namespace cert-manager --create-namespace --set installCRDs=true cert-manager jetstack/cert-manager
    r_certmgr "$EMAIL" >"$d/certmgr.yaml"
    shw kubectl apply -f "$d/certmgr.yaml"
    ok "Nginx Ingress and CertMgr using Lets encrypt installed\n${L}You can now run 'test_http_svc_nginx'$O"
}

T_NGINX_VALS=$(
    cat <<'EOF'
controller:
  kind: DaemonSet
  service:
    externalIPs: []
    nodePorts:
      http: 30080
      https: 30443
  config:
    # https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/
    use-proxy-protocol: "true"
    use-forwarded-headers: "true" # when others set XForwFor we take it

EOF
)

r_certmgr() {
    local email="${1:?Require email}"
    cat <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    email: $email
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
}

function render_ingress_nginx {
    retval_=''
    local name="" hostname="" stk=false ssl=true
    while [[ -n "${1:-}" ]]; do
        case "$1" in
        h=* | hostname=*) hostname="${1##*=}" && shift ;;
        n=* | name=*) name="${1##*=}" && shift ;;
        -n | --nossl) ssl=false && shift ;;
        -s | --sticky-sessions) stk=true && shift ;;
        *) shift ;;
        esac
    done
    test -z "$name" && die "name not set" "💡 Use n <name>"
    test -z "$hostname" && die "hostname not set" "💡 Use h <hostname>"
    local a=''
    if [[ $ssl == true ]] || [[ $stk == true ]]; then
        a='annotations:\n'
        $ssl && a=''$a'    cert-manager.io/cluster-issuer: "letsencrypt-prod"\n'
        $ssl && a=''$a'    kubernetes.io/tls-acme: "true"\n'
        $stk && a=''$a'    kubernetes.io/tls-acme: "true"\n'
        $stk && a=''$a'    nginx.ingress.kubernetes.io/affinity: "cookie"\n'
        $stk && a=''$a'    nginx.ingress.kubernetes.io/session-cookie-name: "route"\n'
        $stk && a=''$a'    nginx.ingress.kubernetes.io/session-cookie-expires: "172800"\n'
        $stk && a=''$a'    nginx.ingress.kubernetes.io/session-cookie-max-age: "172800"\n'
    fi
    retval_=$(
        cat <<EOF
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $name
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
