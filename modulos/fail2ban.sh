#!/usr/bin/env bash
# ============================================================
# modulos/fail2ban.sh - Ponto 11 (2 valores)
# ============================================================
# Operacoes:
#   - Instalar e configurar fail2ban para proteger SSH contra
#     brute force
#   - Listar IPs bloqueados
#   - Desbloquear um IP dado pelo utilizador
#   - Reiniciar / estado do servico
#
# Nota: fail2ban vem do repo EPEL (instalado pelo install.sh).
# ============================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

_instalar_f2b() {
    if ! rpm -q fail2ban >/dev/null 2>&1; then
        info "fail2ban nao instalado. A instalar via dnf (EPEL)..."
        if ! rpm -q epel-release >/dev/null 2>&1; then
            dnf install -y epel-release || { erro "Falha EPEL"; return 1; }
        fi
        # O subpackage fail2ban-firewalld pode nao existir em todas as mirrors
        # EPEL. Tentamos com, se falhar tentamos sem.
        if ! dnf install -y fail2ban fail2ban-firewalld 2>/dev/null; then
            dnf install -y fail2ban || { erro "Falha ao instalar fail2ban"; return 1; }
        fi
    fi

    # Configurar jail.local se ainda nao existir
    if [[ ! -f "$FAIL2BAN_JAIL_LOCAL" ]]; then
        info "A criar $FAIL2BAN_JAIL_LOCAL"
        cat > "$FAIL2BAN_JAIL_LOCAL" <<'EOF'
# ============================================================
# jail.local - configuracao do projeto AS
# ============================================================
# Sobrepoe /etc/fail2ban/jail.conf sem tocar no original.
# ============================================================

[DEFAULT]
# Tempo de ban (10 minutos)
bantime  = 600
# Janela de observacao (10 minutos)
findtime = 600
# Tentativas antes de banir
maxretry = 5
# Usar firewalld (AlmaLinux 8 default)
banaction = firewallcmd-ipset
backend   = systemd

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/secure
maxretry = 5
EOF
    else
        ok "jail.local ja existe - nao sobrescrevi"
    fi

    systemctl enable fail2ban
    systemctl restart fail2ban
    systemctl is-active --quiet fail2ban && ok "fail2ban instalado e ativo" \
        || erro "fail2ban falhou a arrancar - ver 'systemctl status fail2ban'"
}

_estado_jail() {
    local jail="${1:-sshd}"
    if ! systemctl is-active --quiet fail2ban; then
        erro "fail2ban nao esta a correr."
        return 1
    fi
    fail2ban-client status "$jail" 2>/dev/null || {
        erro "Nao foi possivel obter estado do jail '$jail'."
        return 1
    }
}

f2b_instalar() {
    title "Instalar/configurar fail2ban"
    _instalar_f2b
}

f2b_estado() {
    title "Estado do fail2ban (jail sshd)"
    _estado_jail sshd
}

f2b_listar_bloqueados() {
    title "IPs atualmente bloqueados"
    if ! systemctl is-active --quiet fail2ban; then
        warn "fail2ban nao esta a correr. Ativar primeiro."
        return 1
    fi
    local banned
    banned="$(fail2ban-client status sshd 2>/dev/null | grep 'Banned IP list' | sed 's/.*Banned IP list:\s*//')"
    if [[ -z "$banned" ]]; then
        echo "(nenhum)"
    else
        echo "$banned" | tr ' ' '\n' | sed 's/^/  - /'
    fi
}

f2b_desbloquear() {
    title "Desbloquear IP"
    f2b_listar_bloqueados
    local ip
    perguntar_ip ip "IP a desbloquear" ""
    if fail2ban-client set sshd unbanip "$ip" >/dev/null 2>&1; then
        ok "IP $ip removido do jail sshd."
    else
        erro "Falha ao desbloquear $ip (talvez nao estivesse bloqueado)."
        return 1
    fi
}

f2b_reiniciar() {
    title "Reiniciar fail2ban"
    systemctl restart fail2ban
    systemctl is-active --quiet fail2ban && ok "fail2ban reiniciado." || erro "fail2ban falhou a arrancar."
}

f2b_menu() {
    while true; do
        echo
        title "fail2ban"
        cat <<EOF
  1) Instalar + configurar jail sshd
  2) Estado do jail sshd
  3) Listar IPs bloqueados
  4) Desbloquear IP
  5) Reiniciar fail2ban
  0) Voltar
EOF
        local opc; ler opc "Opcao" "0"
        case "$opc" in
            1) f2b_instalar ;;
            2) f2b_estado ;;
            3) f2b_listar_bloqueados ;;
            4) f2b_desbloquear ;;
            5) f2b_reiniciar ;;
            0) return 0 ;;
            *) warn "Opcao invalida" ;;
        esac
        pausa
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    f2b_menu
fi