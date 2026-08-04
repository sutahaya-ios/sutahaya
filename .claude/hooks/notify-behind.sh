#!/bin/bash
# セッション開始時にリモートを取得し、未取得のコミットがあれば知らせる(SessionStartフック)。
# fetch だけなので手元のファイルは書き換わらない。取り込み(pull)は人間が判断する。
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

git fetch --quiet 2>/dev/null

# 上流ブランチが無い/オフラインなら黙って終了
behind=$(git rev-list --count HEAD..@{u} 2>/dev/null) || exit 0
[ "${behind:-0}" -gt 0 ] || exit 0

message="リモートに未取得のコミットが ${behind} 件あります。作業前に \`git pull --rebase && xcodegen generate\` を実行してください。"
jq -nc --arg m "$message" \
  '{systemMessage: $m, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $m}}'
