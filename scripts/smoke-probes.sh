# Open WebUI：sso=oidc；清单没有 mcp。
SSO=oidc
MCP=0

web_assert() { grep -qi 'open webui'; }   # 标准输入：应用真实页面

identity_check() { # 走应用自己的 OIDC 登录端点，再调自己的“当前用户”接口：主人且是管理员
  local me
  curl -sS --noproxy '*' -o /dev/null -L -b "$SMOKE_JAR" -c "$SMOKE_JAR" "$SMOKE_WEB_URL/oauth/oidc/login" ||
    { echo "OIDC 登录链失败"; return 1; }
  me="$(web_get /api/v1/auths/ -H 'Accept: application/json')" || { echo "/api/v1/auths/ 失败：$me"; return 1; }
  jq -e --arg u "$SMOKE_OWNER" '.role == "admin" and (.name == $u or (.email | startswith($u + "@")))' <<<"$me" >/dev/null ||
    { echo "当前用户不是主人管理员：$me"; return 1; }
}
