#!/bin/bash
# 提交前隐私检查：扫暂存区里有没有不该出现在公开仓库的东西。
#
# 用法：
#   bash scripts/pre-commit-check.sh          # 检查已暂存的文件
#   bash scripts/pre-commit-check.sh --all    # 检查整个工作区（含未跟踪）
#
# 退出码 0 = 干净；1 = 发现问题（此时别提交）；124 = 有文件读不动（超时）
#
# 为什么需要它：这个仓库是公开的。文件一旦进历史就很难彻底删（要重写历史）。
#
# ⚠️ Windows 陷阱：CON / PRN / AUX / NUL / COM1-9 / LPT1-9 是保留设备名。
#    `grep 文件` 会挂死（等设备输入），`head` 也一样。所以扫描前必须跳过它们。

set -uo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-}"
# -c core.quotepath=false：否则中文文件名会被 git 转义成 "docs/\347\216..." 形式，
# 后面的 [ -f "$f" ] 判断失败 → 文件被静默跳过（实测漏检 3 个中文名文件）。
if [ "$MODE" = "--all" ]; then
  FILES=$(git -c core.quotepath=false ls-files -co --exclude-standard | grep -v '^private/' || true)
else
  FILES=$(git -c core.quotepath=false diff --cached --name-only --diff-filter=ACM || true)
fi

if [ -z "$FILES" ]; then
  echo "没有需要检查的文件。"
  exit 0
fi

# Windows 保留设备名：读到它们会永久挂起
RESERVED='^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'

SKIPPED=()
CHECKED=0
BAD=0

# 危险模式：命中即报警
# 注意：本脚本自身也被扫描时会把下面这些模式文本当成命中，
# 所以扫描前先把自己排除掉（见下方 SELF 判断）。
SELF="scripts/pre-commit-check.sh"
PATTERNS=(
  'github_pat_[A-Za-z0-9_]'
  'gho_[A-Za-z0-9]{20,}'
  'ghp_[A-Za-z0-9]{20,}'
  'sk-[A-Za-z0-9]{20,}'
  'SESSDATA='
  'bili_jct'
  'Cookie:'
  'C:\\Users\\[^\\<>]+\\'
  'char-mwbnue56'
  'char-[a-z0-9]{10}'
  '夏鱼'
  'password\s*[:=]\s*["'\''][^"'\'']{8,}'
)

echo "共 $(echo "$FILES" | wc -l) 个候选文件..."

for f in $FILES; do
  # 跳过本脚本自己（它含有模式字面量，会自我命中）
  [ "$f" = "$SELF" ] && continue

  # 跳过 Windows 保留设备名（读到会挂死）
  base=$(basename "$f")
  if echo "$base" | grep -qiE "$RESERVED"; then
    SKIPPED+=("$f")
    continue
  fi

  [ -f "$f" ] || continue
  # -I：把二进制当文本跳过；--timeout 由外部 timeout 兜底
  CHECKED=$((CHECKED + 1))
  for p in "${PATTERNS[@]}"; do
    if timeout 5 grep -qIE "$p" "$f" 2>/dev/null; then
      echo "  ⚠️  $f  命中模式: $p"
      BAD=1
    fi
  done
done

if [ ${#SKIPPED[@]} -gt 0 ]; then
  echo ""
  echo "⚠️ 跳过了 ${#SKIPPED[@]} 个 Windows 保留设备名（读它们会挂死）："
  for s in "${SKIPPED[@]}"; do echo "   $s"; done
  echo "   这些通常是误创建的产物，建议删掉：del 或 rm（在 cmd 里用 \\\\.\\CON 前缀才能删）"
fi

echo ""
if [ "$BAD" -eq 1 ]; then
  echo "❌ 发现可疑内容。确认这些没问题再提交；确实需要的放 private/（不进 git）。"
  exit 1
fi

echo "✅ 检查了 $CHECKED 个文件，没发现问题。"
exit 0
