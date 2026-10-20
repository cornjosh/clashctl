#!/usr/bin/env bash
# 实际安装到当前目录、恢复 Shell、更新和卸载；仅组件下载使用本地测试二进制。
set -euo pipefail
REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
WORK_DIR=$(mktemp -d)
TEST_YQ=${TEST_YQ:-$(command -v yq || true)}
TEST_MIHOMO=${TEST_MIHOMO:-}
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
[ -x "$TEST_YQ" ] && [ -x "$TEST_MIHOMO" ] || fail 'set TEST_YQ and TEST_MIHOMO to local test binaries'
cleanup() {
    if [ -f "$WORK_DIR/source/.clashctl/init.sh" ]; then
        bash -c 'source "$1" --commands-only && clashctl stop' _ "$WORK_DIR/source/.clashctl/init.sh" >/dev/null 2>&1 || true
    fi
    if [ -f "$WORK_DIR/custom/init.sh" ]; then
        bash -c 'source "$1" --commands-only && clashctl stop' _ "$WORK_DIR/custom/init.sh" >/dev/null 2>&1 || true
    fi
    rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT
export TEST_YQ TEST_MIHOMO CI=1 CLASHCTL_COLOR=never
export HOME="$WORK_DIR/user"
unset CLASHCTL_HOME CLASHCTL_INSTALL_MODE
mkdir -p "$HOME" "$WORK_DIR/source"
printf '# original bashrc\n' >"$HOME/.bashrc"
tar -C "$REPO_DIR" --exclude=.git --exclude=.env --exclude=bin --exclude=archives -cf - . |
    tar -xf - -C "$WORK_DIR/source"
cat >>"$WORK_DIR/source/scripts/preflight.sh" <<'EOF'
valid_required() { :; }
prepare_zip() {
    mkdir -p "$CLASHCTL_HOME/bin"
    cp "$TEST_YQ" "$CLASHCTL_HOME/bin/yq"
    cp "$TEST_MIHOMO" "$CLASHCTL_HOME/bin/mihomo"
}
EOF
cd "$WORK_DIR/source"
bash install.sh --local --notebook >"$WORK_DIR/install.out" 2>&1 || { cat "$WORK_DIR/install.out"; fail 'notebook installation failed'; }
[ -f .clashctl/init.sh ] || fail 'current directory was not used'
[ ! -e "$HOME/.clashctl" ] || fail 'installed into HOME'
[ "$(cat "$HOME/.bashrc")" = '# original bashrc' ] || fail 'bashrc was modified'
grep -q 'CLASHCTL_INSTALL_MODE=notebook' .clashctl/.env || fail 'notebook mode was not saved'
grep -q 'INIT_TYPE=nohup' .clashctl/.env || fail 'nohup was not selected'
[ "$("$TEST_YQ" '.tun.enable' .clashctl/data/runtime.yaml)" = false ] || fail 'TUN enabled'
installed="$PWD/.clashctl"
export installed
bash -c '
    set -e
    unset http_proxy https_proxy all_proxy
    source "$installed/init.sh" --commands-only
    type clashctl >/dev/null
    test -z "${http_proxy:-}"
    clashctl stop
    source "$installed/init.sh" --commands-only
    ! service_is_active
    source "$installed/init.sh"
    test -n "$http_proxy"
    first=$(service_main_pid)
    source "$installed/init.sh"
    test "$first" = "$(service_main_pid)"
    clashctl stop
    # 模拟重启后留下的无效 PID 记录。
    printf "99999999\n" >"$CLASH_DATA_DIR/mihomo.pid"
    source "$installed/init.sh"
    service_is_active
    clashctl stop
    if source "$installed/init.sh" --invalid; then exit 1; fi
' >"$WORK_DIR/init.out" 2>&1 || { cat "$WORK_DIR/init.out"; fail 'initialization lifecycle failed'; }
if bash "$installed/init.sh" >"$WORK_DIR/execute.out" 2>&1; then fail 'init allowed execution without source'; fi
# 使用同一源码续装更新时保留 notebook 模式，即使省略 --notebook。
bash install.sh --local --home "$installed" >"$WORK_DIR/update.out" 2>&1 || { cat "$WORK_DIR/update.out"; fail 'notebook update failed'; }
[ "$(cat "$HOME/.bashrc")" = '# original bashrc' ] || fail 'update modified bashrc'
# 老版本普通安装没有模式字段，不能因 --notebook 请求而被误认成已有 notebook。
cp "$installed/.env" "$WORK_DIR/notebook.env"
sed -i '/^CLASHCTL_INSTALL_MODE=/d' "$installed/.env"
# 普通安装上次更新失败的标记也不能授权转换模式。
touch "$installed/.clashctl-incomplete"
if bash install.sh --local --notebook --home "$installed" >"$WORK_DIR/migration.out" 2>&1; then
    fail 'ordinary installation without mode key was silently converted'
fi
cp "$WORK_DIR/notebook.env" "$installed/.env"
rm -f "$installed/.clashctl-incomplete"
if bash install.sh --notebook --home "$installed" --service systemd-user >"$WORK_DIR/conflict.out" 2>&1; then
    fail 'notebook accepted conflicting service option'
fi
bash "$installed/uninstall.sh" --yes >"$WORK_DIR/uninstall.out" 2>&1 || { cat "$WORK_DIR/uninstall.out"; fail 'uninstall failed'; }
[ ! -e "$installed" ] || fail 'installation was not removed'
[ "$(cat "$HOME/.bashrc")" = '# original bashrc' ] || fail 'uninstall modified bashrc'
[ -f "$WORK_DIR/source/install.sh" ] || fail 'uninstall removed source'
# 显式目录及安装期 Base64 参数；订阅开启 TUN 的值必须由默认 Mixin 覆盖。
printf 'proxies:\n  - {name: test, type: ss, server: 192.0.2.1, port: 443, cipher: aes-128-gcm, password: test}\ntun: {enable: true}\n' |
    base64 >"$WORK_DIR/subscription.b64"
custom="$WORK_DIR/custom"
bash install.sh --local --notebook --home "$custom" --sub-base64-file "$WORK_DIR/subscription.b64" >"$WORK_DIR/custom.out" 2>&1 || { cat "$WORK_DIR/custom.out"; fail 'custom installation failed'; }
[ "$("$TEST_YQ" '.profiles[0].source' "$custom/data/profiles.yaml")" = manual ] || fail 'installer did not import manual subscription'
[ "$("$TEST_YQ" '.tun.enable' "$custom/data/runtime.yaml")" = false ] || fail 'subscription enabled TUN'
bash "$custom/uninstall.sh" --yes >"$WORK_DIR/custom-uninstall.out" 2>&1 || { cat "$WORK_DIR/custom-uninstall.out"; fail 'custom uninstall failed'; }
printf 'notebook: ok\n'
