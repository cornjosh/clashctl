#!/usr/bin/env bash
# 在当前 Bash 中恢复命令和代理，不依赖 ~/.bashrc。
if [ -z "${BASH_VERSION:-}" ]; then
    printf '请在 Bash 中执行 source /安装目录/init.sh\n' >&2
    return 1 2>/dev/null || exit 1
fi
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    printf '请使用 source %q [--commands-only]，以修改当前终端的代理环境\n' "$0" >&2
    exit 1
fi

_clashctl_notebook_init() {
    case "${1:-}" in
    -h | --help)
        printf '用法: source /安装目录/init.sh [--commands-only]\n默认加载命令、启动内核并启用当前 Bash 代理；--commands-only 只加载命令。\n'
        return 0 ;;
    '' | --commands-only) ;;
    *) printf '未知初始化参数：%s\n' "$1" >&2; return 1 ;;
    esac
    [ "$#" -le 1 ] || { printf '初始化只接受 --commands-only 参数\n' >&2; return 1; }
    local init_home
    init_home=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || return 1
    [ -f "$init_home/.env" ] || { printf '该目录尚未完成安装：%s\n' "$init_home" >&2; return 1; }
    export CLASHCTL_HOME="$init_home"
    # shellcheck source=scripts/cmd/clashctl.sh
    . "$CLASHCTL_HOME/scripts/cmd/clashctl.sh" || return 1
    [ "${1:-}" != --commands-only ] || return 0
    clashctl on
}

_clashctl_notebook_init "$@"
