#!/usr/bin/env bash
# ============================================================
# modulos/nfs.sh - NFS (Ponto 7)
# ============================================================
# Operacoes:
#   - Criar export em /etc/exports
#   - Alterar opcoes (rw/ro, sync/async)
#   - Desativar (comentar linha)
#   - Eliminar
#   - Listar exports
#   - Testar mount numa maquina cliente (comando sugerido)
# ============================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

_listar_exports() {
    # Mostra todos os exports (ativos e desativados)
    # Desativados aparecem com prefixo [DESATIVADO]
    grep -Ev '^\s*$' "$NFS_EXPORTS" 2>/dev/null | while IFS= read -r linha; do
        if [[ "$linha" =~ ^\s*# ]]; then
            echo "[DESATIVADO] ${linha#\#}"
        else
            echo "[ATIVO]      $linha"
        fi
    done || true
}

_listar_exports_ativos() {
    grep -Ev '^\s*(#|$)' "$NFS_EXPORTS" 2>/dev/null || true
}

_listar_exports_desativados() {
    grep -E '^\s*#[^!]' "$NFS_EXPORTS" 2>/dev/null | sed 's/^\s*#\s*//' || true
}

_export_existe() {
    local path="$1"
    grep -Eq "^[[:space:]]*${path}[[:space:]]" "$NFS_EXPORTS" 2>/dev/null
}

_export_desativado() {
    local path="$1"
    grep -Eq "^[[:space:]]*#[[:space:]]*${path}[[:space:]]" "$NFS_EXPORTS" 2>/dev/null
}

_aplicar_exports() {
    local msg="$1"
    if exportfs -ra 2>/dev/null; then
        systemctl reload nfs-server 2>/dev/null || systemctl restart nfs-server
        ok "$msg"
    else
        erro "exportfs -ra falhou. Ver /etc/exports."
        return 1
    fi
}

nfs_criar() {
    title "Criar export NFS"
    local path rede opts
    ler path "Diretoria a exportar" "/srv/nfs/share"
    ler rede "Rede autorizada (ex: 192.168.1.0/24 ou *)" "192.168.1.0/24"
    ler opts "Opcoes (ex: rw,sync,no_subtree_check,no_root_squash)" "rw,sync,no_subtree_check,no_root_squash"

    if _export_existe "$path"; then
        warn "Ja existe um export para $path."; return 1
    fi

    mkdir -p "$path"
    # Permissoes abertas para teste; em producao ajustar.
    chmod 755 "$path"
    # SELinux
    if comando_existe semanage; then
        semanage fcontext -a -t public_content_rw_t "${path}(/.*)?" 2>/dev/null || true
    fi
    restorecon -R "$path" 2>/dev/null || true

    backup_file "$NFS_EXPORTS"
    printf '%s %s(%s)\n' "$path" "$rede" "$opts" >> "$NFS_EXPORTS"
    _aplicar_exports "Export criado: $path $rede($opts)"
    echo
    info "Teste na maquina cliente:"
    echo "    sudo mkdir -p /mnt/nfs"
    echo "    sudo mount -t nfs ${SERVER_IP}:${path} /mnt/nfs"
}

nfs_alterar() {
    title "Alterar export NFS"
    _listar_exports_ativos | nl -w2 -s') '
    local path; ler path "Path do export" ""
    _export_existe "$path" || { erro "Nao existe ou esta desativado."; return 1; }

    local novas_opts
    ler novas_opts "Novas opcoes (ex: ro,sync,no_subtree_check)" "rw,sync,no_subtree_check"
    backup_file "$NFS_EXPORTS"
    local rede
    rede=$(grep -E "^[[:space:]]*${path}[[:space:]]" "$NFS_EXPORTS" | awk '{print $2}' | sed 's/(.*//')
    sed -i "\|^[[:space:]]*${path}[[:space:]]|d" "$NFS_EXPORTS"
    printf '%s %s(%s)\n' "$path" "${rede:-*}" "$novas_opts" >> "$NFS_EXPORTS"
    _aplicar_exports "Export $path alterado ($novas_opts)"
}

nfs_desativar() {
    title "Desativar export (comentar)"
    _listar_exports_ativos | nl -w2 -s') '
    local path; ler path "Path" ""
    _export_existe "$path" || { erro "Nao existe ou ja esta desativado."; return 1; }
    backup_file "$NFS_EXPORTS"
    sed -i "s|^\([[:space:]]*${path}[[:space:]]\)|# \1|" "$NFS_EXPORTS"
    _aplicar_exports "Export $path desativado"
}

nfs_ativar() {
    title "Ativar export (descomentar)"
    _listar_exports_desativados | nl -w2 -s') '
    local path; ler path "Path" ""
    _export_desativado "$path" || { erro "Nao existe nenhum export desativado com esse path."; return 1; }
    backup_file "$NFS_EXPORTS"
    sed -i "s|^[[:space:]]*#[[:space:]]*\(${path}[[:space:]]\)|\1|" "$NFS_EXPORTS"
    _aplicar_exports "Export $path reativado"
}

nfs_eliminar() {
    title "Eliminar export"
    _listar_exports | nl -w2 -s') '
    local path; ler path "Path" ""
    confirmar "Remover export $path de /etc/exports?" || return 0
    backup_file "$NFS_EXPORTS"
    sed -i "\|^[[:space:]#]*${path}[[:space:]]|d" "$NFS_EXPORTS"
    _aplicar_exports "Export $path eliminado"
}

nfs_listar() {
    title "Exports NFS"
    if [[ ! -s "$NFS_EXPORTS" ]] || ! _listar_exports | grep -q .; then
        echo "(nenhum)"
    else
        _listar_exports | sed 's/^/  /'
    fi
    echo
    info "exportfs -v:"
    exportfs -v 2>/dev/null || warn "nfs-server nao esta a correr."
}

nfs_testar_mount_local() {
    title "Testar mount NFS local (loopback)"
    local path mnt
    ler path "Path exportado"        "/srv/nfs/share"
    ler mnt  "Ponto de montagem"     "/mnt/nfs-test"
    mkdir -p "$mnt"
    if mount -t nfs "${SERVER_IP}:${path}" "$mnt"; then
        ok "Mount OK em $mnt"
        df -h "$mnt"
        info "Desmontar: umount $mnt"
    else
        erro "Mount falhou. Ver mensagens acima."
    fi
}

nfs_menu() {
    while true; do
        echo
        title "NFS"
        cat <<EOF
  1) Criar export
  2) Alterar export
  3) Desativar export
  4) Ativar export
  5) Eliminar export
  6) Listar exports
  7) Testar mount local (mount -t nfs)
  0) Voltar
EOF
        local opc; ler opc "Opcao" "0"
        case "$opc" in
            1) nfs_criar ;;
            2) nfs_alterar ;;
            3) nfs_desativar ;;
            4) nfs_ativar ;;
            5) nfs_eliminar ;;
            6) nfs_listar ;;
            7) nfs_testar_mount_local ;;
            0) return 0 ;;
            *) warn "Opcao invalida" ;;
        esac
        pausa
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    nfs_menu
fi