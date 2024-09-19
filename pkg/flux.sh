function ensure_flux {
    shw flux check --pre || die "Pre-check failed"
    export GITHUB_TOKEN="${GH_GITOPS_TOKEN:-}"
    shw flux bootstrap github --owner="$GH_GITOPS_USER" --repository="other$GH_GITOPS_REPO" --branch=main --path=./clusters/my-cluster --personal
    shw flux check || die "flux post-check failed"
}
function ensure_flux_helm {
    shw flux create source helm starboard-operator --url https://aquasecurity.github.io/helm-charts --namespace starboard-system
}
false && . ./tools.sh && . ./conf.sh || true

# function digitalocean_dns_add {
#     local host="$1" ip="$2" domain="$3" token="${DNS_API_TOKEN:-}"
#     test -z "$token" && die "No \$DNS_API_TOKEN"
#     local h && h="$(digitalocean_dns_by_name "$host" | jq -r .data)"
#     test -n "$h" && test "$h" = "$ip" && {
#         ok "Already set" "$host -> $ip"
#         return 0
#     }
#     digitalocean_dns_rm_by_name "$host"
#     curl_ POST "$token" "https://api.digitalocean.com/v2/domains/$domain/records" \
#         -d "{\"type\":\"A\",\"name\":\"$host\",\"data\":\"$ip\",\"ttl\":$DNS_TTL}"
#     ok "DNS configured" "$host.$domain -> $ip"
# }
#
# function digitalocean_dns_list {
#     local domain="${DOMAIN#*.}"
#     local u="https://api.digitalocean.com/v2/domains/$domain/records"
#     curl_ GET "$DNS_API_TOKEN" "$u" | jq '.domain_records[] | {id, name, data, ttl}'
# }
#
# #💡 List DO DNS entries by name
# function digitalocean_dns_by_name {
#     # $1 maybe foo*, then we do startswith
#     # foo maybe a subdomain, i.e. *.test
#     local name="${1:?Req name}"
#     if [[ $name == *\* ]]; then
#         name="${name%\*}"
#         digitalocean_dns_list | jq -c 'select(.name | startswith("'"$name"'"))'
#     else
#         digitalocean_dns_list | jq -c 'select(.name == "'"$1"'")'
#     fi
#
# }
#
# function digitalocean_dns_rm_by_name {
#     local name="${1:?Req name}"
#     digitalocean_dns_by_name "$name" |
#         while read -r item; do digitalocean_dns_rm "$(echo "$item" | jq -r '.id')"; done
# }
# function digitalocean_dns_rm {
#     local u id="${1:?Require id of entry to delete}"
#     local domain="${DOMAIN#*.}"
#     for id in "$@"; do
#         u="https://api.digitalocean.com/v2/domains/$domain/records/$id"
#         curl_ DELETE "$DNS_API_TOKEN" "$u"
#         ok "Deleted dns record" "$u"
#     done
# }
#
# #💡 Adding a DNS subdomain entry
# function dns_add {
#     # Called autom. by ensure_proxy_is_loadbalancer
#     # When $DOMAIN of our cluster is configured to be foo.bar.com, we create a record '*.foo', pointing to the IP of the proxy server, under domain bar.com, which you must own.
#     # Note: $DNS_PROVIDER can be also a function, which sets all up as well (but you have to take care for idempotency)
#     proxy_is_lb || die "Proxy server is not a load balancer" "Manually add DNS record for the load balancer once created by CCM"
#     test -z "${1:-}" && get_proxy_ips
#     local ip="${1:-$IP_PROXY_}"
#     local d="${DOMAIN:-}"
#     test -z "$d" && die "No domain set"
#     local subdom="${d%%.*}"
#     local domain="${d#*.}"
#     local f="${DNS_PROVIDER:-}"
#     test -z "$f" && die "No DNS provider set"
#     # might be a callable
#     chk_have "$f" || {
#         f="${f}_dns_add"
#         chk_have "$f" || { out "DNS provider $f not found. Hint: You may supply a callable as well." && return 1; }
#     }
#     shw "$f" '*.'"$subdom"'' "$ip" "$domain"
#     shw dig +short "host$(date +%s).$DOMAIN"
# }
#
