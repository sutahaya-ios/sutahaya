#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fetch_origin=false
allow_dirty=false

usage() {
  cat <<'EOF'
Usage: scripts/preflight.sh [--fetch] [--allow-dirty]

push / pull / merge / rebase / branch操作 / origin同期、競合可能性が高い共有ファイル、
Firebase本番・Rules・project.yml・Signing等のSTRICT作業だけで使用する。

  --fetch        originを更新して確認する。通常は現在のorigin/mainで確認する
  --allow-dirty  未commit差分を警告に留め、終了コード2にしない
EOF
}

while (($#)); do
  case "$1" in
    --fetch) fetch_origin=true ;;
    --allow-dirty) allow_dirty=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "不明な引数: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

echo "== Preflight =="
echo "root: $ROOT_DIR"
echo "branch: $(git branch --show-current)"

if $fetch_origin; then
  echo "origin: fetch中..."
  if ! git fetch origin --quiet; then
    echo "判定: git fetch originに失敗。認証または通信を確認し、作業開始前に解決する" >&2
    exit 1
  fi
else
  echo "origin: fetch省略(必要なら--fetch)"
fi

if ! git rev-parse --verify --quiet origin/main >/dev/null; then
  echo "判定: origin/mainが見つからない" >&2
  exit 1
fi

read -r ahead behind < <(git rev-list --left-right --count HEAD...origin/main)
echo "origin/mainとの差: ahead=$ahead behind=$behind"

dirty=false
if [[ -n "$(git status --porcelain)" ]]; then
  dirty=true
  echo "作業ツリー: 差分あり"
  git status --short
else
  echo "作業ツリー: clean"
fi

echo "STATUS作業中宣言:"
declarations="$({
  awk '
    /^## 作業中宣言/ { in_section=1; next }
    in_section && /^---$/ { exit }
    in_section && /^\|/ && $0 !~ /^\|---/ && $0 !~ /^\| 担当 / { print }
  ' STATUS.md
} || true)"
if [[ -n "$declarations" ]]; then
  printf '%s\n' "$declarations"
else
  echo "  なし"
fi

local_files="$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)"

base="$(git merge-base HEAD origin/main)"
if ((ahead > 0)); then
  local_files="$({ printf '%s\n' "$local_files"; git diff --name-only "$base"..HEAD; } | sed '/^$/d' | sort -u)"
fi
upstream_files="$(git diff --name-only "$base"..origin/main | sort -u)"
overlap="$(comm -12 <(printf '%s\n' "$local_files") <(printf '%s\n' "$upstream_files"))"

if [[ -n "$overlap" ]]; then
  echo "競合可能性: 同じファイルをローカルとorigin/mainが変更"
  while IFS= read -r file; do
    [[ -n "$file" ]] && printf '  %s\n' "$file"
  done <<< "$overlap"
else
  echo "競合可能性: ファイル重複なし"
fi

needs_attention=false
if ((behind > 0)) || [[ -n "$overlap" ]]; then
  needs_attention=true
fi
if $dirty && ! $allow_dirty; then
  needs_attention=true
fi

if $needs_attention; then
  echo "判定: 要確認。未commit差分があるときはpullせず、内容を確認する"
  exit 2
fi

echo "判定: 作業開始可"
