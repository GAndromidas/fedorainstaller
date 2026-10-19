#!/usr/bin/env bash
# Integration test harness for fedorainstaller — static phase only.
# (archinstaller's harness additionally has an opt-in VM phase; the fedora
# fork keeps a static gate for now: syntax smoke, the SSH hardening unit
# tests, and shellcheck gated on errors only.)
#
# Usage: bash tests/integration.sh

set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }
skip() { echo "SKIP: $1"; }

phase() { echo ""; echo "=== $1 ==="; }

phase "Phase 1 — static checks"

if bash "$ROOT_DIR/tests/syntax.sh"; then
  pass "syntax smoke test"
else
  fail "syntax smoke test"
fi

if bash "$ROOT_DIR/tests/unit_ssh.sh"; then
  pass "ssh hardening unit tests"
else
  fail "ssh hardening unit tests"
fi

if command -v shellcheck &>/dev/null; then
  if shellcheck --severity=error "$ROOT_DIR/install.sh" "$ROOT_DIR"/scripts/common.sh \
    "$ROOT_DIR"/scripts/verify.sh "$ROOT_DIR"/scripts/lib/*.sh \
    "$ROOT_DIR"/scripts/modules/*.sh "$ROOT_DIR"/tests/*.sh; then
    pass "shellcheck (error severity)"
  else
    fail "shellcheck (error severity)"
  fi
else
  skip "shellcheck not installed — error-severity gate not run"
fi

echo ""
echo "integration: $PASS passed, $FAIL failed"
exit "$([ "$FAIL" -eq 0 ] && echo 0 || echo 1)"
