#!/usr/bin/env bash
# ============================================================
# asmenu.sh - Menu principal do projeto AS
# ============================================================
# Ponto de entrada unico. Corre como root.
#
# Uso: sudo ./asmenu.sh
# ============================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Guardar o AS_ROOT antes de fazer source dos modulos, porque cada modulo
# redefine SCRIPT_DIR quando e carregado via source (BASH_SOURCE[0] aponta
# para o modulo, nao para o asmenu.sh), corrompendo os paths seguintes.
_ASMENU_ROOT="$AS_ROOT"

# shellcheck source=modulos/dns.sh
source "$_ASMENU_ROOT/modulos/dns.sh"
# shellcheck source=modulos/web.sh
source "$_ASMENU_ROOT/modulos/web.sh"
# shellcheck source=modulos/samba.sh
source "$_ASMENU_ROOT/modulos/samba.sh"
# shellcheck source=modulos/nfs.sh
source "$_ASMENU_ROOT/modulos/nfs.sh"
# shellcheck source=modulos/backup.sh
source "$_ASMENU_ROOT/modulos/backup.sh"
# shellcheck source=modulos/raid.sh
source "$_ASMENU_ROOT/modulos/raid.sh"
# shellcheck source=modulos/fail2ban.sh
source "$_ASMENU_ROOT/modulos/fail2ban.sh"
# shellcheck source=modulos/portknock.sh
source "$_ASMENU_ROOT/modulos/portknock.sh"

_banner() {
    clear
    cat <<'EOF'
 _____________________________________________________________
|                                                             |
|   Administracao de Sistemas 2025/2026 - IPBeja              |
|   Projeto de automatizacao - Miguel Correia                 |
|   Docente: Armando Ventura                                  |
|_____________________________________________________________|
EOF
    printf ' Servidor: %s  | IP: %s\n' "$(hostname)" "$SERVER_IP"
    printf ' Log:      %s\n\n' "$LOG_FILE"
}

_ver_log() {
    title "Ultimas 30 linhas do log"
    if [[ -f "$LOG_FILE" ]]; then
        tail -n 30 "$LOG_FILE"
    else
        echo "(log vazio)"
    fi
    echo
    info "Snapshots de configuracao (backup antes de editar):"
    listar_backups_config
}

_estado_servicos() {
    title "Estado dos servicos"
    for svc in named httpd smb nmb nfs-server fail2ban knockd; do
        if systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "${svc}.service"; then
            local st
            st=$(systemctl is-active "$svc" 2>/dev/null)
            printf '  %-14s %s\n' "$svc" "$st"
        fi
    done
    echo
    info "Firewalld (zona public):"
    firewall-cmd --zone=public --list-services 2>/dev/null || echo "(firewalld inativo)"
}

main_menu() {
    while true; do
        _banner
        cat <<EOF
  1) DNS (BIND)                     [Pontos 1, 4, 5, 6, 13a]
  2) Web / Apache VirtualHosts      [Pontos 3, 6]
  3) SAMBA                          [Ponto 2]
  4) NFS                            [Ponto 7]
  5) Backups (tar + rsync)          [Ponto 9]
  6) RAID 5                         [Ponto 10]
  7) fail2ban                       [Ponto 11 - 2v]
  8) Port Knocking                  [Ponto 12 - 2v]
  ---------------------------------------------------
  9) Ver log / snapshots de config
  s) Estado dos servicos
  0) Sair

EOF
        local opc; ler opc "Opcao" "0"
        case "$opc" in
            1) dns_menu ;;
            2) web_menu ;;
            3) samba_menu ;;
            4) nfs_menu ;;
            5) bkp_menu ;;
            6) raid_menu ;;
            7) f2b_menu ;;
            8) pk_menu ;;
            9) _ver_log; pausa ;;
            s|S) _estado_servicos; pausa ;;
            0) echo "Ate a proxima!"; exit 0 ;;
            *) warn "Opcao invalida" ;;
        esac
    done
}

# Nao exigir root para o cliente port-knocking sozinho, mas o
# menu principal gere recursos do sistema -> precisa root.
require_root
main_menu