#!/usr/bin/env bash
# python_prep.sh — Secure Python Virtual Environment Setup
# ─────────────────────────────────────────────────────────────────
# Creates a venv, installs system dependencies (libmagic1), compiles
# a hash-pinned requirements.txt via pip-compile, installs all
# packages with strict security flags, and runs pip-audit.
#
# Idempotent — safe to re-run on an existing venv.
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"
REQ_IN="$SCRIPT_DIR/requirements.in"
REQ_FILE="$SCRIPT_DIR/requirements.txt"
CA_CERT="/etc/ssl/certs/ca-certificates.crt"
PIP_LOG="$SCRIPT_DIR/pip-secure.log"

# ── Colours ───────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; GOLD='\033[0;33m'; RED='\033[0;31m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

ok()      { printf "${GREEN}[✔]${NC} %s\n" "$1"; }
info()    { printf "${CYAN}[*]${NC} %s\n" "$1"; }
warn()    { printf "${GOLD}[!]${NC} %s\n" "$1"; }
die()     { printf "${RED}[✘] ERROR: %s${NC}\n" "$1" >&2; exit 1; }
section() { printf "\n${BOLD}${CYAN}━━━ %s ━━━${NC}\n\n" "$1"; }

# ── Banner ────────────────────────────────────────────────────────
clear
printf "${BOLD}${CYAN}"
cat <<'BANNER'
  ╔══════════════════════════════════════════════════════════╗
  ║     ORP ENGINE — Python Environment Setup               ║
  ╚══════════════════════════════════════════════════════════╝
BANNER
printf "${NC}\n"

# ── 1. Python version check ───────────────────────────────────────
section "1. Python"

command -v python3 >/dev/null 2>&1 || die "python3 not found. Install with: sudo apt-get install python3"

PYTHON_VERSION="$(python3 --version 2>&1 | awk '{print $2}')"
PY_MAJOR="$(echo "$PYTHON_VERSION" | cut -d. -f1)"
PY_MINOR="$(echo "$PYTHON_VERSION" | cut -d. -f2)"

if [ "$PY_MAJOR" -lt 3 ] || ([ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 10 ]); then
    die "Python 3.10+ required. Found: $PYTHON_VERSION"
fi
ok "Python $PYTHON_VERSION"

if ! python3 -m venv --help >/dev/null 2>&1; then
    die "python3-venv not installed. Install with: sudo apt-get install python3-venv"
fi
ok "venv module available"

# ── 2. System dependencies ────────────────────────────────────────
# python-magic requires libmagic1 at the OS level. Without it,
# `import magic` raises: ImportError: failed to find libmagic
section "2. System Dependencies"

SYSTEM_PKGS=()
dpkg -l libmagic1 >/dev/null 2>&1 || SYSTEM_PKGS+=("libmagic1")

if [ ${#SYSTEM_PKGS[@]} -gt 0 ]; then
    info "Installing missing system packages: ${SYSTEM_PKGS[*]}"
    apk update -qq
    apk install -y "${SYSTEM_PKGS[@]}"
    ok "System packages installed: ${SYSTEM_PKGS[*]}"
else
    ok "All system dependencies present (libmagic1 ✔)."
fi

[ -f "$CA_CERT" ] || die "CA certificate bundle not found: $CA_CERT"
ok "CA certificate bundle found."

# ── 3. requirements.in pre-flight ────────────────────────────────
section "3. Requirements"

[ -f "$REQ_IN" ] || die "requirements.in not found at $REQ_IN"
ok "requirements.in found."

# ── 4. Virtual environment ────────────────────────────────────────
section "4. Virtual Environment"

if [ -d "$VENV_DIR" ]; then
    warn "Virtual environment already exists at $VENV_DIR"
else
    info "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
    ok "Virtual environment created."
fi

# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

info "Upgrading pip, setuptools, wheel..."
python3 -m pip install --quiet --upgrade pip setuptools wheel
ok "pip, setuptools, wheel upgraded."

# ── 5. Ensure bootstrap pins are in requirements.in ───────────────
# Pre-seed pip/setuptools/wheel pins so requirements.in is fully
# self-contained in git and pip-compile produces stable output.
section "5. Bootstrap Pin Check"

MISSING_PINS=()
for PKG in pip setuptools wheel; do
    grep -Eiq "^${PKG}==" "$REQ_IN" || MISSING_PINS+=("$PKG")
done

if [ ${#MISSING_PINS[@]} -gt 0 ]; then
    info "Auto-pinning in requirements.in: ${MISSING_PINS[*]}"

    PIP_VER="$(python3 -m pip --version | awk '{print $2}')"
    read -r SETUPTOOLS_VER WHEEL_VER < <(python3 - <<'PY'
import setuptools, wheel
print(setuptools.__version__, wheel.__version__)
PY
)
    TMP="$(mktemp)"
    cp "$REQ_IN" "$TMP"

    {
        printf '\n# ── Bootstrap (auto-pinned by python_prep.sh) ──────────────────\n'
        for PKG in "${MISSING_PINS[@]}"; do
            case "$PKG" in
                pip)        printf 'pip==%s\n'        "$PIP_VER" ;;
                setuptools) printf 'setuptools==%s\n' "$SETUPTOOLS_VER" ;;
                wheel)      printf 'wheel==%s\n'      "$WHEEL_VER" ;;
            esac
        done
    } >> "$TMP"

    mv "$TMP" "$REQ_IN"
    ok "Pins added to requirements.in: ${MISSING_PINS[*]}"
else
    ok "Bootstrap pins already present in requirements.in."
fi

# ── 6. Install pip-tools ─────────────────────────────────────────
section "6. pip-tools"

info "Installing pip-tools..."
python3 -m pip install --quiet --upgrade pip-tools
ok "pip-tools installed."

# ── 7. Compile locked requirements.txt ───────────────────────────
# FIXED: pip-compile is called exactly ONCE using the venv binary.
# The previous version called it twice (once via venv binary, once
# via python3 -m piptools.scripts.compile), silently overwriting
# the first output. The module entrypoint is not a supported API.
section "7. Compiling requirements.txt"

info "Running pip-compile --generate-hashes..."
"$VENV_DIR/bin/pip-compile" \
    --generate-hashes \
    --quiet \
    "$REQ_IN" \
    --output-file "$REQ_FILE"

[ -s "$REQ_FILE" ] || die "requirements.txt was not created at $REQ_FILE"
ok "requirements.txt compiled with hashes."

# ── 8. Secure installation ────────────────────────────────────────
section "8. Installing Dependencies"

info "Installing packages with strict security flags..."
pip install \
    --require-virtualenv \
    --isolated \
    --no-cache-dir \
    --require-hashes \
    -r "$REQ_FILE" \
    --cert "$CA_CERT" \
    --retries 3 \
    --timeout 10 \
    --no-input \
    --log "$PIP_LOG"

ok "Dependencies installed."

# ── 9. pip-audit ──────────────────────────────────────────────────
section "9. Security Audit"

if python3 -m pip_audit --progress-spinner off 2>/dev/null; then
    ok "pip-audit passed — no known vulnerabilities."
else
    warn "pip-audit found issues. Run 'pip-audit' to inspect."
    warn "Check $PIP_LOG for details."
fi

# ── 10. Lock snapshot ─────────────────────────────────────────────
section "10. Lockfile"

python3 -m pip freeze > "$SCRIPT_DIR/requirements.lock"
ok "requirements.lock written."

# ── Summary ───────────────────────────────────────────────────────
printf "\n${BOLD}${CYAN}━━━ Python Environment Ready ━━━${NC}\n\n"
printf "  ${BOLD}%-20s${NC} %s\n" "Python:" "$PYTHON_VERSION"
printf "  ${BOLD}%-20s${NC} %s\n" "Venv:" "$VENV_DIR"
printf "  ${BOLD}%-20s${NC} %s\n" "Lockfile:" "requirements.lock"
printf "  ${BOLD}%-20s${NC} %s\n" "Pip log:" "$PIP_LOG"
printf "\n"
ok "Setup complete."
