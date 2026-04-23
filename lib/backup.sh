#!/usr/bin/env bash
# ============================================================
# lib/backup.sh - Snapshots de ficheiros de configuracao
# ============================================================
# Antes de qualquer script modificar um ficheiro do sistema
# (/etc/named.conf, smb.conf, exports, ...) chamamos
# backup_file <path> para guardar uma copia timestamped em
# $CONFIG_BACKUP_DIR. Ajuda a explicar na discussao que os
# scripts sao seguros.
# ============================================================

# backup_file /etc/named.conf
backup_file() {
    local src="$1"
    [[ -f "$src" ]] || return 0
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    local dest_dir="$CONFIG_BACKUP_DIR/$ts"
    mkdir -p "$dest_dir"
    # Preservar path relativo para ficar organizado
    local rel="${src#/}"
    mkdir -p "$dest_dir/$(dirname "$rel")"
    cp -a "$src" "$dest_dir/$rel"
    log BACKUP "Snapshot de $src -> $dest_dir/$rel"
}

# backup_files /etc/named.conf /etc/httpd/conf.d/foo.conf ...
backup_files() {
    for f in "$@"; do
        backup_file "$f"
    done
}

# listar_backups - mostra os snapshots existentes
listar_backups_config() {
    if [[ ! -d "$CONFIG_BACKUP_DIR" ]]; then
        echo "(sem snapshots)"
        return
    fi
    ls -1t "$CONFIG_BACKUP_DIR" 2>/dev/null | head -20
}
