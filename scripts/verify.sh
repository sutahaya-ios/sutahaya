#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: scripts/verify.sh FAST|NORMAL|STRICT [options]

Options:
  --only-testing TARGET/TEST  関連テストを指定(複数回可)
  --no-tests                 NORMALで関連ユニットテストが無い場合に明示
  --skip-build               buildを省略
  --build                    FASTでもbuildを実行
  --xcodegen                 検証前にxcodegen generateを実行
  --dry-run                  コマンド表示だけで実行しない

Environment:
  TEST_DESTINATION  既定: platform=iOS Simulator,name=iPhone 17 Pro
EOF
}

if (($# == 0)); then usage >&2; exit 2; fi
if [[ "$1" == "-h" || "$1" == "--help" ]]; then usage; exit 0; fi

level="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
shift
case "$level" in FAST|NORMAL|STRICT) ;; *) echo "不明なレベル: $level" >&2; usage >&2; exit 2 ;; esac

only_tests=()
no_tests=false
skip_build=false
force_build=false
run_xcodegen=false
dry_run=false

while (($#)); do
  case "$1" in
    --only-testing)
      (($# >= 2)) || { echo "--only-testingに値が必要" >&2; exit 2; }
      only_tests+=("$2"); shift
      ;;
    --no-tests) no_tests=true ;;
    --skip-build) skip_build=true ;;
    --build) force_build=true ;;
    --xcodegen) run_xcodegen=true ;;
    --dry-run) dry_run=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "不明な引数: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ "$level" == NORMAL && ${#only_tests[@]} -eq 0 ]] && ! $no_tests; then
  echo "NORMALは --only-testing または --no-tests を指定する" >&2
  exit 2
fi
if $no_tests && ((${#only_tests[@]} > 0)); then
  echo "--no-testsと--only-testingは同時に使えない" >&2
  exit 2
fi

run() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  if ! $dry_run; then "$@"; fi
}

echo "== Verify: $level =="
run git diff --check

if $run_xcodegen; then
  run xcodegen generate
fi

developer_dir="/Applications/Xcode.app/Contents/Developer"
project="HayaosiApp.xcodeproj"
scheme="HayaosiApp"
test_destination="${TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"

if [[ "$level" == FAST && "$force_build" == false ]]; then
  skip_build=true
fi

if ! $skip_build; then
  run env "DEVELOPER_DIR=$developer_dir" xcodebuild -quiet \
    -project "$project" -scheme "$scheme" \
    -destination 'generic/platform=iOS Simulator' build
fi

test_command=(env "DEVELOPER_DIR=$developer_dir" xcodebuild -quiet
  -project "$project" -scheme "$scheme" -destination "$test_destination" test)

if [[ "$level" == NORMAL ]] && ((${#only_tests[@]} > 0)); then
  for test_name in "${only_tests[@]}"; do
    test_command+=("-only-testing:$test_name")
  done
  run "${test_command[@]}"
elif [[ "$level" == STRICT ]]; then
  for test_name in "${only_tests[@]}"; do
    test_command+=("-only-testing:$test_name")
  done
  run "${test_command[@]}"
fi

if [[ "$level" == STRICT ]]; then
  rules_changed="$(git status --short -- firestore.rules database.rules.json FirebaseRulesTests firebase.json package.json)"
  if [[ -n "$rules_changed" ]]; then
    if $dry_run; then
      run npm run test:firebase-rules
    elif [[ ! -x node_modules/.bin/firebase ]]; then
      echo "Firebase Rules差分あり: node_modulesが無いため npm ci 後に再実行が必要" >&2
      exit 2
    else
      run npm run test:firebase-rules
    fi
  fi
  echo "注意: 通信対戦・実機・本番Firebaseは自動検証できないため、未検証項目を報告する"
fi

echo "== Verify complete: $level =="
