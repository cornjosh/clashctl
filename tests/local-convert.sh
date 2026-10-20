#!/usr/bin/env bash
# 实际 curl 请求本地 HTTP fixture，校验转换器参数和生成的可用分组/规则。
set -euo pipefail
REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
WORK_DIR=$(mktemp -d)
server_pid=''
cleanup() {
    [ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
    wait 2>/dev/null || true
    rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
TEST_YQ=${TEST_YQ:-$(command -v yq || true)}
[ -x "$TEST_YQ" ] || fail 'MikeFarah yq v4 is required'
python3 - "$WORK_DIR" <<'PY' &
import base64
import http.server
import pathlib
import sys
import urllib.parse

work = pathlib.Path(sys.argv[1])
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        assert query["target"] == ["clash"]
        assert query["list"] == ["true"]
        assert query["insert"] == ["false"]
        uri = query["url"][0]
        assert uri.startswith("data:text/plain,")
        # data URI 解码后，subconverter 还会将订阅正文按 Base64 解码。
        decoded = base64.urlsafe_b64decode(uri.split(",", 1)[1])
        assert decoded == b"ss://YWVzLTEyOC1nY206dGVzdA==@192.0.2.1:443#PROXY\n"
        work.joinpath("received").write_bytes(decoded)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"proxies:\n  - {name: PROXY, type: ss, server: 192.0.2.1, port: 443, cipher: aes-128-gcm, password: test}\n")
    def log_message(self, *args):
        pass
with http.server.HTTPServer(("127.0.0.1", 0), Handler) as server:
    work.joinpath("port").write_text(str(server.server_port))
    server.serve_forever()
PY
server_pid=$!
for ((i=0; i<100; i++)); do [ ! -s "$WORK_DIR/port" ] || break; sleep 0.05; done
[ -s "$WORK_DIR/port" ] || fail 'HTTP fixture failed to start'
. "$REPO_DIR/scripts/lib/convert.sh"
BIN_YQ=$TEST_YQ
CLASH_RESOURCES_DIR=$WORK_DIR
BIN_SUBCONVERTER_PORT=$(cat "$WORK_DIR/port")
_start_convert() { sleep 30 >/dev/null 2>&1 & BIN_SUBCONVERTER_PID=$!; }
printf 'ss://YWVzLTEyOC1nY206dGVzdA==@192.0.2.1:443#PROXY\n' >"$WORK_DIR/nodes"
# 即使当前 Shell 代理失效，本地转换器仍应可访问。
http_proxy=http://127.0.0.1:1 HTTP_PROXY=http://127.0.0.1:1 \
    _convert_local_config "$WORK_DIR/config.yaml" "$WORK_DIR/nodes" || fail 'local conversion failed'
cmp "$WORK_DIR/nodes" "$WORK_DIR/received" || fail 'node content changed in transit'
"$BIN_YQ" -e '.proxy-groups[0].name == "PROXY_" and .rules[0] == "MATCH,PROXY_"' "$WORK_DIR/config.yaml" >/dev/null || fail 'proxy group conflicts with node name'
"$BIN_YQ" -e '(.proxy-groups[0].proxies | join(",")) == "PROXY"' "$WORK_DIR/config.yaml" >/dev/null || fail 'node missing from group'
printf 'local-convert: ok\n'
