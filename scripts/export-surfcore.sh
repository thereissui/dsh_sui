#!/bin/bash
# 重新导出 surfcore 的本地定制备份（三个产物）。
#
# 用法：
#   bash scripts/export-surfcore.sh                    # 用默认基线（上游 v0.8.9 = 0ce8580）
#   bash scripts/export-surfcore.sh <基线提交>          # 换基线，比如上游又发了新版
#   bash scripts/export-surfcore.sh --check             # 只检查产物是否最新，不重写
#
# 产物（全部落在 private/patches/，那个目录被 .gitignore 整目录挡住）：
#   surfcore/              40 个 .patch —— 逐提交历史，含私人标识（含人格卡正文），不能公开
#   surfcore-net.diff      净改动（git diff -w）—— 唯一可公开的版本
#   surfcore-full.bundle   完整 git 历史 —— 本机灾备，clone 就能完整恢复
#
# 退出码：0 = 成功；1 = 有失败；2 = 用法错误；3 = --check 发现产物过期
#
# 为什么必须带 -w（忽略空白）：
#   上游是 LF、本地工作区是 CRLF，不带 -w 的话 src/bridge.js 会被算成
#   「18000 行增 / 17800 行删」的整文件重写，其中 98% 是行尾噪音。
#   真实改动量约 5500 增 / 160 删。这条坑踩过两次，别再去掉。
#
# 为什么产物必须放 private/：
#   dsh_sui 是公开仓库。patch 集与 bundle 里含人格卡正文、角色名、主人 QQ、
#   B 站 mid。private/ 被 .gitignore 挡住，放别处会被 git add 收走。
#
# ⚠️ Windows 陷阱：CON / PRN / AUX / NUL / COM1-9 / LPT1-9 是保留设备名，
#   读它们会永久挂死。本脚本只操作 .patch/.diff/.bundle，不遍历整个工作区。

set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
# 默认导出到本仓库 private/patches；可用 SURFCORE_EXPORT_DIR 覆盖（换机器时用）。
OUT_DIR="${SURFCORE_EXPORT_DIR:-$REPO_ROOT/private/patches}"

# surfcore 的位置：优先环境变量，其次从 private/README 常见位置猜。
SURFCORE_DIR="${SURFCORE_DIR:-}"
if [ -z "$SURFCORE_DIR" ]; then
  # 带 set -u 时 $USER / $USERNAME 可能都没定义（MSYS bash 与 cmd 来源不同），
  # 所以用 :- 兜空，不能用裸变量。
  for cand in "C:/Users/${USER:-${USERNAME:-}}/surfcore" "$HOME/surfcore"; do
    if [ -d "$cand/.git" ]; then SURFCORE_DIR="$cand"; break; fi
  done
fi

# 上游基线：默认 v0.8.9 的提交号。换上游版本时改这里或用第一个参数。
BASE_DEFAULT="0ce8580"

# 私人标识模式：从 private/patches/.private-patterns 读（一行一个正则，跳过空行和 #）。
# 为什么不写在脚本里：本脚本会进公开仓库，但模式里含本机身份明文
# （角色名、主人 QQ、机器人 QQ、B 站 mid）。写进脚本等于把私货抄进公开代码，
# 正是这套检查要防的事。文件缺失时降级为「跳过该项检查」并明确提示，不静默放行。
PRIVATE_PATTERNS_FILE="$OUT_DIR/.private-patterns"
PRIVATE_RE=''
if [ -f "$PRIVATE_PATTERNS_FILE" ]; then
  # 用 grep -v 去掉注释/空行，再用 | 拼成一个 alternation。
  PRIVATE_RE="$(grep -vE '^\s*(#|$)' "$PRIVATE_PATTERNS_FILE" | sed 's/[][\\.^$*+?(){}|]/\\&/g' | paste -sd'|' -)"
else
  echo "⚠️  缺 $PRIVATE_PATTERNS_FILE：本次跳过私人标识检查（不能确认净 diff 可以公开）"
fi

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then CHECK_ONLY=1; shift; fi
BASE="${1:-$BASE_DEFAULT}"

fail() { echo "❌ $*" >&2; exit 1; }

# 计数辅助：PRIVATE_RE 为空时 grep -cE "" 会匹配每一行（假阳性），必须显式跳过。
count_private_hits() {
  [ -n "$PRIVATE_RE" ] || { echo 0; return; }
  grep -cE "$PRIVATE_RE" "$1" 2>/dev/null || true
}
show_private_hits() {
  [ -n "$PRIVATE_RE" ] || return 0
  grep -nE "$PRIVATE_RE" "$1" 2>/dev/null | head -5 | sed 's/^/    /'
}

[ -n "$SURFCORE_DIR" ] || fail "找不到 surfcore 仓库：设 SURFCORE_DIR=/path/to/surfcore 后重跑"
[ -d "$SURFCORE_DIR/.git" ] || fail "SURFCORE_DIR 不是 git 仓库：$SURFCORE_DIR"
[ -d "$OUT_DIR" ] || fail "输出目录不存在：$OUT_DIR（先 mkdir -p）"

cd "$SURFCORE_DIR" || fail "进不去 $SURFCORE_DIR"

# 基线必须真实存在，否则 format-patch 会静默产出空结果。
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || fail "基线提交不存在：$BASE"
HEAD_SHA="$(git rev-parse HEAD)"
BASE_SHA="$(git rev-parse "$BASE")"
COUNT="$(git rev-list --count "$BASE..HEAD")"

echo "仓库：$SURFCORE_DIR"
echo "基线：$BASE ($(git log -1 --format='%h %s' "$BASE"))"
echo "HEAD：$(git log -1 --format='%h %s' HEAD)"
echo "落后上游提交数：$COUNT"
echo "输出：$OUT_DIR"
echo

# 工作区脏就别导：导出来的东西会和工作区状态对不上，恢复时容易误判。
# 只警告不阻止 —— 有人可能故意导出「已提交的部分」，但那要知道自己在干什么。
if [ -n "$(git status --porcelain)" ]; then
  echo "⚠️  工作区不干净（有未提交改动）。本次只导出已提交的内容。"
  git status --porcelain | head -5 | sed 's/^/    /'
  echo
fi

# ── --check：只比对，不重写 ─────────────────────────────────────────────────
if [ "$CHECK_ONLY" -eq 1 ]; then
  STALE=0
  # 元数据里记了导出时的 HEAD；对不上就是过期。
  META="$OUT_DIR/.export-meta.json"
  if [ ! -f "$META" ]; then
    echo "❌ 还没导出过（缺 $META）"; exit 3
  fi
  OLD_HEAD="$(sed -n 's/.*"head":"\([^"]*\)".*/\1/p' "$META")"
  if [ "$OLD_HEAD" != "$HEAD_SHA" ]; then
    echo "❌ 产物已过期：导出时 HEAD=$OLD_HEAD，现在 HEAD=$HEAD_SHA"
    echo "   → 跑 bash scripts/export-surfcore.sh 重新生成"
    STALE=1
  fi
  # 净 diff 的私人标识命中数：非 0 说明有新的私货混进最终状态。
  HITS=0
  if [ -f "$OUT_DIR/surfcore-net.diff" ]; then
    HITS="$(count_private_hits "$OUT_DIR/surfcore-net.diff")"
  else
    echo "❌ 缺 surfcore-net.diff"; STALE=1
  fi
  if [ "${HITS:-0}" != "0" ]; then
    echo "❌ 净 diff 里命中私人标识 $HITS 处（应为 0）"
    show_private_hits "$OUT_DIR/surfcore-net.diff"
    STALE=1
  fi
  [ -f "$OUT_DIR/surfcore-full.bundle" ] || { echo "❌ 缺 surfcore-full.bundle"; STALE=1; }
  [ "$STALE" -eq 0 ] && { echo "✅ 产物是最新的（HEAD=$HEAD_SHA）"; exit 0; }
  exit 3
fi

# ── 1) patch 集：逐提交历史 ─────────────────────────────────────────────────
PATCH_DIR="$OUT_DIR/surfcore"
mkdir -p "$PATCH_DIR"
# 清旧的：否则删掉的提交会留下孤儿 patch，恢复时 am 到一半失败。
rm -f "$PATCH_DIR"/*.patch
if ! git format-patch "$BASE..HEAD" -o "$PATCH_DIR" >/dev/null; then
  fail "format-patch 失败"
fi
PATCH_COUNT="$(ls "$PATCH_DIR"/*.patch 2>/dev/null | wc -l | tr -d ' ')"
[ "$PATCH_COUNT" -eq "$COUNT" ] || fail "patch 数量不符：预期 $COUNT，实际 $PATCH_COUNT"
echo "✅ patch 集：$PATCH_COUNT 个（$PATCH_DIR）"

# ── 2) 净 diff：唯一可公开的版本 ────────────────────────────────────────────
NET_DIFF="$OUT_DIR/surfcore-net.diff"
# 必须 -w，理由见文件头。
if ! git diff -w "$BASE..HEAD" > "$NET_DIFF"; then
  fail "git diff 失败"
fi
NET_BYTES="$(wc -c < "$NET_DIFF" | tr -d ' ')"
NET_HITS="$(count_private_hits "$NET_DIFF")"
echo "✅ 净 diff：$NET_BYTES 字节，私人标识命中 ${NET_HITS:-0} 处（期望 0）"
if [ "${NET_HITS:-0}" != "0" ]; then
  echo "⚠️  净 diff 里还有私人标识，这个版本不能公开："
  show_private_hits "$NET_DIFF"
  echo "    → 先在 surfcore 里把这行清理掉（参考 docs/PITFALLS.md #26），再重新导出"
fi

# ── 3) 完整 bundle：本机灾备 ────────────────────────────────────────────────
# 用 main 全量，不用 BASE..HEAD：增量 bundle 的 verify 会报
# 「The bundle requires this ref」，clone 不出来（踩过一次）。
BUNDLE="$OUT_DIR/surfcore-full.bundle"
if ! git bundle create "$BUNDLE" main >/dev/null 2>&1; then
  fail "bundle create 失败"
fi
if ! git bundle verify "$BUNDLE" >/dev/null 2>&1; then
  fail "bundle verify 失败（包可能不完整）"
fi
BUNDLE_BYTES="$(wc -c < "$BUNDLE" | tr -d ' ')"
echo "✅ bundle：$BUNDLE_BYTES 字节，verify 通过（完整历史可 clone）"

# ── 4) 元数据：--check 靠它判断过期 ─────────────────────────────────────────
cat > "$OUT_DIR/.export-meta.json" <<EOF
{"head":"$HEAD_SHA","base":"$BASE_SHA","baseRef":"$BASE","commits":$COUNT,"patches":$PATCH_COUNT,"netDiffBytes":$NET_BYTES,"bundleBytes":$BUNDLE_BYTES,"exportedAt":"$(date -Iseconds)"}
EOF
echo "✅ 元数据：$OUT_DIR/.export-meta.json"
echo
echo "完成。三个产物都在 $OUT_DIR"
echo "   surfcore/            逐提交 patch（含私货，只能留 private/）"
echo "   surfcore-net.diff    净改动（唯一可公开的）"
echo "   surfcore-full.bundle 完整历史（本机灾备，别外传）"
exit 0
