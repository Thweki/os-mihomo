#!/bin/sh
# 在线订阅转换脚本

#################### 初始化 ####################
Server_Dir=$(cd "$(dirname "$0")" && pwd)
umask 077
Clash_Dir="${MIHOMO_DIR:-/usr/local/etc/mihomo}"
FORMAL_CONFIG="${MIHOMO_FORMAL_CONFIG:-$Clash_Dir/config.yaml}"
MIHOMO_BIN="${MIHOMO_BIN:-/usr/local/bin/mihomo}"
MIHOMO_SERVICE_CMD="${MIHOMO_SERVICE_CMD:-service mihomo restart}"
PHP_BIN="${MIHOMO_PHP_BIN:-/usr/local/bin/php}"
WRITE_HELPER="${MIHOMO_WRITE_HELPER:-/usr/local/opnsense/scripts/mihomo/subscription_install.php}"
LOCK_DIR="${MIHOMO_LOCK_DIR:-/var/run/mihomo-sub.lock}"
LOCK_HELD=0
TEMPLATE_FILE="$Server_Dir/template_config.yaml"
# Never stage in the directory containing the live config.yaml. Each invocation owns
# only its unique directory, on the same filesystem as the eventual target.
Temp_Dir=$(mktemp -d "$(dirname "$FORMAL_CONFIG")/.mihomo-sub.XXXXXX") || exit 1
Conf_Dir="$Temp_Dir"
TMP_RAW=""
TMP_PROXIES=""
TMP_NAMES=""
TMP_FINAL=""
BASELINE="$Temp_Dir/baseline.json"

cleanup_tmp_files() {
    [ -n "$TMP_RAW" ] && rm -f "$TMP_RAW"
    [ -n "$TMP_PROXIES" ] && rm -f "$TMP_PROXIES"
    [ -n "$TMP_NAMES" ] && rm -f "$TMP_NAMES"
    [ -n "$TMP_FINAL" ] && rm -f "$TMP_FINAL"
    rm -f "$Conf_Dir/config.clean.yaml" "$Conf_Dir/config.new.yaml" "$Conf_Dir/config.yaml" "$BASELINE"
    rmdir "$Temp_Dir" 2>/dev/null || true
    [ "$LOCK_HELD" = "1" ] && rm -f "$LOCK_DIR/pid" 2>/dev/null || true
    [ "$LOCK_HELD" = "1" ] && rmdir "$LOCK_DIR" 2>/dev/null || true
}

trap cleanup_tmp_files EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

command -v jq >/dev/null 2>&1 || {
  echo "缺少 jq 命令，请先安装（用于 URL 编码）"
  exit 1
}
command -v curl >/dev/null 2>&1 || {
  echo "缺少 curl 命令，请先安装。"
  exit 1
}
command -v openssl >/dev/null 2>&1 || {
  echo "缺少 openssl 命令，请先安装。"
  exit 1
}


if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_HELD=1
    printf '%s\n' "$$" > "$LOCK_DIR/pid" 2>/dev/null || true
else
    echo "错误：订阅任务已在运行，请勿重复执行。"
    [ -f "$LOCK_DIR/pid" ] && echo "当前锁持有进程 PID: $(cat "$LOCK_DIR/pid" 2>/dev/null)"
    exit 9
fi

# Snapshot before reading credentials/template. A concurrent settings or policy
# change is rejected by the installer instead of silently overwriting it.
"$PHP_BIN" "$WRITE_HELPER" snapshot "$FORMAL_CONFIG" "$TEMPLATE_FILE" "$Server_Dir/env" > "$BASELINE" || exit 1
ENV_MIHOMO_URL="${mihomo_URL:-}"
ENV_MIHOMO_SECRET="${mihomo_secret:-}"
ENV_MIHOMO_CONVERTER="${MIHOMO_CONVERTER_URL:-}"
[ -f "$Server_Dir/env" ] && . "$Server_Dir/env"
[ -n "$ENV_MIHOMO_URL" ] && mihomo_URL="$ENV_MIHOMO_URL"
[ -n "$ENV_MIHOMO_SECRET" ] && mihomo_secret="$ENV_MIHOMO_SECRET"
[ -n "$ENV_MIHOMO_CONVERTER" ] && MIHOMO_CONVERTER_URL="$ENV_MIHOMO_CONVERTER"
# Backward-compatible converter default. Set MIHOMO_CONVERTER_URL=direct for
# provider-supplied Clash YAML, or an HTTPS URL for a trusted/self-hosted converter.
API_BASE="${MIHOMO_CONVERTER_URL:-https://subconverters.com/sub}"
CURL_TLS_ARGS=""
[ "${INSECURE_TLS:-0}" = "1" ] && CURL_TLS_ARGS="-k"

# mihomo订阅地址校验
[ -z "$mihomo_URL" ] && {
    echo "错误：未设置 mihomo_URL 环境变量"
    exit 1
}
URL_SCHEME_CHECK=$(printf "%s" "$mihomo_URL" | tr '[:upper:]' '[:lower:]')
case "$URL_SCHEME_CHECK" in
    http://*|https://*) ;;
    *)
        echo "错误：mihomo_URL 必须以 http:// 或 https:// 开头"
        exit 1
        ;;
esac

# 安全密钥
Secret=${mihomo_secret:-$(openssl rand -hex 32)}

#################### 预清理临时文件 ####################

TMP_RAW=$(mktemp "$Temp_Dir/clash_config.XXXXXX") || {
    echo "创建临时文件失败：TMP_RAW"
    exit 1
}
TMP_PROXIES=$(mktemp "$Temp_Dir/proxies.XXXXXX") || {
    echo "创建临时文件失败：TMP_PROXIES"
    exit 1
}
TMP_NAMES=$(mktemp "$Temp_Dir/names.XXXXXX") || {
    echo "创建临时文件失败：TMP_NAMES"
    exit 1
}
TMP_FINAL=$(mktemp "$Temp_Dir/config.XXXXXX") || {
    echo "创建临时文件失败：TMP_FINAL"
    exit 1
}

#################### 下载配置 ####################
ENCODED_URL=$(printf "%s" "$mihomo_URL" | jq -s -R -r @uri)
case "$API_BASE" in
    direct) API_URL="$mihomo_URL" ;;
    https://*) API_URL="${API_BASE}?target=clash&url=${ENCODED_URL}&udp=true&clash.dns=true&list=false" ;;
    *) echo "转换服务必须使用 HTTPS，或设置为 direct。"; exit 1 ;;
esac
echo ""
echo "正在下载订阅配置（凭据不会写入日志）..."
if curl -fL $CURL_TLS_ARGS -sS --retry 3 -m 15 -o "$TMP_RAW" "$API_URL" 2>/dev/null; then
    echo "下载成功：$TMP_RAW"
else
    echo "下载失败，尝试通过 SOCKS5 代理 127.0.0.1:7891 下载配置..."
    if curl -fL $CURL_TLS_ARGS -sS --retry 2 -m 15 --socks5-hostname 127.0.0.1:7891 -o "$TMP_RAW" "$API_URL" 2>/dev/null; then
        echo "下载成功：$TMP_RAW"
    else
        echo "订阅下载失败。"
        echo "请检查网络连接或 mihomo 是否运行并监听 127.0.0.1:7891"
        exit 2
    fi
fi

if [ ! -s "$TMP_RAW" ]; then
    echo "下载结果为空，订阅内容无效。"
    exit 1
fi

RAW_SIZE=$(wc -c < "$TMP_RAW" | tr -d ' ')
echo "下载文件大小: ${RAW_SIZE} 字节"

if head -n 20 "$TMP_RAW" | grep -Eiq '^(<!doctype html|<html|<head|<body)'; then
    echo "检测到返回内容为 HTML 页面，订阅可能失效或被拦截。"
    exit 1
fi

if ! grep -Eq '^[[:space:]]*proxies[[:space:]]*:' "$TMP_RAW"; then
    echo "下载结果缺少 proxies: 节点，订阅内容可能无效。"
    exit 1
fi
echo ""

#################### 合成配置 ####################
TEMPLATE_FILE="$Server_Dir/template_config.yaml"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "缺少模板文件：$TEMPLATE_FILE"
    exit 1
fi
if ! grep -q '__MIHOMO_PROXIES__' "$TEMPLATE_FILE" || ! grep -q '__MIHOMO_NODE_NAMES__' "$TEMPLATE_FILE"; then
    echo "模板文件缺少订阅占位符：__MIHOMO_PROXIES__ 或 __MIHOMO_NODE_NAMES__"
    exit 1
fi

# 只提取 proxies 顶层段，避免订阅里的 proxy-groups/rules 覆盖模板策略。
awk '
  /^[[:space:]]*proxies[[:space:]]*:/ {
      in_proxies = 1
      print
      next
  }
  in_proxies && /^[^[:space:]][^:]*[[:space:]]*:/ {
      exit
  }
  in_proxies {
      print
  }
' "$TMP_RAW" | sed 's/www\.speedtet\.net/www.speedtest.net/g' > "$TMP_PROXIES"

if [ ! -s "$TMP_PROXIES" ]; then
    echo "提取代理节点失败，proxies 段为空。"
    exit 1
fi

NODE_COUNT=$(awk '
  BEGIN { count = 0 }
  /^[[:space:]]*proxies[[:space:]]*:/ { in_proxies = 1; next }
  in_proxies && /^[^[:space:]]/ { in_proxies = 0 }
  in_proxies && /^[[:space:]]*-[[:space:]]/ { count++ }
  END { print count }
' "$TMP_PROXIES" | tr -d ' ')
echo "提取节点数量: ${NODE_COUNT}"
if [ "${NODE_COUNT:-0}" -le 0 ] 2>/dev/null; then
    echo "提取到的代理节点数量为 0，停止应用。"
    exit 1
fi

awk '
  function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
  }
  function unquote(s) {
      s = trim(s)
      if ((substr(s, 1, 1) == "\"" && substr(s, length(s), 1) == "\"") ||
          (substr(s, 1, 1) == "\047" && substr(s, length(s), 1) == "\047")) {
          s = substr(s, 2, length(s) - 2)
      }
      return s
  }
  function emit(s) {
      s = unquote(s)
      if (s != "" && !seen[s]++) {
          gsub(/\\/, "\\\\", s)
          gsub(/"/, "\\\"", s)
          print "      - \"" s "\""
      }
  }
  /^[[:space:]]*-[[:space:]]*\{/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*\{[[:space:]]*name:[[:space:]]*/, "", line)
      sub(/[[:space:]]*,[[:space:]]*server:.*/, "", line)
      emit(line)
      next
  }
  /^[[:space:]]*-[[:space:]]*name[[:space:]]*:/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*name[[:space:]]*:[[:space:]]*/, "", line)
      emit(line)
      next
  }
  /^[[:space:]]*name[[:space:]]*:/ {
      line = $0
      sub(/^[[:space:]]*name[[:space:]]*:[[:space:]]*/, "", line)
      emit(line)
      next
  }
' "$TMP_PROXIES" > "$TMP_NAMES"

if [ ! -s "$TMP_NAMES" ]; then
    echo "提取代理节点名称失败。"
    exit 1
fi

# 合成配置
echo "合成配置..."
awk -v proxies_file="$TMP_PROXIES" -v names_file="$TMP_NAMES" '
  /^[[:space:]]*#[[:space:]]*__MIHOMO_PROXIES__[[:space:]]*$/ {
      while ((getline line < proxies_file) > 0) print line
      close(proxies_file)
      next
  }
  /^[[:space:]]*#[[:space:]]*__MIHOMO_NODE_NAMES__[[:space:]]*$/ {
      while ((getline line < names_file) > 0) print line
      close(names_file)
      next
  }
  { print }
' "$TEMPLATE_FILE" > "$TMP_FINAL"

if [ ! -s "$TMP_FINAL" ]; then
    echo "合成后的配置文件为空。"
    exit 1
fi

FINAL_SIZE=$(wc -c < "$TMP_FINAL" | tr -d ' ')
echo "合成配置大小: ${FINAL_SIZE} 字节"

cp "$TMP_FINAL" "$Conf_Dir/config.yaml" || {
    echo "写入临时配置失败：$Conf_Dir/config.yaml"
    exit 1
}

# 先清理旧的 secret，再在 external-ui 行之后插入 secret
awk '!/^[[:space:]]*secret[[:space:]]*:/ { print }' "$Conf_Dir/config.yaml" > "$Conf_Dir/config.clean.yaml" && mv "$Conf_Dir/config.clean.yaml" "$Conf_Dir/config.yaml"

if grep -q '^external-ui:' "$Conf_Dir/config.yaml"; then
    awk -v secret="secret: ${Secret}" '
      /^external-ui:/ {
          print;
          print secret;
          next
      }
      { print }
    ' "$Conf_Dir/config.yaml" > "$Conf_Dir/config.new.yaml" && mv "$Conf_Dir/config.new.yaml" "$Conf_Dir/config.yaml"
else
    echo "secret: ${Secret}" >> "$Conf_Dir/config.yaml"
fi
echo "合成完成!"
echo ""

#################### 校验、原子提交与失败恢复 ####################
# The PHP bridge validates under the shared writer lock, backs up the actual old
# bytes, renames on the target filesystem and rolls back if an opted-in restart fails.
"$PHP_BIN" "$WRITE_HELPER" install "$Conf_Dir/config.yaml" "$FORMAL_CONFIG" \
    "$Clash_Dir" "$MIHOMO_BIN" "$BASELINE" "$MIHOMO_SERVICE_CMD" "$TEMPLATE_FILE"
exit $?
