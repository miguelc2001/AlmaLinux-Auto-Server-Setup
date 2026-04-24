#!/usr/bin/env bash
# ============================================================
# modulos/web.sh - Apache VirtualHosts (Pontos 3, 6)
# ============================================================
# Operacoes:
#   - Criar VirtualHost para um dominio + pagina de boas-vindas
#   - Eliminar VirtualHost
#   - Listar VirtualHosts
#
# Contexto SELinux (httpd_sys_content_t) e aplicado ao criar
# o DocumentRoot.
# ============================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

_render_template() {
    local src="$1"; local dst="$2"; shift 2
    cp "$src" "$dst"
    for kv in "$@"; do
        local k="${kv%%=*}"; local v="${kv#*=}"
        sed -i "s@__${k}__@${v//@/\\@}@g" "$dst"
    done
}

_listar_vhosts() {
    ls -1 "$HTTPD_CONF_D"/*.conf 2>/dev/null \
        | xargs -r -n1 basename 2>/dev/null \
        | grep -v '^ssl\.conf$\|^welcome\.conf$\|^autoindex\.conf$\|^userdir\.conf$' \
        | sed 's/\.conf$//'
}

_aplicar_httpd() {
    local msg="$1"
    if httpd -t 2>/dev/null; then
        systemctl reload httpd 2>/dev/null || systemctl restart httpd
        ok "$msg"
    else
        erro "httpd -t falhou. Config invalida, ver '/var/log/httpd/error_log'."
        return 1
    fi
}

# ------------------------------------------------------------
# PONTO 3: Criar VirtualHost + pagina de boas-vindas
# ------------------------------------------------------------
web_criar_vhost() {
    title "Criar VirtualHost"
    local dom
    perguntar_fqdn dom "Dominio (ex: exemplo.pt)" ""
    local vhost_file="$HTTPD_CONF_D/${dom}.conf"
    local docroot="$HTTPD_DOCROOT_BASE/${dom}"

    if [[ -f "$vhost_file" ]]; then
        warn "VirtualHost '$dom' ja existe ($vhost_file)."
        return 1
    fi

    mkdir -p "$docroot"
    # Gerar index.html a partir do template
    _render_template "$AS_ROOT/templates/index.html.tpl" "$docroot/index.html" \
        "DOMINIO=$dom" \
        "SERVER_IP=$SERVER_IP" \
        "DATA=$(date '+%Y-%m-%d %H:%M')"

    # Gerar vhost.conf
    _render_template "$AS_ROOT/templates/vhost.tpl" "$vhost_file" \
        "DOMINIO=$dom" \
        "DOCROOT=$docroot"

    # SELinux: marcar o DocumentRoot como conteudo web
    if comando_existe semanage; then
        semanage fcontext -a -t httpd_sys_content_t "${docroot}(/.*)?" 2>/dev/null || true
    fi
    restorecon -R "$docroot" 2>/dev/null || true
    chown -R apache:apache "$docroot" 2>/dev/null || chown -R root:root "$docroot"
    chmod -R 755 "$docroot"

    _aplicar_httpd "VirtualHost '$dom' criado, docroot=$docroot"
    info "Teste: curl -H 'Host: $dom' http://$SERVER_IP/"
}

# ------------------------------------------------------------
# PONTO 6 (parcial): Eliminar VirtualHost
# ------------------------------------------------------------
web_eliminar_vhost() {
    title "Eliminar VirtualHost"
    local vhosts
    vhosts="$(_listar_vhosts || true)"
    if [[ -z "$vhosts" ]]; then
        warn "Nao ha VirtualHosts criados."
        return 1
    fi
    echo "VirtualHosts existentes:"
    echo "$vhosts" | nl -w2 -s') '
    local dom
    ler dom "Nome do VirtualHost a eliminar" ""
    local vhost_file="$HTTPD_CONF_D/${dom}.conf"
    if [[ ! -f "$vhost_file" ]]; then
        erro "VirtualHost '$dom' nao existe."; return 1
    fi
    confirmar "Eliminar VirtualHost '$dom' e o docroot /var/www/${dom}?" \
        || { info "Cancelado."; return 0; }

    backup_file "$vhost_file"
    rm -f "$vhost_file"
    # Apagar docroot so se for debaixo de /var/www (seguranca)
    if [[ -d "$HTTPD_DOCROOT_BASE/${dom}" ]]; then
        rm -rf "${HTTPD_DOCROOT_BASE:?}/${dom}"
    fi
    _aplicar_httpd "VirtualHost '$dom' eliminado"
}

web_listar() {
    title "VirtualHosts"
    local vhosts
    vhosts="$(_listar_vhosts || true)"
    if [[ -z "$vhosts" ]]; then
        echo "(nenhum)"
    else
        echo "$vhosts" | sed 's/^/  - /'
    fi
}

# ------------------------------------------------------------
# Menu
# ------------------------------------------------------------
web_menu() {
    while true; do
        echo
        title "Apache / VirtualHosts"
        cat <<EOF
  1) Criar VirtualHost + pagina boas-vindas
  2) Eliminar VirtualHost
  3) Listar VirtualHosts
  0) Voltar
EOF
        local opc; ler opc "Opcao" "0"
        case "$opc" in
            1) web_criar_vhost ;;
            2) web_eliminar_vhost ;;
            3) web_listar ;;
            0) return 0 ;;
            *) warn "Opcao invalida" ;;
        esac
        pausa
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    web_menu
fi
