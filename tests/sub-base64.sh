#!/usr/bin/env bash
# 本地内容导入不下载订阅；坏输入不提交；手动订阅更新不触网。
set -euo pipefail
REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
WORK_DIR=$(mktemp -d)
trap 'rm -rf -- "$WORK_DIR"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
TEST_YQ=${TEST_YQ:-$(command -v yq || true)}
[ -x "$TEST_YQ" ] || fail 'MikeFarah yq v4 is required'
export CLASHCTL_HOME="$WORK_DIR/home" CLASHCTL_KERNEL=mihomo
mkdir -p "$CLASHCTL_HOME/data/profiles" "$CLASHCTL_HOME/resources"
. "$REPO_DIR/scripts/lib/common.sh"
. "$REPO_DIR/scripts/lib/convert.sh"
. "$REPO_DIR/scripts/cmd/sub.sh"
BIN_YQ=$TEST_YQ
cp "$REPO_DIR/resources/profiles.yaml" "$CLASH_PROFILES_META"
# 内核校验为边界替身，元数据和配置读写使用真实 yq。
_valid_config() { "$BIN_YQ" -e 'tag == "!!map" and (.proxies | length > 0)' "$1" >/dev/null; }
_download_raw_config() { fail 'manual input tried downloading a subscription'; }
cat >"$WORK_DIR/config.yaml" <<'EOF'
proxies:
  - {name: example, type: ss, server: 192.0.2.1, port: 443, cipher: aes-128-gcm, password: test}
EOF
base64 "$WORK_DIR/config.yaml" >"$WORK_DIR/content.b64"
content=$(cat "$WORK_DIR/content.b64")
sub_add --base64 "$content" --name pasted >"$WORK_DIR/out" 2>&1 || { cat "$WORK_DIR/out"; fail 'Base64 paste rejected'; }
cmp "$WORK_DIR/config.yaml" "$(_sub_get pasted path)" || fail 'decoded YAML changed'
[ "$(_sub_get pasted source)" = manual ] || fail 'manual source not recorded'
sub_add --base64-file "$WORK_DIR/content.b64" --name file >"$WORK_DIR/out" 2>&1 || { cat "$WORK_DIR/out"; fail 'Base64 file rejected'; }
sub_add --base64-file - --name stdin <"$WORK_DIR/content.b64" >"$WORK_DIR/out" 2>&1 || fail 'Base64 stdin rejected'
base64 -w0 "$WORK_DIR/config.yaml" | sub_add --name interactive >"$WORK_DIR/out" 2>&1 || fail 'Base64 interactive input rejected'
for bad in '%%%invalid%%%' '' 'YWJjZA='; do
    if sub_add --base64 "$bad" --name bad >"$WORK_DIR/out" 2>&1; then fail 'invalid Base64 accepted'; fi
done
if sub_add --base64 "$content" https://example.invalid >"$WORK_DIR/out" 2>&1; then fail 'ambiguous source accepted'; fi
[ "$("$BIN_YQ" '.profiles | length' "$CLASH_PROFILES_META")" = 4 ] || fail 'invalid input committed metadata'
before=$(sha256sum "$CLASH_PROFILES_META")
_sub_update_one pasted auto >"$WORK_DIR/out" 2>&1 || fail 'manual update should skip successfully'
_sub_update --all >"$WORK_DIR/out" 2>&1 || fail 'manual update-all should skip successfully'
[ "$before" = "$(sha256sum "$CLASH_PROFILES_META")" ] || fail 'manual update changed metadata'
# Node list 必须传递解码内容给本地转换器；校验转换结果后才允许提交。
_convert_local_config() {
    cmp "$2" "$WORK_DIR/nodes" || return 1
    cp "$WORK_DIR/config.yaml" "$1"
}
printf 'ss://YWVzLTEyOC1nY206dGVzdA==@192.0.2.1:443#example\n' >"$WORK_DIR/nodes"
sub_add --base64 "$(base64 "$WORK_DIR/nodes")" --name nodes >"$WORK_DIR/out" 2>&1 || { cat "$WORK_DIR/out"; fail 'Base64 nodes rejected'; }
_convert_local_config() { printf 'proxies: []\n' >"$1"; }
if sub_add --base64 "$(base64 "$WORK_DIR/nodes")" --name empty >"$WORK_DIR/out" 2>&1; then fail 'empty converted nodes accepted'; fi
! _sub_has empty || fail 'invalid conversion committed'
printf 'sub-base64: ok\n'
