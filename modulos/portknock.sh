#!/usr/bin/env bash
# ============================================================
# modulos/portknock.sh - Ponto 12 (2 valores)
# ============================================================
# Implementa dois modos:
#   - SERVIDOR: configura knockd com uma sequencia de portas.
#     Apos sequencia correta, knockd adiciona regra firewalld
#     permitindo SSH da origem (%IP%) durante 60s.
#   - CLIENTE: faz os knocks na sequencia e abre a sessao SSH.
#
# Por default o SSH esta FECHADO no firewalld (so passa apos
# o knock). Isto e o que o enunciado pede no Ponto 12.
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

_detetar_iface() {
    # Devolve a interface com default route
    ip route show default | awk '/default/ {print $5; exit}'
}

pk_instalar_servidor() {
    title "Configurar servidor knockd"
    if ! rpm -q knock-server >/dev/null 2>&1 && ! rpm -q knock >/dev/null 2>&1; then
        info "A instalar knockd (EPEL)..."
        rpm -q epel-release >/dev/null 2>&1 || dnf install -y epel-release
        dnf install -y knock-server knock || dnf install -y knock || {
            erro "Falha ao instalar knockd."
            return 1
        }
    fi

    local iface
    iface="$(_detetar_iface)"
    [[ -z "$iface" ]] && iface="eth0"
    ler iface "Interface de rede" "$iface"

    backup_file "$KNOCKD_CONF"
    _render_template "$AS_ROOT/templates/knockd.conf.tpl" "$KNOCKD_CONF" \
        "IFACE=$iface" \
        "OPEN_SEQ=$KNOCK_OPEN_SEQ" \
        "CLOSE_SEQ=$KNOCK_CLOSE_SEQ"

    # Fechar SSH por default
    if firewall-cmd --list-services 2>/dev/null | grep -qw ssh; then
        firewall-cmd --permanent --remove-service=ssh >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        info "SSH removido do firewalld (so abre apos knock)"
    fi

    systemctl enable --now knockd 2>/dev/null || systemctl restart knockd
    if systemctl is-active --quiet knockd; then
        ok "knockd ativo. Sequencia abrir: $KNOCK_OPEN_SEQ | fechar: $KNOCK_CLOSE_SEQ"
    else
        erro "knockd nao arrancou. Ver 'systemctl status knockd' e 'journalctl -u knockd'."
        return 1
    fi
}

pk_estado() {
    title "Estado do knockd"
    systemctl status knockd --no-pager 2>/dev/null || warn "knockd nao esta instalado."
    echo
    echo "Regras firewalld (public):"
    firewall-cmd --zone=public --list-all 2>/dev/null || true
}

pk_cliente() {
    title "Cliente Port-Knocking"
    local host user porta
    ler  host "Host/IP do servidor" "$SERVER_IP"
    ler  user "Utilizador SSH"       "$USER"
    ler porta "Porta SSH"            "22"

    info "A bater nas portas: $KNOCK_OPEN_SEQ"
    # Usar 'knock' se existir; fallback para nc
    if comando_existe knock; then
        IFS=',' read -ra seq <<<"$KNOCK_OPEN_SEQ"
        knock -v "$host" "${seq[@]}"
    else
        IFS=',' read -ra seq <<<"$KNOCK_OPEN_SEQ"
        for p in "${seq[@]}"; do
            echo "  knock $host:$p"
            nc -z -w1 "$host" "$p" 2>/dev/null || true
            sleep 0.2
        done
    fi
    sleep 1
    info "A abrir ssh ${user}@${host}:${porta}..."
    ssh -p "$porta" "${user}@${host}"
}

pk_fechar_cliente() {
    title "Enviar sequencia de fecho"
    local host; ler host "Host/IP do servidor" "$SERVER_IP"
    if comando_existe knock; then
        IFS=',' read -ra seq <<<"$KNOCK_CLOSE_SEQ"
        knock -v "$host" "${seq[@]}"
    else
        IFS=',' read -ra seq <<<"$KNOCK_CLOSE_SEQ"
        for p in "${seq[@]}"; do
            nc -z -w1 "$host" "$p" 2>/dev/null || true
            sleep 0.2
        done
    fi
    ok "Sequencia de fecho enviada."
}

pk_menu() {
    while true; do
        echo
        title "Port Knocking (Ponto 12)"
        cat <<EOF
  --- SERVIDOR (configurar esta maquina) ---
  1) Instalar e configurar knockd (+ fechar SSH)
  2) Estado do knockd e firewalld
  --- CLIENTE (bater a porta de outra maquina) ---
  3) Cliente: abrir SSH (knock + ssh)
  4) Cliente: enviar sequencia de fecho
  0) Voltar
EOF
        local opc; ler opc "Opcao" "0"
        case "$opc" in
            1) pk_instalar_servidor ;;
            2) pk_estado ;;
            3) pk_cliente ;;
            4) pk_fechar_cliente ;;
            0) return 0 ;;
            *) warn "Opcao invalida" ;;
        esac
        pausa
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Cliente nao precisa de root; servidor sim. Menu decide.
    pk_menu
fi
