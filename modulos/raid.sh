#!/usr/bin/env bash
# ============================================================
# modulos/raid.sh - RAID 5 com mdadm (Ponto 10)
# ============================================================
# Pre-requisito: adicionar pelo menos 3 discos virtuais no
# VirtualBox (5GB cada). Sem discos a mais nao ha RAID 5.
#
# Operacoes:
#   - Listar discos disponiveis (sem particoes, sem mount)
#   - Criar RAID 5 /dev/md0 com pelo menos 3 discos
#   - Formatar ext4 e montar em diretoria a escolher
#   - Persistir em /etc/fstab + /etc/mdadm.conf
#   - Ver estado do RAID
#   - Destruir RAID (com confirmacao dupla)
# ============================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

MD_DEV="/dev/md0"

# Listar discos "livres" - sem particoes, nao montados, nao no
# sistema (nao raiz).
raid_listar_discos() {
    title "Discos candidatos para RAID"
    # Todos os discos block tipo 'disk' (exclui particoes e cdrom)
    echo
    lsblk -ndo NAME,SIZE,TYPE,MOUNTPOINT,PKNAME 2>/dev/null | awk '$3 == "disk" {print "  - /dev/"$1, $2, ($4 ? "MONTADO: "$4 : "livre")}'
    echo
    echo "(Discos livres sao os que nao aparecem montados nem como pai de particoes ativas.)"
}

raid_criar() {
    title "Criar RAID 5"
    raid_listar_discos
    echo
    info "Exemplo de input: /dev/sdb /dev/sdc /dev/sdd"
    local discos; ler discos "Discos a usar (separados por espaco)" ""
    # shellcheck disable=SC2206
    local arr=($discos)
    if [[ ${#arr[@]} -lt 3 ]]; then
        erro "RAID 5 precisa de pelo menos 3 discos."
        return 1
    fi
    for d in "${arr[@]}"; do
        [[ -b "$d" ]] || { erro "'$d' nao e um dispositivo de bloco."; return 1; }
    done

    local mnt
    ler mnt "Ponto de montagem (diretoria)" "/mnt/raid5"
    mkdir -p "$mnt"

    warn "ATENCAO: Vai destruir QUALQUER DADO nos discos ${arr[*]}."
    confirmar "Confirmar?" || return 0
    confirmar "Tens a certeza absoluta? Isto e irreversivel." || return 0

    # Zerar superblocks anteriores (por seguranca)
    for d in "${arr[@]}"; do
        mdadm --zero-superblock --force "$d" 2>/dev/null || true
    done

    info "A criar RAID 5 em $MD_DEV..."
    echo y | mdadm --create --verbose "$MD_DEV" --level=5 \
        --raid-devices="${#arr[@]}" "${arr[@]}" || {
        erro "mdadm --create falhou."
        return 1
    }

    info "Sincronizacao inicial em progresso (pode demorar). Estado:"
    mdadm --detail "$MD_DEV" | head -20

    info "A formatar ext4..."
    mkfs.ext4 -F "$MD_DEV" || { erro "mkfs.ext4 falhou"; return 1; }

    mount "$MD_DEV" "$mnt" || { erro "mount falhou"; return 1; }

    # Persistir em fstab (por UUID, mais robusto)
    local uuid
    uuid="$(blkid -s UUID -o value "$MD_DEV")"
    backup_file /etc/fstab
    if ! grep -q "$uuid" /etc/fstab; then
        echo "UUID=$uuid  $mnt  ext4  defaults  0 0" >> /etc/fstab
    fi

    # Persistir config mdadm
    backup_file /etc/mdadm.conf 2>/dev/null || true
    mdadm --detail --scan >> /etc/mdadm.conf
    # Regenerar initramfs (AlmaLinux 8 usa dracut)
    dracut --force 2>/dev/null || true

    ok "RAID 5 criado, montado em $mnt e persistido."
    df -h "$mnt"
}

raid_estado() {
    title "Estado RAID"
    if [[ ! -b "$MD_DEV" ]]; then
        warn "$MD_DEV nao existe."
        cat /proc/mdstat 2>/dev/null | head -20
        return
    fi
    mdadm --detail "$MD_DEV"
    echo
    cat /proc/mdstat
}

raid_destruir() {
    title "Destruir RAID"
    if [[ ! -b "$MD_DEV" ]]; then
        warn "$MD_DEV nao existe. Nada a fazer."
        return
    fi
    warn "Vai destruir $MD_DEV (perde todos os dados)."
    confirmar "Confirmar?" || return 0
    # Obter os membros ANTES de parar
    local membros
    membros=$(mdadm --detail "$MD_DEV" 2>/dev/null | awk '/active sync/ {print $NF}')

    # Desmontar
    local mnt
    mnt=$(findmnt -no TARGET "$MD_DEV" 2>/dev/null)
    [[ -n "$mnt" ]] && umount "$mnt"

    mdadm --stop "$MD_DEV"
    for d in $membros; do
        mdadm --zero-superblock "$d" 2>/dev/null || true
    done
    backup_file /etc/fstab
    sed -i "\|$MD_DEV\|d" /etc/fstab
    [[ -n "$mnt" ]] && sed -i "\|$mnt|d" /etc/fstab
    ok "RAID destruido."
}

raid_menu() {
    while true; do
        echo
        title "RAID 5 (Ponto 10)"
        cat <<EOF
  1) Listar discos disponiveis
  2) Criar RAID 5
  3) Estado do RAID
  4) Destruir RAID (cuidado!)
  0) Voltar
EOF
        local opc; ler opc "Opcao" "0"
        case "$opc" in
            1) raid_listar_discos ;;
            2) raid_criar ;;
            3) raid_estado ;;
            4) raid_destruir ;;
            0) return 0 ;;
            *) warn "Opcao invalida" ;;
        esac
        pausa
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    raid_menu
fi
