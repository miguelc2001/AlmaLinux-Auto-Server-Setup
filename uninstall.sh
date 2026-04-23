#!/usr/bin/env bash
# ============================================================
# uninstall.sh - Desfaz o que o projeto criou
# ============================================================
# NAO remove os packages. Apenas limpa os ficheiros de
# configuracao que o projeto adicionou (zonas DNS, vhosts,
# partilhas samba/nfs). Util para voltar a testar do zero.
#
# Uso: sudo ./uninstall.sh
# ============================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root

warn "Este script remove todas as zonas DNS, vhosts e docroots"
warn "criados pelo projeto. As partilhas samba/nfs NAO sao"
warn "removidas automaticamente - usa os submenus para isso."
confirmar "Prosseguir?" || exit 0

# Remover zonas DNS do projeto
if [[ -f "$NAMED_CUSTOM_INCLUDE" ]]; then
    backup_file "$NAMED_CUSTOM_INCLUDE"
    : > "$NAMED_CUSTOM_INCLUDE"
    ok "Zonas custom DNS removidas."
fi
if [[ -f "$NAMED_BLACKLIST_INCLUDE" ]]; then
    backup_file "$NAMED_BLACKLIST_INCLUDE"
    : > "$NAMED_BLACKLIST_INCLUDE"
    ok "Blacklist DNS limpa."
fi
rm -rf "$NAMED_BLACKLIST_DIR"
# Apagar zonefiles que o projeto criou (apenas .zone em /var/named que nao vem por default)
# Cuidado: nao apagar zonefiles do sistema
for f in "$NAMED_ZONES_DIR"/*.zone; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f")
    # Nao tocar em named.ca, named.empty, etc.
    case "$base" in
        named.*) continue ;;
    esac
    rm -f "$f"
done

# Remover vhosts criados (os que temos na pasta conf.d com dominio.tld.conf)
for f in "$HTTPD_CONF_D"/*.conf; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f")
    case "$base" in
        ssl.conf|welcome.conf|autoindex.conf|userdir.conf|php.conf|README) continue ;;
    esac
    # So apagar se parecer um dominio
    if [[ "$base" =~ \. ]]; then
        backup_file "$f"
        rm -f "$f"
    fi
done

# Recarregar
systemctl reload named 2>/dev/null || systemctl restart named 2>/dev/null || true
systemctl reload httpd 2>/dev/null || systemctl restart httpd 2>/dev/null || true

ok "Uninstall concluido. Packages NAO foram removidos."
