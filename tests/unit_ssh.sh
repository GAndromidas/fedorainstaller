#!/usr/bin/env bash
# Hermetic unit tests for the SSH Include-repair logic in
# scripts/modules/system_services.sh (harden_sshd_restore_include), ported
# from archinstaller's tests/unit_ssh.sh after the fedorainstaller SSH
# hardening step was added (it did not exist before).
#
# Regression incentive from the arch parent: that branch was once inverted,
# causing (a) a false warning + pointless rewrite on every CLEAN rerun, and
# (b) a false "already repaired" no-op on genuinely DIRTY configs. These
# tests pin all four outcomes before the first VM rerun of the new step.
#
# Needs no root: sudo is stubbed to run the same tools unprivileged, and
# the main sshd_config path is redirected into the fixture directory via
# SSHD_MAIN_CONFIG. Module top-level execution is bypassed by extracting
# only the SSH function block.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FX="$(mktemp -d /tmp/opencode/unit_ssh.XXXXXX)"
trap 'rm -rf "$FX"' EXIT
export INSTALL_LOG="$FX/test.log"
export SSHD_MAIN_CONFIG="$FX/sshd_config"
PASS=0; FAIL=0
assert_contains() {
  local name="${1:-}" hay="${2:-}" needle="${3:-}"
  if [[ "$hay" == *"$needle"* ]]; then PASS=$((PASS+1)); echo "PASS: $name";
  else FAIL=$((FAIL+1)); echo "FAIL: $name — '$needle' not in: ${hay:0:200}"; fi
}
assert_eq() {
  local name="${1:-}" got="${2:-}" want="${3:-}"
  if [[ "$got" == "$want" ]]; then PASS=$((PASS+1)); echo "PASS: $name";
  else FAIL=$((FAIL+1)); echo "FAIL: $name — got '$got', want '$want'"; fi
}

# --- sudo shim: drop -n, run the real tool unprivileged (fixtures are ours) ---
SSHD_T_RC="${SSHD_T_RC:-0}"
sudo() {
  [[ "${1:-}" == "-n" ]] && shift
  case "${1:-}" in
    grep) command grep "${@:2}" ;;
    awk)  command awk "${@:2}" ;;
    cp)   command cp "${@:2}" ;;
    sshd) [[ "${2:-}" == "-t" ]] && return "$SSHD_T_RC" || command sshd "${@:2}" ;;
    *) command "$@" ;;
  esac
}
export -f sudo

# --- extract ONLY the ssh function block (system_services.sh has top-level
# code that would execute — installs, systemctl — if sourced whole) ---
python3 - "$ROOT_DIR/scripts/modules/system_services.sh" > "$FX/ssh_fns.sh" <<'PYEOF'
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
names = ['sshd_hardened_enough', '_sshd_file_level_hardened',
         'harden_sshd_restore_include', 'harden_sshd']
for name in names:
    m = re.search(rf'(?ms)^{name}\(\) \{{.*?^\}}\n', src)
    assert m, name
    sys.stdout.write(m.group(0))
PYEOF
if ! grep -q 'harden_sshd() {' "$FX/ssh_fns.sh"; then
  echo "unit-ssh: could not extract SSH function block — module layout changed"; exit 1
fi

# Dependencies from core/lib that the extracted block calls
export INSTALL_LOG="$FX/test.log"
log_to_file() { echo "$1" >> "$INSTALL_LOG" 2>/dev/null || true; }
ui_info()    { echo "INFO: $*"; }
ui_warn()    { echo "WARN: $*"; }
ui_success() { echo "SUCCESS: $*"; }
ui_error()   { echo "ERROR: $*"; }
step()       { :; }

# shellcheck disable=SC1090
source "$FX/ssh_fns.sh"

# --- fixtures ---
cat > "$FX/clean.conf" <<EOF
# Added by fedorainstaller — enables sshd_config.d drop-ins (managed)
Include /etc/ssh/sshd_config.d/*.conf
PasswordAuthentication yes
EOF
cat > "$FX/dirty.conf" <<EOF
PermitRootLogin yes
# Added by fedorainstaller — enables sshd_config.d drop-ins (managed)
Include /etc/ssh/sshd_config.d/*.conf
PasswordAuthentication yes
EOF
cat > "$FX/noinclude.conf" <<EOF
# Managed by fedorainstaller test
PasswordAuthentication yes
EOF

# 1. CLEAN: Include already first → info, no rewrite, no backup
cp "$FX/clean.conf" "$SSHD_MAIN_CONFIG"
out=$(harden_sshd_restore_include 2>&1)
rc=$?
assert_contains "clean-info" "$out" "already present and first"
assert_eq "clean-rc" "$rc" "0"
assert_eq "clean-no-backups" "$(ls "$FX"/sshd_config.backup.* 2>/dev/null | wc -l)" "0"
assert_eq "clean-untouched" "$(head -1 "$SSHD_MAIN_CONFIG" | cut -c1-4)" "# Ad"

# 2. DIRTY: managed key above Include → warning + repair + backup
cp "$FX/dirty.conf" "$SSHD_MAIN_CONFIG"
out=$(harden_sshd_restore_include 2>&1)
rc=$?
assert_contains "dirty-warning" "$out" "Managed SSH setting precedes Include"
assert_contains "dirty-forensics" "$(cat "$INSTALL_LOG" 2>/dev/null)" "Managed keys above Include"
assert_contains "dirty-success" "$out" "Include in $SSHD_MAIN_CONFIG fixed"
assert_eq "dirty-rc" "$rc" "0"
assert_eq "dirty-repair" "$(grep -c '^Include /etc/ssh/sshd_config.d' "$SSHD_MAIN_CONFIG")" "1"
# The managed key must now be BELOW the Include (first-obtained goes to the
# drop-in); its exact line number depends on where we spliced it.
_prl_line=$(sudo awk '$1=="PermitRootLogin" {print NR}' "$SSHD_MAIN_CONFIG")
_prl_line=${_prl_line%%[^0-9]*}; [[ -n "$_prl_line" ]] || _prl_line=0
_inc_line=$(sudo awk '$1=="Include" {print NR}' "$SSHD_MAIN_CONFIG")
_inc_line=${_inc_line%%[^0-9]*}; [[ -n "$_inc_line" ]] || _inc_line=0
(( _prl_line > _inc_line )); assert_eq "dirty-key-below-include" "$?" "0"
assert_contains "dirty-backup" "$(ls "$FX"/sshd_config.backup.* 2>/dev/null)" "sshd_config.backup."

# 3. NO INCLUDE: managed keys only in main → warning + Include added at top
cp "$FX/noinclude.conf" "$SSHD_MAIN_CONFIG"
out=$(harden_sshd_restore_include 2>&1)
assert_contains "noinclude-warning" "$out" "No Include for sshd_config.d"
assert_contains "noinclude-added" "$(head -2 "$SSHD_MAIN_CONFIG" | tail -1)" "Include /etc/ssh/sshd_config.d"

# 4. VALIDATION FAILURE: sshd -t fails after edit → rollback, rc 1
cp "$FX/dirty.conf" "$SSHD_MAIN_CONFIG"
SSHD_T_RC=3 out=$(harden_sshd_restore_include 2>&1)
rc=$?
assert_contains "rollback-warning" "$out" "rolling back"
assert_eq "rollback-rc" "$rc" "1"
assert_eq "rollback-restore" "$(head -1 "$SSHD_MAIN_CONFIG")" "PermitRootLogin yes"

echo ""; echo "unit-ssh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
