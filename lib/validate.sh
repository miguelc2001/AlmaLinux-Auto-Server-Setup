#!/usr/bin/env bash
# ============================================================
# lib/validate.sh - Validacao de input (IPs, FQDNs, etc.)
# ============================================================

# is_valid_ip 192.168.1.1
is_valid_ip() {
    local ip="$1"
    [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    local IFS=.
    # shellcheck disable=SC2206
    local parts=($ip)
    for p in "${parts[@]}"; do
        (( p >= 0 && p <= 255 )) || return 1
    done
    return 0
}

# is_valid_fqdn exemplo.pt
is_valid_fqdn() {
    local fqdn="$1"
    # Pelo menos um ponto, labels 1-63 chars alfanumericos/hifen, nao comeca/acaba em hifen
    [[ "$fqdn" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

# is_valid_hostname ns1  (sem ponto)
is_valid_hostname() {
    local h="$1"
    [[ "$h" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]
}

# ip_to_reverse_zone 192.168.1.100 -> 1.168.192.in-addr.arpa
ip_to_reverse_zone() {
    local ip="$1"
    local IFS=.
    # shellcheck disable=SC2206
    local p=($ip)
    printf '%s.%s.%s.in-addr.arpa' "${p[2]}" "${p[1]}" "${p[0]}"
}

# ip_last_octet 192.168.1.100 -> 100
ip_last_octet() {
    local ip="$1"
    echo "${ip##*.}"
}

# perguntar_ip <var> <prompt> [default]
perguntar_ip() {
    local __var="$1"; local __prompt="$2"; local __default="${3:-}"
    local __v
    while true; do
        ler __v "$__prompt" "$__default"
        if is_valid_ip "$__v"; then
            printf -v "$__var" '%s' "$__v"
            return 0
        fi
        echo "IP invalido: '$__v'. Usa formato xxx.xxx.xxx.xxx com cada octeto 0-255."
    done
}

# perguntar_fqdn <var> <prompt> [default]
perguntar_fqdn() {
    local __var="$1"; local __prompt="$2"; local __default="${3:-}"
    local __v
    while true; do
        ler __v "$__prompt" "$__default"
        if is_valid_fqdn "$__v"; then
            printf -v "$__var" '%s' "$__v"
            return 0
        fi
        echo "FQDN invalido: '$__v'. Ex.: exemplo.pt, servidor.empresa.com"
    done
}
