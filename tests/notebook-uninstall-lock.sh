#!/usr/bin/env bash
set -euo pipefail
REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
. "$REPO_DIR/scripts/lib/operation-lock.sh"
WORK_DIR=$(mktemp -d)
trap 'rm -rf -- "$WORK_DIR"' EXIT
export CLASHCTL_HOME="$WORK_DIR/home" CLASHCTL_INSTALL_MODE=notebook
mkdir -m 700 "$CLASHCTL_HOME"
printf 'payload\n' >"$CLASHCTL_HOME/payload"
operation_lock_acquire
export TEST_REAL_RM TEST_REPO_DIR="$REPO_DIR" TEST_PROBE_LOG="$WORK_DIR/probe"
TEST_REAL_RM=$(command -v rm)
mkdir "$WORK_DIR/bin"
cat >"$WORK_DIR/bin/rm" <<'STUB'
#!/usr/bin/env bash
set -eu
"$TEST_REAL_RM" "$@"
case " $* " in
*'/.clashctl-tmp '*|*'/payload '*)
    if bash -c '. "$1/scripts/lib/operation-lock.sh"; operation_lock_acquire' _ "$TEST_REPO_DIR" 2>/dev/null; then
        echo 'FAIL: acquired lock during uninstall' >&2; exit 1
    fi
    echo checked >>"$TEST_PROBE_LOG" ;;
esac
STUB
chmod +x "$WORK_DIR/bin/rm"
PATH="$WORK_DIR/bin:$PATH" operation_lock_remove_notebook_home
[ ! -e "$CLASHCTL_HOME" ] || { echo 'FAIL: installation remains'; exit 1; }
[ "$(wc -l <"$TEST_PROBE_LOG")" -ge 2 ] || { echo 'FAIL: removal race not tested'; exit 1; }
printf 'notebook-uninstall-lock: ok\n'
