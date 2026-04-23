#!/usr/bin/env bash
# ============================================================
# install.sh - Bootstrap do servidor AlmaLinux 8
# ============================================================
# Instala todos os packages necessarios para os 13 pontos do
# projeto, habilita/arranca os servicos, abre as portas no
# firewalld e ajusta SELinux. Correr UMA VEZ depois de clonar.
#
# Uso: sudo ./install.sh
# ============================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root

title "Bootstrap do servidor"
info  "Distro alvo: AlmaLinux 8 (RHEL-like)"

# ------------------------------------------------------------
# 1) EPEL (necessario para fail2ban e knockd)
# ------------------------------------------------------------
title "EPEL"
if ! rpm -q epel-release >/dev/null 2>&1; then
    info "A instalar epel-release..."
    dnf install -y epel-release || { erro "Falha a instalar EPEL"; exit 1; }
else
    ok "EPEL ja instalado"
fi

# ------------------------------------------------------------
# 2) Packages principais
# ------------------------------------------------------------
title "Packages"
PACOTES=(
    bind bind-utils                     # Ponto 1, 4, 5, 6, 13a
    httpd                               # Ponto 3
    samba samba-client cifs-utils       # Ponto 2
    nfs-utils                           # Ponto 7
    tar rsync                           # Ponto 9
    mdadm                               # Ponto 10
    fail2ban                            # Ponto 11 (EPEL)
    knock-server knock                  # Ponto 12 (EPEL) - servidor+cliente knockd
    policycoreutils-python-utils        # semanage/restorecon
    firewalld
    nmap-ncat                           # cliente nc para port-knock
)

info "A instalar: ${PACOTES[*]}"
if ! dnf install -y "${PACOTES[@]}"; then
    warn "Alguns packages podem nao estar disponiveis. A tentar sem knock/knock-server e sem fail2ban-firewalld..."
    # Construir lista sem os pacotes que podem faltar em certas mirrors
    PACOTES_CORE=()
    for p in "${PACOTES[@]}"; do
        case "$p" in
            knock-server|knock) ;;          # saltar
            *) PACOTES_CORE+=("$p") ;;
        esac
    done
    dnf install -y "${PACOTES_CORE[@]}" || warn "Packages core falharam - rever manualmente"
    # Tentar knock sozinho
    dnf install -y knock || dnf install -y knock-server || warn "knock/knockd nao disponivel nesta mirror"
fi
ok "Packages instalados (ou avisos acima)"

# ------------------------------------------------------------
# 3) Firewalld - abrir servicos principais
# ------------------------------------------------------------
title "Firewalld"
systemctl enable --now firewalld
for svc in dns http https samba nfs; do
    firewall-cmd --permanent --add-service="$svc" >/dev/null 2>&1 || true
done
# SSH e aberto por default mas deixamos explicito
firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1 || true
# Portas do knock (vao ser usadas pelo cliente para a sequencia)
for port in 7000 8000 9000; do
    firewall-cmd --permanent --add-port="$port/tcp" >/dev/null 2>&1 || true
done
firewall-cmd --reload >/dev/null 2>&1 || true
ok "Firewalld configurado (dns/http/samba/nfs/ssh abertos)"

# ------------------------------------------------------------
# 4) SELinux booleans
# ------------------------------------------------------------
title "SELinux"
if comando_existe setsebool; then
    setsebool -P samba_enable_home_dirs on 2>/dev/null || true
    setsebool -P httpd_can_network_connect on 2>/dev/null || true
    setsebool -P nfs_export_all_rw on 2>/dev/null || true
    setsebool -P nfs_export_all_ro on 2>/dev/null || true
    ok "SELinux booleans aplicados"
else
    warn "setsebool nao disponivel (SELinux desabilitado?)"
fi

# ------------------------------------------------------------
# 5) Diretorias de trabalho
# ------------------------------------------------------------
title "Diretorias"
mkdir -p "$CONFIG_BACKUP_DIR" "$BACKUP_DIR" "$(dirname "$LOG_FILE")" \
         "$NAMED_BLACKLIST_DIR" "$PROJECT_ROOT"
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"
ok "Estrutura de diretorias criada"

# ------------------------------------------------------------
# 6) Inicializar includes do BIND
# ------------------------------------------------------------
title "BIND - includes custom"
if [[ ! -f "$NAMED_CUSTOM_INCLUDE" ]]; then
    touch "$NAMED_CUSTOM_INCLUDE"
    chown root:named "$NAMED_CUSTOM_INCLUDE" 2>/dev/null || true
    chmod 640 "$NAMED_CUSTOM_INCLUDE"
fi
if [[ ! -f "$NAMED_BLACKLIST_INCLUDE" ]]; then
    touch "$NAMED_BLACKLIST_INCLUDE"
    chown root:named "$NAMED_BLACKLIST_INCLUDE" 2>/dev/null || true
    chmod 640 "$NAMED_BLACKLIST_INCLUDE"
fi

# Garantir que named.conf faz include dos nossos ficheiros
if ! grep -q "$NAMED_CUSTOM_INCLUDE" "$NAMED_CONF"; then
    backup_file "$NAMED_CONF"
    {
        echo ""
        echo "// === Includes do projeto AS ==="
        echo "include \"$NAMED_CUSTOM_INCLUDE\";"
        echo "include \"$NAMED_BLACKLIST_INCLUDE\";"
    } >> "$NAMED_CONF"
    ok "Includes adicionados a $NAMED_CONF"
else
    ok "named.conf ja inclui os ficheiros do projeto"
fi

# Permitir queries de qualquer rede interna (ambiente de testes)
if grep -Eq '^\s*allow-query\s*\{\s*localhost\s*;\s*\}\s*;' "$NAMED_CONF"; then
    backup_file "$NAMED_CONF"
    sed -i 's/allow-query *{ *localhost *; *};/allow-query { any; };/' "$NAMED_CONF"
    info "allow-query alargado para 'any' (ambiente de laboratorio)"
fi
# E escutar em todas as interfaces
sed -i 's/listen-on port 53 { 127.0.0.1; };/listen-on port 53 { any; };/' "$NAMED_CONF" || true

# ------------------------------------------------------------
# 7) Ativar servicos
# ------------------------------------------------------------
title "Servicos"
for svc in named httpd smb nmb nfs-server fail2ban; do
    systemctl enable --now "$svc" 2>/dev/null && ok "$svc ativado" \
        || warn "Nao foi possivel ativar $svc (pode precisar de config primeiro)"
done

# ------------------------------------------------------------
# 8) Fim
# ------------------------------------------------------------
title "Pronto"
echo
echo "Proximo passo: sudo ./asmenu.sh"
echo
echo "Nota: edita config/defaults.conf para pores o IP real do"
echo "      servidor (atualmente $SERVER_IP)."
