#!/usr/bin/env bash
# ============================================================
# lib/common.sh - Funcoes e variaveis partilhadas
# ============================================================
# Carregar com: source "$(dirname "$0")/lib/common.sh"
# (ou caminho absoluto)
# ============================================================

# --- Localizar a raiz do projeto -----------------------------
# Resolve o diretorio raiz do projeto (um nivel acima de lib/).
if [[ -z "${AS_ROOT:-}" ]]; then
    AS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    export AS_ROOT
fi

# --- Carregar defaults --------------------------------------
if [[ -f "$AS_ROOT/config/defaults.conf" ]]; then
    # shellcheck disable=SC1091
    source "$AS_ROOT/config/defaults.conf"
else
    echo "ERRO: config/defaults.conf nao encontrado em $AS_ROOT" >&2
    return 1 2>/dev/null || exit 1
fi

# --- Cores (desligadas se nao houver TTY) -------------------
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
else
    C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

# --- Logging ------------------------------------------------
_ensure_log() {
    if [[ ! -f "$LOG_FILE" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        touch "$LOG_FILE" 2>/dev/null || true
    fi
}

log() {
    # log <nivel> <mensagem...>
    local nivel="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    _ensure_log
    printf '%s [%s] %s\n' "$ts" "$nivel" "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

info()  { printf '%s[INFO]%s %s\n'  "$C_CYAN"   "$C_RESET" "$*"; log INFO  "$*"; }
ok()    { printf '%s[ OK ]%s %s\n'  "$C_GREEN"  "$C_RESET" "$*"; log OK    "$*"; }
warn()  { printf '%s[WARN]%s %s\n'  "$C_YELLOW" "$C_RESET" "$*"; log WARN  "$*"; }
erro()  { printf '%s[ERRO]%s %s\n'  "$C_RED"    "$C_RESET" "$*" >&2; log ERRO  "$*"; }
title() { printf '\n%s== %s ==%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }

# --- Verificacoes -------------------------------------------
require_root() {
    if [[ $EUID -ne 0 ]]; then
        erro "Este script tem de ser executado como root (usa sudo)."
        exit 1
    fi
}

comando_existe() { command -v "$1" >/dev/null 2>&1; }

# --- Prompts seguros ----------------------------------------
# ler <var> <prompt> [default]
ler() {
    local __var="$1"; local __prompt="$2"; local __default="${3:-}"
    local __input
    if [[ -n "$__default" ]]; then
        read -r -p "$__prompt [$__default]: " __input
        __input="${__input:-$__default}"
    else
        read -r -p "$__prompt: " __input
    fi
    printf -v "$__var" '%s' "$__input"
}

# confirmar "mensagem" -> 0 (yes) ou 1 (no). Default = no.
confirmar() {
    local resp
    read -r -p "$1 [s/N]: " resp
    [[ "$resp" =~ ^[sSyY]$ ]]
}

pausa() {
    read -r -p "Pressiona Enter para continuar..." _
}

# --- Carregar helpers adicionais ----------------------------
# shellcheck disable=SC1091
source "$AS_ROOT/lib/validate.sh"
# shellcheck disable=SC1091
source "$AS_ROOT/lib/backup.sh"
