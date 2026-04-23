#!/usr/bin/env bash
# ============================================================
# modulos/backup.sh - Backups (Ponto 9)
# ============================================================
# Duas estrategias:
#   A) tar - snapshot completo de ficheiros/configs criticos
#      (/etc/passwd, shadow, group, gshadow, /etc/httpd,
#       /etc/samba, /var/named, /etc/exports, /etc/ssh).
#      Resulta num .tar.gz datado em $BACKUP_DIR/tar/.
#
#   B) rsync "incremental forever" das areas dos utilizadores
#      (/home). Usa --link-dest apontando para o snapshot
#      anterior: ficheiros inalterados sao hardlinks (zero
#      espaco), so o que mudou ocupa espaco novo.
#      Estrutura: $BACKUP_DIR/rsync/<YYYYmmdd-HHMMSS>/
#      Um symlink 'latest' aponta sempre para o ultimo.
# ============================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

TAR_DIR="$BACKUP_DIR/tar"
RSYNC_DIR="$BACKUP_DIR/rsync"

# ------------------------------------------------------------
# Ficheiros/pastas criticos para o snapshot tar
# ------------------------------------------------------------
BACKUP_PATHS=(
    /etc/passwd
    /etc/shadow
    /etc/group
    /etc/gshadow
    /etc/sudoers
    /etc/ssh
    /etc/httpd
    /etc/samba
    /etc/named.conf
    /etc/named
    /var/named
    /etc/exports
    /etc/fail2ban
    /etc/knockd.conf
    /etc/fstab
    /etc/mdadm.conf
    /etc/hosts
    /etc/hostname
    /etc/resolv.conf
)

# ------------------------------------------------------------
# Backup tar (snapshot completo, com data no nome)
# ------------------------------------------------------------
bkp_tar() {
    title "Backup tar de ficheiros/configs criticos"
    mkdir -p "$TAR_DIR"
    local ts; ts="$(date +%Y%m%d-%H%M%S)"
    local arq="$TAR_DIR/criticos-${ts}.tar.gz"

    # Filtrar existentes para nao fazer tar bombar
    local existentes=()
    for p in "${BACKUP_PATHS[@]}"; do
        [[ -e "$p" ]] && existentes+=("$p")
    done

    info "A criar $arq"
    if tar --ignore-failed-read -czpf "$arq" "${existentes[@]}" 2>/dev/null; then
        ok "Backup tar OK: $arq ($(du -h "$arq" | awk '{print $1}'))"
    else
        erro "tar retornou erros (alguns ficheiros podem nao ter sido lidos)."
    fi
    echo
    echo "Conteudo (resumo):"
    tar -tzf "$arq" 2>/dev/null | head -20
    echo "..."
}

# ------------------------------------------------------------
# Rsync incremental forever das areas dos utilizadores
# ------------------------------------------------------------
bkp_rsync_home() {
    title "Rsync incremental forever de /home"
    mkdir -p "$RSYNC_DIR"
    local ts; ts="$(date +%Y%m%d-%H%M%S)"
    local dest="$RSYNC_DIR/$ts"
    local latest="$RSYNC_DIR/latest"

    local link_opt=()
    if [[ -L "$latest" && -d "$latest" ]]; then
        link_opt=(--link-dest="$(readlink -f "$latest")")
        info "A basear no snapshot anterior: $(readlink "$latest")"
    else
        info "Primeiro snapshot (sem --link-dest)"
    fi

    rsync -aAX --delete "${link_opt[@]}" /home/ "$dest/"
    local rc=$?

    if [[ $rc -eq 0 ]]; then
        ln -snf "$ts" "$latest"
        ok "Snapshot criado em $dest"
        echo
        info "Tamanho do snapshot (sem contar hardlinks):"
        du -sh "$dest" 2>/dev/null
        info "Todos os snapshots:"
        ls -1 "$RSYNC_DIR" | grep -v '^latest$' | tail -5
    else
        erro "rsync falhou (codigo $rc)"
        return $rc
    fi
}

# ------------------------------------------------------------
# Listar
# ------------------------------------------------------------
bkp_listar() {
    title "Backups existentes"
    echo "--- tar ---"
    if [[ -d "$TAR_DIR" ]]; then
        ls -1tsh "$TAR_DIR" 2>/dev/null | head -10
    else
        echo "(nenhum)"
    fi
    echo
    echo "--- rsync (incremental) ---"
    if [[ -d "$RSYNC_DIR" ]]; then
        ls -1 "$RSYNC_DIR" | grep -v '^latest$' | tail -10
        [[ -L "$RSYNC_DIR/latest" ]] && echo "latest -> $(readlink "$RSYNC_DIR/latest")"
    else
        echo "(nenhum)"
    fi
}

bkp_restore_tar_info() {
    title "Restaurar backup tar"
    ls -1t "$TAR_DIR"/*.tar.gz 2>/dev/null | head -5 | nl -w2 -s') '
    local arq; ler arq "Caminho completo do .tar.gz" ""
    [[ -f "$arq" ]] || { erro "Ficheiro nao existe."; return 1; }
    warn "Este restore vai sobrepor ficheiros em / - EXTREMO CUIDADO."
    confirmar "Tens a certeza?" || return 0
    tar -xzpf "$arq" -C / && ok "Restore concluido." || erro "Restore falhou."
}

bkp_menu() {
    while true; do
        echo
        title "Backups (Ponto 9)"
        cat <<EOF
  1) Backup tar (ficheiros/configs criticos)
  2) Backup rsync incremental forever (/home)
  3) Listar backups
  4) Restaurar backup tar
  0) Voltar
EOF
        local opc; ler opc "Opcao" "0"
        case "$opc" in
            1) bkp_tar ;;
            2) bkp_rsync_home ;;
            3) bkp_listar ;;
            4) bkp_restore_tar_info ;;
            0) return 0 ;;
            *) warn "Opcao invalida" ;;
        esac
        pausa
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    bkp_menu
fi
