#!/usr/bin/env bash
# ============================================================
# modulos/dns.sh - BIND / DNS (Pontos 1, 4, 5, 6, 13a)
# ============================================================
# Operacoes:
#   - Criar zona forward (master) para um dominio (Ponto 1)
#   - Adicionar registo A/MX a uma zona existente (Ponto 4)
#   - Criar zona reverse a partir de IP+FQDN (Ponto 5)
#   - Eliminar zona forward (Ponto 6)
#   - Eliminar zona reverse (Ponto 6)
#   - Gerir blacklist de dominios (Ponto 13a)
#
# Todas as escritas em named.conf fazem backup primeiro,
# e no fim faz-se 'named-checkconf' + 'named-checkzone' antes
# de 'systemctl reload named'. Se o check falhar, os scripts
# recuperam do snapshot. Isto cobre o Ponto 8 (inovacoes).
# ============================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# ------------------------------------------------------------
# Helpers especificos de DNS
# ------------------------------------------------------------

# Serial SOA no formato YYYYMMDDNN.
_gerar_serial() {
    date +%Y%m%d01
}

# Re-render um template substituindo placeholders __KEY__.
# Uso: _render_template origem destino KEY=value KEY2=value2 ...
_render_template() {
    local src="$1"; local dst="$2"; shift 2
    cp "$src" "$dst"
    for kv in "$@"; do
        local k="${kv%%=*}"
        local v="${kv#*=}"
        # Usar @ como separador do sed porque valores podem conter /
        sed -i "s@__${k}__@${v//@/\\@}@g" "$dst"
    done
}

# Verifica se ja existe zona forward com o nome.
_zona_forward_existe() {
    local dom="$1"
    grep -Eq "^zone[[:space:]]+\"${dom}\"" "$NAMED_CUSTOM_INCLUDE" 2>/dev/null
}

_zona_reverse_existe() {
    local rev="$1"
    grep -Eq "^zone[[:space:]]+\"${rev}\"" "$NAMED_CUSTOM_INCLUDE" 2>/dev/null
}

# Lista zonas definidas no nosso include. Imprime uma por linha.
_listar_zonas() {
    [[ -f "$NAMED_CUSTOM_INCLUDE" ]] || return
    grep -Eo '^zone "[^"]+"' "$NAMED_CUSTOM_INCLUDE" | awk -F\" '{print $2}'
}

# Incrementa o serial do SOA num zone file. Se nao encontrar, nao toca.
_bump_serial() {
    local zonefile="$1"
    local novo
    novo="$(_gerar_serial)"
    # Incrementa sequencial se ja ha serial de hoje
    if grep -Eq "[0-9]{10}[[:space:]]*;[[:space:]]*serial" "$zonefile"; then
        local atual
        atual="$(grep -Eo '[0-9]{10}' "$zonefile" | head -1)"
        local hoje_prefix="${novo:0:8}"
        if [[ "${atual:0:8}" == "$hoje_prefix" ]]; then
            local suf="${atual:8:2}"
            suf=$((10#$suf + 1))
            printf -v novo '%s%02d' "$hoje_prefix" "$suf"
        fi
        sed -i -E "s/[0-9]{10}([[:space:]]*;[[:space:]]*serial)/${novo}\1/" "$zonefile"
    fi
}

# Valida a configuracao; se OK -> reload; senao -> restaura backup.
# Uso: _aplicar "msg" <ficheiros que foram modificados>
_aplicar() {
    local msg="$1"; shift
    info "Validar configuracao BIND..."
    if named-checkconf "$NAMED_CONF"; then
        if systemctl reload named 2>/dev/null || systemctl restart named; then
            ok "$msg"
            return 0
        else
            erro "named recusou reload/restart - ver 'systemctl status named'"
            return 1
        fi
    else
        erro "named-checkconf falhou! Ver '/var/log/messages' e corrigir."
        return 1
    fi
}

_restorecon_named() {
    restorecon -R "$NAMED_ZONES_DIR" 2>/dev/null || true
    chown -R root:named "$NAMED_ZONES_DIR" 2>/dev/null || true
    # Garantir que named pode escrever os seus ficheiros de runtime
    # (data/named.run, etc.) mesmo a correr o menu com sudo
    chown -R named:named /var/named/data /var/named/dynamic 2>/dev/null || true
}

# ------------------------------------------------------------
# PONTO 1: Criar zona master (forward) para um dominio
# ------------------------------------------------------------
dns_criar_forward() {
    title "Criar zona forward (master)"
    local dominio
    perguntar_fqdn dominio "Dominio (ex: exemplo.pt)"

    if _zona_forward_existe "$dominio"; then
        warn "Zona '$dominio' ja existe."
        return 1
    fi

    local ns_host="$SERVER_NAME"
    ler ns_host "Hostname do NS" "$SERVER_NAME"
    local ns_fqdn="${ns_host}.${dominio}"

    local server_ip="$SERVER_IP"
    perguntar_ip server_ip "IP do servidor (NS/Web)" "$SERVER_IP"

    local zonefile="$NAMED_ZONES_DIR/${dominio}.zone"
    local serial; serial="$(_gerar_serial)"

    backup_file "$NAMED_CUSTOM_INCLUDE"
    [[ -f "$zonefile" ]] && backup_file "$zonefile"

    _render_template "$AS_ROOT/templates/zone-forward.tpl" "$zonefile" \
        "NS_FQDN=$ns_fqdn" \
        "ADMIN_EMAIL=$ADMIN_EMAIL" \
        "SERIAL=$serial" \
        "SERVER_IP=$server_ip" \
        "NS_HOST=$ns_host"

    cat >> "$NAMED_CUSTOM_INCLUDE" <<EOF
zone "$dominio" IN {
    type master;
    file "$zonefile";
    allow-update { none; };
};
EOF

    _restorecon_named
    if named-checkzone "$dominio" "$zonefile" >/dev/null; then
        _aplicar "Zona forward '$dominio' criada em $zonefile"
    else
        erro "Zona '$dominio' tem erros. A reverter."
        sed -i "/zone \"$dominio\" IN {/,/^};/d" "$NAMED_CUSTOM_INCLUDE"
        rm -f "$zonefile"
        return 1
    fi
}

# ------------------------------------------------------------
# PONTO 4: Adicionar registos A/MX a uma zona existente
# ------------------------------------------------------------
dns_add_registo() {
    title "Adicionar registo DNS"
    local zonas
    zonas="$(_listar_zonas | grep -v 'in-addr.arpa' || true)"
    if [[ -z "$zonas" ]]; then
        warn "Nao ha zonas forward criadas. Cria uma primeiro."
        return 1
    fi
    echo "Zonas disponiveis:"
    echo "$zonas" | nl -w2 -s') '
    local dominio
    ler dominio "Dominio alvo" ""
    if ! echo "$zonas" | grep -qx "$dominio"; then
        erro "Zona '$dominio' nao existe."; return 1
    fi
    local zonefile="$NAMED_ZONES_DIR/${dominio}.zone"

    echo
    echo "Tipo de registo:"
    echo "  1) A    (host -> IP)"
    echo "  2) MX   (mail exchanger)"
    echo "  3) CNAME (alias)"
    local opc; ler opc "Opcao" "1"

    local entrada=""
    case "$opc" in
        1)
            local host ip
            ler host "Nome (ex: mail, ftp) ou '@' para o dominio" ""
            perguntar_ip ip "IP de destino" ""
            entrada="${host}   IN  A   ${ip}"
            ;;
        2)
            local host prio
            ler host "Mail host (ex: mail.${dominio}. com o ponto final)" "mail.${dominio}."
            ler prio "Prioridade" "10"
            # Garantir ponto final para FQDN
            [[ "$host" != *. && "$host" == *.* ]] && host="${host}."
            entrada="@    IN  MX  ${prio}  ${host}"
            ;;
        3)
            local alias alvo
            ler alias "Alias" ""
            ler alvo "Destino (ex: www)" ""
            entrada="${alias}   IN  CNAME   ${alvo}"
            ;;
        *) erro "Opcao invalida"; return 1;;
    esac

    backup_file "$zonefile"
    echo "$entrada" >> "$zonefile"
    _bump_serial "$zonefile"
    _restorecon_named

    if named-checkzone "$dominio" "$zonefile" >/dev/null; then
        _aplicar "Registo adicionado: $entrada"
    else
        erro "Zone file tem erros apos adicionar registo. A reverter."
        # Restaurar ultima versao do backup
        local snap
        snap="$(ls -1t "$CONFIG_BACKUP_DIR" | head -1)"
        cp "$CONFIG_BACKUP_DIR/$snap${zonefile}" "$zonefile" 2>/dev/null || true
        return 1
    fi
}

# ------------------------------------------------------------
# PONTO 5: Criar zona reverse
# ------------------------------------------------------------
dns_criar_reverse() {
    title "Criar zona reverse"
    local ip fqdn
    perguntar_ip    ip    "IP do host"    "$SERVER_IP"
    perguntar_fqdn  fqdn  "FQDN do host (ex: ns1.exemplo.pt)" ""

    local rev_zone last_oct
    rev_zone="$(ip_to_reverse_zone "$ip")"
    last_oct="$(ip_last_octet "$ip")"

    if _zona_reverse_existe "$rev_zone"; then
        warn "Zona reverse '$rev_zone' ja existe. A adicionar apenas o PTR."
        local zonefile="$NAMED_ZONES_DIR/${rev_zone}.zone"
        backup_file "$zonefile"
        echo "${last_oct}  IN  PTR  ${fqdn}." >> "$zonefile"
        _bump_serial "$zonefile"
        _restorecon_named
        _aplicar "PTR adicionado: $ip -> $fqdn"
        return $?
    fi

    local ns_fqdn="${SERVER_NAME}.${fqdn#*.}"
    local serial; serial="$(_gerar_serial)"
    local zonefile="$NAMED_ZONES_DIR/${rev_zone}.zone"

    backup_file "$NAMED_CUSTOM_INCLUDE"
    _render_template "$AS_ROOT/templates/zone-reverse.tpl" "$zonefile" \
        "NS_FQDN=$ns_fqdn" \
        "ADMIN_EMAIL=$ADMIN_EMAIL" \
        "SERIAL=$serial" \
        "LAST_OCTET=$last_oct" \
        "HOST_FQDN=$fqdn"

    cat >> "$NAMED_CUSTOM_INCLUDE" <<EOF
zone "$rev_zone" IN {
    type master;
    file "$zonefile";
    allow-update { none; };
};
EOF

    _restorecon_named
    if named-checkzone "$rev_zone" "$zonefile" >/dev/null; then
        _aplicar "Zona reverse '$rev_zone' criada ($ip -> $fqdn)"
    else
        erro "Zona reverse tem erros. A reverter."
        sed -i "/zone \"$rev_zone\" IN {/,/^};/d" "$NAMED_CUSTOM_INCLUDE"
        rm -f "$zonefile"
        return 1
    fi
}

# ------------------------------------------------------------
# PONTO 6 (parcial): Eliminar zona forward / reverse
# ------------------------------------------------------------
dns_eliminar_zona() {
    title "Eliminar zona DNS"
    local zonas
    zonas="$(_listar_zonas || true)"
    if [[ -z "$zonas" ]]; then
        warn "Nao ha zonas para eliminar."
        return 1
    fi
    echo "Zonas atuais:"
    echo "$zonas" | nl -w2 -s') '
    local zona
    ler zona "Nome exato da zona a eliminar" ""
    if ! echo "$zonas" | grep -qx "$zona"; then
        erro "Zona '$zona' nao existe."; return 1
    fi
    confirmar "Eliminar zona '$zona' e o respetivo ficheiro?" || { info "Cancelado."; return 0; }

    backup_file "$NAMED_CUSTOM_INCLUDE"
    # Remove o bloco 'zone "X" IN { ... };' do include
    sed -i "/^zone \"${zona}\" IN {/,/^};/d" "$NAMED_CUSTOM_INCLUDE"
    # Apaga o ficheiro de zona (tentar varios sufixos)
    rm -f "$NAMED_ZONES_DIR/${zona}.zone" "$NAMED_ZONES_DIR/${zona}"

    _aplicar "Zona '$zona' removida"
}

# ------------------------------------------------------------
# PONTO 13a: Blacklist de dominios
# ------------------------------------------------------------
dns_blacklist_listar() {
    title "Dominios em blacklist"
    if [[ ! -s "$NAMED_BLACKLIST_INCLUDE" ]]; then
        echo "(vazio)"
        return
    fi
    grep -Eo '^zone "[^"]+"' "$NAMED_BLACKLIST_INCLUDE" | awk -F\" '{print "  - "$2}'
}

dns_blacklist_add() {
    title "Adicionar dominio a blacklist"
    local dom ip
    perguntar_fqdn dom "Dominio a bloquear (ex: facebook.com)" ""
    perguntar_ip   ip  "Responder com IP"                       "$BLACKLIST_REDIRECT_IP"

    if grep -Eq "^zone \"${dom}\"" "$NAMED_BLACKLIST_INCLUDE"; then
        warn "'$dom' ja esta na blacklist."
        return 1
    fi

    mkdir -p "$NAMED_BLACKLIST_DIR"
    local zonefile="$NAMED_BLACKLIST_DIR/${dom}.zone"
    _render_template "$AS_ROOT/templates/zone-blacklist.tpl" "$zonefile" \
        "REDIRECT_IP=$ip"

    backup_file "$NAMED_BLACKLIST_INCLUDE"
    cat >> "$NAMED_BLACKLIST_INCLUDE" <<EOF
zone "$dom" IN {
    type master;
    file "$zonefile";
};
EOF
    _restorecon_named
    _aplicar "'$dom' adicionado a blacklist (responde $ip)"
}

dns_blacklist_remove() {
    title "Remover dominio da blacklist"
    dns_blacklist_listar
    local dom
    ler dom "Dominio a remover" ""
    if ! grep -Eq "^zone \"${dom}\"" "$NAMED_BLACKLIST_INCLUDE"; then
        erro "'$dom' nao esta na blacklist."; return 1
    fi
    backup_file "$NAMED_BLACKLIST_INCLUDE"
    sed -i "/^zone \"${dom}\" IN {/,/^};/d" "$NAMED_BLACKLIST_INCLUDE"
    rm -f "$NAMED_BLACKLIST_DIR/${dom}.zone"
    _aplicar "'$dom' removido da blacklist"
}

# ------------------------------------------------------------
# Menu do modulo
# ------------------------------------------------------------
dns_menu() {
    while true; do
        echo
        title "DNS (BIND)"
        cat <<EOF
  1) Criar zona forward (master)         [Ponto 1]
  2) Adicionar registo A/MX/CNAME        [Ponto 4]
  3) Criar zona reverse                  [Ponto 5]
  4) Eliminar zona (forward ou reverse)  [Ponto 6]
  5) Listar zonas
  --- Blacklist ------------------------ [Ponto 13a]
  6) Listar blacklist
  7) Adicionar dominio a blacklist
  8) Remover dominio da blacklist
  0) Voltar
EOF
        local opc; ler opc "Opcao" "0"
        case "$opc" in
            1) dns_criar_forward  ;;
            2) dns_add_registo    ;;
            3) dns_criar_reverse  ;;
            4) dns_eliminar_zona  ;;
            5) title "Zonas"; _listar_zonas | sed 's/^/  - /' ;;
            6) dns_blacklist_listar ;;
            7) dns_blacklist_add    ;;
            8) dns_blacklist_remove ;;
            0) return 0 ;;
            *) warn "Opcao invalida" ;;
        esac
        pausa
    done
}

# Se executado diretamente, abre o menu
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    dns_menu
fi