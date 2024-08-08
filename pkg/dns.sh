function digitalocean_add_dns {
    local host="$1" ip="$2" domain="$3" token="${DNS_API_TOKEN:-}"
    test -z "$token" && die "No \$DNS_API_TOKEN"
    curl_ POST "$token" "https://api.digitalocean.com/v2/domains/$domain/records" \
        -d "{\"type\":\"A\",\"name\":\"$host\",\"data\":\"$ip\",\"ttl\":1800}"
}

function digitalocean_dns_list {
    local domain="${DOMAIN#*.}"
    local u="https://api.digitalocean.com/v2/domains/$domain/records"
    curl_ GET "$DNS_API_TOKEN" "$u" | jq '.domain_records[] | {id, name, data}'
}

function digitalocean_dns_rm {
    local u id="${1:?Require id of entry to delete}"
    local domain="${DOMAIN#*.}"
    for id in "$@"; do
        u="https://api.digitalocean.com/v2/domains/$domain/records/$id"
        shw curl_ DELETE "$DNS_API_TOKEN" "$u"
    done
}

function dns_add {
    test -z "${1:-}" && get_proxy_ips
    local ip="${1:-$IP_PROXY_}"
    local d="${DOMAIN:-}"
    test -z "$d" && die "No domain set"
    local subdom="${d%%.*}"
    local domain="${d#*.}"
    local f="${DNS_PROVIDER:-}"
    test -z "$f" && die "No DNS provider set"
    chk_have "$f" || {
        f="${f}_add_dns"
        chk_have "$f" || { out "DNS provider $f not found. Hint: You may supply a callable as well." && return 1; }
    }
    shw "$f" '*.'"$subdom"'' "$ip" "$domain"
    ok "DNS configured: *.$DOMAIN -> $ip"
}

false && . ./tools.sh || true
