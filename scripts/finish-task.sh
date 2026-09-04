#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: scripts/finish-task.sh [--verify FAST|NORMAL|STRICT] [verify options] [--message TEXT]

commit準備・push前確認・他開発者への引き渡し・大規模タスク・ユーザー指定時だけ使う。
--verify指定時だけverify.shを実行し、同じ検証を重複させない。
verify.shと同じ --only-testing / --no-tests / --skip-build / --build / --xcodegen / --dry-run を渡せる。
Git差分と推奨コマンドを表示するだけで、add / commit / pushは実行しない。
EOF
}

if (($# > 0)) && [[ "$1" == "-h" || "$1" == "--help" ]]; then usage; exit 0; fi

run_verify=false
verify_args=()
message=""

while (($#)); do
  case "$1" in
    --verify)
      (($# >= 2)) || { echo "--verifyにFAST/NORMAL/STRICTが必要" >&2; exit 2; }
      run_verify=true
      verify_args+=("$2"); shift
      ;;
    --message)
      (($# >= 2)) || { echo "--messageに値が必要" >&2; exit 2; }
      message="$2"; shift
      ;;
    --only-testing)
      (($# >= 2)) || { echo "--only-testingに値が必要" >&2; exit 2; }
      verify_args+=("$1" "$2"); shift
      ;;
    --no-tests|--skip-build|--build|--xcodegen|--dry-run)
      verify_args+=("$1")
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "不明な引数: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if $run_verify; then
  scripts/verify.sh "${verify_args[@]}"
elif ((${#verify_args[@]} > 0)); then
  echo "verifyオプションを使う場合は先に --verify FAST|NORMAL|STRICT を指定する" >&2
  exit 2
fi

mapfile_compat() {
  while IFS= read -r line; do
    [[ -n "$line" ]] && changed_files+=("$line")
  done
}

changed_files=()
mapfile_compat < <({
  git diff --name-only HEAD
  git ls-files --others --exclude-standard
} | sort -u)

if ((${#changed_files[@]} == 0)); then
  echo "Git差分はありません"
  exit 0
fi

echo "== 変更ファイル =="
printf '  %s\n' "${changed_files[@]}"
echo "== diff stat =="
git diff --stat HEAD
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  line_count="$(wc -l < "$file" | tr -d ' ')"
  printf ' %s | %s + (untracked)\n' "$file" "$line_count"
done < <(git ls-files --others --exclude-standard | sort)

if [[ -z "$message" ]]; then
  docs_only=true
  for file in "${changed_files[@]}"; do
    case "$file" in
      *.md|scripts/*.sh) ;;
      *) docs_only=false; break ;;
    esac
  done
  if $docs_only; then
    message="docs: 開発フローの検証手順を高速化"
  else
    message="fix: 変更内容を要約してください"
  fi
fi

echo "== 推奨commit message =="
echo "$message"
echo "== 人間が確認後に実行するコマンド =="
printf 'git add --'
printf ' %q' "${changed_files[@]}"
printf '\n'
escaped_message="$(printf '%s' "$message" | sed "s/'/'\\\\''/g")"
printf "git commit -m '%s'\n" "$escaped_message"
echo 'git pull --rebase origin main'
echo 'xcodegen generate'
echo 'git push origin main'
