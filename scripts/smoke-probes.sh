# shellcheck shell=bash
# Open WebUI：sso=oidc；清单没有 mcp。
export SSO=oidc
export MCP=0

web_assert() { grep -qi 'open webui'; }   # 标准输入：应用真实页面

identity_check() { # 走应用自己的 OIDC 登录端点，再调自己的“当前用户”接口：用户且是管理员
  local me
  curl -sS --noproxy '*' -o /dev/null -L -b "$SMOKE_JAR" -c "$SMOKE_JAR" "$SMOKE_WEB_URL/oauth/oidc/login" ||
    { echo "OIDC 登录链失败"; return 1; }
  me="$(web_get /api/v1/auths/ -H 'Accept: application/json')" || { echo "/api/v1/auths/ 失败：$me"; return 1; }
  jq -e --arg u "$SMOKE_OWNER" '.role == "admin" and (.name == $u or (.email | startswith($u + "@")))' <<<"$me" >/dev/null ||
    { echo "当前用户不是用户管理员：$me"; return 1; }
}

# 数据：对话是 Open WebUI 的用户数据，存在 /data 里，升级、重装都保留。
# data_write 登录后建一条带随机标记的对话，标记写进 SMOKE_STATE；data_check 读回标记，在对话列表里找回它。
# 只依赖模板约定的变量（SMOKE_STATE/SMOKE_JAR/SMOKE_WEB_URL）和助手 web_get、dweb。
# 应用会话分两层：核心会话由 dweb 写进 SMOKE_JAR，应用自己的会话要走 /oauth/oidc/login 换
# （应用根路径是前端 SPA，curl 跟不到它的登录跳转），identity_check 同款。
app_login() (
  set -eu
  dweb / >/dev/null
  curl -sS --noproxy '*' -o /dev/null -L -b "$SMOKE_JAR" -c "$SMOKE_JAR" "$SMOKE_WEB_URL/oauth/oidc/login"
)

# e2e 套件给的 SMOKE_STATE 是标记文件，套件自己的 smoke 和 dev.sh probes 给的是 .wonton 目录：
# 是目录就把标记落成目录里的文件，两种都落得进。
data_mark_file() {
  if [[ -d "${SMOKE_STATE:-}" ]]; then printf '%s\n' "$SMOKE_STATE/smoke-chat-mark"; else printf '%s\n' "$SMOKE_STATE"; fi
}

data_write() (
  set -eu
  local mark out mf
  [[ -n "${SMOKE_STATE:-}" && -n "${SMOKE_JAR:-}" && -n "${SMOKE_WEB_URL:-}" ]] ||
    { echo "缺 SMOKE_STATE/SMOKE_JAR/SMOKE_WEB_URL"; return 1; }
  app_login || { echo "登录链失败"; return 1; }
  mark="$(date +%Y%m%d%H%M%S)-$RANDOM"
  out="$(web_post /api/v1/chats/new "{\"chat\":{\"title\":\"wonton-smoke-$mark\",\"messages\":[]}}")" ||
    { echo "建对话失败：$out"; return 1; }
  jq -e '.id' <<<"$out" >/dev/null || { echo "chats/new 返回没有 id：$out"; return 1; }
  mf="$(data_mark_file)"
  printf '%s' "$mark" >"$mf"
  echo "已建对话 wonton-smoke-$mark"
)

data_check() (
  set -eu
  local mark out mf
  [[ -n "${SMOKE_STATE:-}" ]] || { echo "缺 SMOKE_STATE"; return 1; }
  mf="$(data_mark_file)"
  mark="$(cat "$mf" 2>/dev/null)" || mark=""
  [[ -n "$mark" ]] || { echo "没有 data_write 写下的标记"; return 1; }
  app_login || { echo "登录链失败"; return 1; }
  out="$(web_get /api/v1/chats/)" || { echo "读对话列表失败：$out"; return 1; }
  jq -e --arg t "wonton-smoke-$mark" 'any(.[]; .title == $t)' <<<"$out" >/dev/null ||
    { echo "找不到对话 wonton-smoke-$mark，看到的是：$(head -c 200 <<<"$out")"; return 1; }
  echo "对话 wonton-smoke-$mark 还在：升级/重装保住了数据"
)

# POST 助手：带用户会话（SMOKE_JAR 里的网关会话 + 应用会话）向应用自己的接口发 JSON。
web_post() (
  set -eu
  local path="$1" body="$2"
  [[ -n "${SMOKE_WEB_URL:-}" ]] || { echo "缺 SMOKE_WEB_URL"; return 1; }
  curl -sS --noproxy '*' --fail-with-body -b "${SMOKE_JAR:-}" --max-time 120 \
    -H 'Content-Type: application/json' -d "$body" "$SMOKE_WEB_URL$path"
)
