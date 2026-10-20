#!/usr/bin/env bash
set -euo pipefail
REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
. "$REPO_DIR/install.sh"
WORK_DIR=$(mktemp -d)
trap 'rm -rf -- "$WORK_DIR"' EXIT
# Keep source validation and archive extraction real; replace only network I/O.
mkdir "$WORK_DIR/package"
# shellcheck disable=SC2218  # Invoke the executable before defining the network stub.
command git -C "$REPO_DIR" archive HEAD | tar -x -C "$WORK_DIR/package"
tar -czf "$WORK_DIR/source.tar.gz" -C "$WORK_DIR" package
export WORK_DIR
curl() {
    local output='' url=''
    while [ "$#" -gt 0 ]; do
        case $1 in -o) output=$2; shift ;; https://*) url=$1 ;; esac
        shift
    done
    [ "$url" = 'https://github.com/cornjosh/clashctl/archive/refs/heads/master.tar.gz' ] || {
        printf 'FAIL: wrong archive source: %s\n' "$url" >&2; return 1;
    }
    cp "$WORK_DIR/source.tar.gz" "$output"
}
mkdir "$WORK_DIR/archive"
_source_archive "$WORK_DIR/archive" master ''
export CLASHCTL_INSTALL_MODE=notebook
_source_validate "$WORK_DIR/archive"
git() {
    local last=${!#} arg url=''
    for arg in "$@"; do case $arg in https://*) url=$arg ;; esac; done
    [ "$url" = 'https://github.com/cornjosh/clashctl.git' ] || {
        printf 'FAIL: wrong git source: %s\n' "$url" >&2; return 1;
    }
    mkdir -p "$last"
    tar -xzf "$WORK_DIR/source.tar.gz" --strip-components=1 -C "$last"
}
_install_prepare_source "$WORK_DIR/git" master '' false ''
printf 'source-origin: ok\n'
