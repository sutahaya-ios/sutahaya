#!/bin/bash
# STATUS.md の行数を監視し、上限(既定150行)を超えたらアーカイブ移動を促す。
# SessionStart と PostToolUse(Edit/Write後)の両方から呼ばれる($1=イベント名)。
# 自動では移動しない:どこまでが「古い履歴」かは文脈判断が要るため、
# 機械は検知だけを行い、移動はエージェント/人間が判断して行う。
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
EVENT="${1:-PostToolUse}"
LIMIT="${STATUS_LINE_LIMIT:-150}"
FILE="STATUS.md"

# PostToolUse では stdin のJSONに編集対象パスが入っている。STATUS.md 以外の編集なら黙って終了
if [ ! -t 0 ]; then
  input=$(cat)
  path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  if [ -n "$path" ] && [ "$(basename "$path")" != "STATUS.md" ]; then
    exit 0
  fi
fi

[ -f "$FILE" ] || exit 0
lines=$(wc -l < "$FILE" | tr -d ' ')
[ "$lines" -le "$LIMIT" ] && exit 0

msg="STATUS.md が ${lines}行で上限${LIMIT}行を超えています。「最新更新」の古い日付の項目から STATUS_ARCHIVE.md へ移してください(現在フェーズ・作業中宣言・次のタスク・決定事項メモは移動対象外)。"
jq -nc --arg m "$msg" --arg e "$EVENT" \
  '{systemMessage: $m, hookSpecificOutput: {hookEventName: $e, additionalContext: $m}}'
