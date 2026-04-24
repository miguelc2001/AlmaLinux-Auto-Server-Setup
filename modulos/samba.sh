#!/usr/bin/env bash
# ============================================================
# modulos/samba.sh - SAMBA (Ponto 2)
# ============================================================
# Operacoes:
#   - Criar partilha Linux para maquinas Windows
#   - Alterar (read-only, guest, browseable)
#   - Desativar (available = no)
#   - Eliminar
#   - Listar partilhas
#   - Mapear partilha Windows -> Linux via mount.cifs (smbmount)
#
# Cada partilha e um bloco [nome] em /etc/samba/smb.conf.
# Fazemos sempre backup antes de editar + testparm antes de
# aplicar. SELinux: samba_share_t para paths fora de /home.
# ============================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

_testar_e_recarregar() {
    local msg="$1"
    if testparm -s "$SAMBA_CONF" >/dev/null 2>&1; then
        systemctl reload smb 2>/dev/null || systemctl restart smb
        systemctl reload nmb 2>/dev/null || systemctl restart nmb || true
        ok "$msg"
    else
        erro "testparm falhou. Config invalida."
        return 1
    fi
}

_partilha_existe() {
    local nome="$1"
    grep -Eq "^\[${nome}\]" "$SAMBA_CONF"
}

_listar_partilhas_custom() {
    # Lista secoes que nao sao globais (global, homes, printers)
    grep -Eo '^\[[^]]+\]' "$SAMBA_CONF" \
        | tr -d '[]' \
        | grep -Ev '^(global|homes|printers|print\$)$'
}

# ------------------------------------------------------------
# Criar partilha
# ------------------------------------------------------------
samba_criar() {
    title "Criar partilha SAMBA"
    local nome path user ro
    ler nome "Nome da partilha (ex: publico)" ""
    [[ -z "$nome" ]] && { erro "Nome vazio."; return 1; }
    if _partilha_existe "$nome"; then
        warn "Partilha '$nome' ja existe."; return 1
    fi

    ler path "Path no Linux (ex: /srv/samba/${nome})" "/srv/samba/${nome}"
    ler user "Utilizador dono (tem de existir no Linux)" "root"

    if ! id "$user" >/dev/null 2>&1; then
        warn "Utilizador '$user' nao existe no sistema."
        if confirmar "Criar o utilizador '$user' agora?"; then
            useradd -m "$user" || true
            passwd "$user"
        else
            return 1
        fi
    fi

    confirmar "Partilha read-only?" && ro="yes" || ro="no"
    local guest
    confirmar "Permitir acesso guest (sem password)?" && guest="yes" || guest="no"

    mkdir -p "$path"
    chown "${user}:${user}" "$path"
    chmod 2775 "$path"

    # SELinux
    if comando_existe semanage; then
        semanage fcontext -a -t samba_share_t "${path}(/.*)?" 2>/dev/null || true
    fi
    restorecon -R "$path" 2>/dev/null || true

    # Garantir que o user tem password SMB
    if ! pdbedit -L 2>/dev/null | grep -q "^${user}:"; then
        info "Define password SAMBA para $user:"
        smbpasswd -a "$user"
    fi

    backup_file "$SAMBA_CONF"
    cat >> "$SAMBA_CONF" <<EOF

[${nome}]
    path = ${path}
    valid users = ${user}
    read only = ${ro}
    guest ok = ${guest}
    browseable = yes
    writable = $([ "$ro" = "yes" ] && echo no || echo yes)
    create mask = 0664
    directory mask = 2775
EOF

    _testar_e_recarregar "Partilha '$nome' criada em ${path}"
}

# ------------------------------------------------------------
# Alterar partilha (toggle read-only)
# ------------------------------------------------------------
samba_alterar() {
    title "Alterar partilha"
    _listar_partilhas_custom | nl -w2 -s') '
    local nome; ler nome "Nome da partilha a alterar" ""
    _partilha_existe "$nome" || { erro "Nao existe."; return 1; }

    echo "  1) Alternar read-only / writable"
    echo "  2) Alternar guest ok"
    local opc; ler opc "Opcao" "1"

    backup_file "$SAMBA_CONF"
    case "$opc" in
        1)
            if grep -A15 "^\[${nome}\]" "$SAMBA_CONF" | grep -q 'read only = yes'; then
                sed -i "/^\[${nome}\]/,/^\[/ { s/read only = yes/read only = no/; s/writable = no/writable = yes/ }" "$SAMBA_CONF"
                ok "'$nome' agora e writable"
            else
                sed -i "/^\[${nome}\]/,/^\[/ { s/read only = no/read only = yes/; s/writable = yes/writable = no/ }" "$SAMBA_CONF"
                ok "'$nome' agora e read-only"
            fi
            ;;
        2)
            if grep -A15 "^\[${nome}\]" "$SAMBA_CONF" | grep -q 'guest ok = yes'; then
                sed -i "/^\[${nome}\]/,/^\[/ s/guest ok = yes/guest ok = no/" "$SAMBA_CONF"
                ok "'$nome' sem guest"
            else
                sed -i "/^\[${nome}\]/,/^\[/ s/guest ok = no/guest ok = yes/" "$SAMBA_CONF"
                ok "'$nome' permite guest"
            fi
            ;;
        *) erro "Opcao invalida"; return 1 ;;
    esac
    _testar_e_recarregar "Partilha '$nome' alterada"
}

# ------------------------------------------------------------
# Desativar (available = no, mantem bloco)
# ------------------------------------------------------------
samba_desativar() {
    title "Desativar partilha"
    _listar_partilhas_custom | nl -w2 -s') '
    local nome; ler nome "Nome" ""
    _partilha_existe "$nome" || { erro "Nao existe."; return 1; }

    backup_file "$SAMBA_CONF"
    # Remove qualquer 'available' anterior e adiciona 'available = no'
    sed -i "/^\[${nome}\]/,/^\[/ { /^[[:space:]]*available[[:space:]]*=/d }" "$SAMBA_CONF"
    sed -i "/^\[${nome}\]/a\    available = no" "$SAMBA_CONF"
    _testar_e_recarregar "Partilha '$nome' desativada (available = no)"
}

samba_ativar() {
    title "Reativar partilha"
    _listar_partilhas_custom | nl -w2 -s') '
    local nome; ler nome "Nome" ""
    _partilha_existe "$nome" || { erro "Nao existe."; return 1; }
    backup_file "$SAMBA_CONF"
    sed -i "/^\[${nome}\]/,/^\[/ { /^[[:space:]]*available[[:space:]]*=/d }" "$SAMBA_CONF"
    _testar_e_recarregar "Partilha '$nome' reativada"
}

# ------------------------------------------------------------
# Eliminar
# ------------------------------------------------------------
samba_eliminar() {
    title "Eliminar partilha"
    _listar_partilhas_custom | nl -w2 -s') '
    local nome; ler nome "Nome" ""
    _partilha_existe "$nome" || { erro "Nao existe."; return 1; }
    confirmar "Eliminar definitivamente '$nome' de smb.conf?" || return 0
    backup_file "$SAMBA_CONF"
    # Usar awk para apagar bloco ate proximo [ ou EOF
    awk -v s="[${nome}]" '
        BEGIN { skip = 0 }
        $0 == s { skip = 1; next }
        skip && /^\[/ { skip = 0 }
        !skip { print }
    ' "$SAMBA_CONF" > "${SAMBA_CONF}.tmp" && mv "${SAMBA_CONF}.tmp" "$SAMBA_CONF"
    _testar_e_recarregar "Partilha '$nome' eliminada"
}

samba_listar() {
    title "Partilhas SAMBA definidas"
    local ps; ps="$(_listar_partilhas_custom)"
    if [[ -z "$ps" ]]; then
        echo "(nenhuma)"
    else
        echo "$ps" | sed 's/^/  - /'
    fi
    echo
    info "Estado do servico:"
    systemctl is-active smb
}

# ------------------------------------------------------------
# Montar partilha Windows (smbmount / mount.cifs)
# ------------------------------------------------------------
samba_montar_windows() {
    title "Montar partilha Windows em Linux (smbmount/mount.cifs)"
    local host share user mnt
    ler host  "IP/hostname do servidor Windows" ""
    ler share "Nome da partilha Windows"        ""
    ler user  "Utilizador Windows"              "$USER"
    ler mnt   "Ponto de montagem local"         "/mnt/${share}"

    mkdir -p "$mnt"
    if ! comando_existe mount.cifs; then
        info "A instalar cifs-utils..."
        dnf install -y cifs-utils || { erro "Falha"; return 1; }
    fi
    info "A montar //${host}/${share} em ${mnt}..."
    if mount -t cifs "//${host}/${share}" "$mnt" -o "username=${user}"; then
        ok "Montagem concluida em $mnt"
        df -h "$mnt"
    else
        erro "mount.cifs falhou. Verifica credenciais e conectividade."
        return 1
    fi
}

samba_menu() {
    while true; do
        echo
        title "SAMBA"
        cat <<EOF
  1) Criar partilha (Linux -> Windows)
  2) Alterar partilha
  3) Desativar partilha
  4) Reativar partilha
  5) Eliminar partilha
  6) Listar partilhas
  7) Montar partilha Windows em Linux (smbmount)
  0) Voltar
EOF
        local opc; ler opc "Opcao" "0"
        case "$opc" in
            1) samba_criar ;;
            2) samba_alterar ;;
            3) samba_desativar ;;
            4) samba_ativar ;;
            5) samba_eliminar ;;
            6) samba_listar ;;
            7) samba_montar_windows ;;
            0) return 0 ;;
            *) warn "Opcao invalida" ;;
        esac
        pausa
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    samba_menu
fi
