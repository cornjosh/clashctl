#!/usr/bin/env bash
set -euo pipefail
REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
. "$REPO_DIR/scripts/lib/operation-lock.sh"
WORK_DIR=$(mktemp -d)
trap 'rm -rf -- "$WORK_DIR"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
export CLASHCTL_HOME="$WORK_DIR/home" CLASHCTL_INSTALL_MODE=notebook
mkdir -m 700 "$CLASHCTL_HOME"
# /tmp can be unsafe/unavailable; notebook locks must never use it.
_operation_lock_validate_tmp() { fail 'notebook consulted global /tmp'; }
operation_lock_acquire || fail 'notebook lock failed'
case $CLASHCTL_OPERATION_LOCK_DIR in "$CLASHCTL_HOME/.clashctl-tmp/"*) ;; *) fail 'lock escaped installation' ;; esac
if bash -c '. "$1/scripts/lib/operation-lock.sh"; operation_lock_acquire' _ "$REPO_DIR" 2>/dev/null; then
    fail 'concurrent installation acquired the same lock'
fi
operation_lock_release
[ ! -e "$CLASHCTL_HOME/.clashctl-tmp/clashctl-operation-$EUID/operation.lock.d" ] || fail 'lock leaked'
chmod 777 "$CLASHCTL_HOME/.clashctl-tmp"
if operation_lock_acquire 2>/dev/null; then fail 'unsafe runtime accepted'; fi
chmod 700 "$CLASHCTL_HOME/.clashctl-tmp"
rm -rf "$CLASHCTL_HOME/.clashctl-tmp"
ln -s "$WORK_DIR" "$CLASHCTL_HOME/.clashctl-tmp"
if operation_lock_acquire 2>/dev/null; then fail 'symlink runtime accepted'; fi
printf 'notebook-runtime: ok\n'
