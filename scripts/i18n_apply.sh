#!/bin/sh
# os-mihomo —— 把插件中文词条合并进 OPNsense 的 gettext 词库
#
# 背景：OPNsense 使用单一 gettext 域（defaultDomain=OPNsense，
#       目录 /usr/local/share/locale/<locale>/LC_MESSAGES/OPNsense.mo），
#       插件字符串要显示中文只能合并进这个文件。
#
# 本脚本「只增不改」：
#   · 先备份原文件（带时间戳，可用 --rollback 还原）
#   · 合并时若某词条已存在（= 核心已有译文），一律保留原译文，不覆盖
#   · 合并后逐条校验，失败自动回滚
#
# 用法:
#   i18n_apply.sh apply [locale]      合并（默认 zh_CN）
#   i18n_apply.sh rollback [locale]   从最近一次备份还原
#   i18n_apply.sh status [locale]     查看当前是否含插件词条
set -u

LOCALE_DEFAULT=zh_CN
ACTION="${1:-apply}"
LOCALE="${2:-$LOCALE_DEFAULT}"

MO_DIR="/usr/local/share/locale/$LOCALE/LC_MESSAGES"
MO="$MO_DIR/OPNsense.mo"
PO="/tmp/os-mihomo-zh_CN.po"
PY=/usr/local/bin/python3
EDITOR_SCRIPT=/tmp/os-mihomo-mo_editor.py
BAK_DIR=/usr/local/opnsense/_bak/os-mihomo-i18n

[ -f "$MO" ] || { echo "找不到 $MO"; exit 2; }
[ -f "$PO" ] || { echo "找不到 $PO（应由 tools/i18n.ps1 推送）"; exit 2; }
[ -f "$EDITOR_SCRIPT" ] || { echo "找不到 $EDITOR_SCRIPT"; exit 2; }

MARK='Proxy Groups'   # 具有代表性的插件词条，用于状态判断

case "$ACTION" in
    apply)
        mkdir -p "$BAK_DIR"
        TS=$(date '+%Y%m%d_%H%M%S')
        cp -a "$MO" "$BAK_DIR/OPNsense.mo.$TS"
        chmod 0644 "$BAK_DIR/OPNsense.mo.$TS"
        echo "已备份: $BAK_DIR/OPNsense.mo.$TS"

        OUT="$MO.new"
        if ! $PY "$EDITOR_SCRIPT" merge "$MO" "$PO" -o "$OUT" --stats; then
            echo "合并失败（未改动系统文件）"; rm -f "$OUT"; exit 1
        fi

        echo "--- 合并后校验 ---"
        if ! $PY "$EDITOR_SCRIPT" verify "$OUT" "$PO"; then
            echo "校验失败，已放弃（未改动系统文件）"; rm -f "$OUT"; exit 1
        fi

        # 确认核心词条没有被改写
        if ! $PY "$EDITOR_SCRIPT" diff-core "$MO" "$OUT"; then
            echo "检测到核心译文被改写，已放弃"; rm -f "$OUT"; exit 1
        fi

        chown root:wheel "$OUT"; chmod 0644 "$OUT"
        mv -f "$OUT" "$MO"
        echo "已安装: $MO"
        $PY "$EDITOR_SCRIPT" dump "$MO" --filter "$MARK" | head -3
        ;;

    rollback)
        LAST=$(ls -1t "$BAK_DIR"/OPNsense.mo.* 2>/dev/null | head -1)
        [ -n "$LAST" ] || { echo "没有可用备份"; exit 2; }
        cp -a "$LAST" "$MO"
        chmod 0644 "$MO"; chown root:wheel "$MO"
        echo "已从 $LAST 还原 $MO"
        ;;

    status)
        if $PY "$EDITOR_SCRIPT" dump "$MO" --filter "$MARK" | grep -q "$MARK"; then
            echo "已包含插件中文词条"
            $PY "$EDITOR_SCRIPT" dump "$MO" --filter "$MARK" | head -3
        else
            echo "尚未包含插件词条（或已被系统更新覆盖）"
        fi
        ls -la "$BAK_DIR" 2>/dev/null | tail -3
        ;;

    *)
        echo "usage: i18n_apply.sh {apply|rollback|status} [locale]"; exit 2 ;;
esac
