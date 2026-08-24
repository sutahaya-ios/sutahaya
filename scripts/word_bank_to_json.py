#!/usr/bin/env python3
"""word_bank.xlsx から単語JSONを生成する。

    python3 scripts/word_bank_to_json.py            # 検証だけして差分を表示
    python3 scripts/word_bank_to_json.py --write    # JSONへ書き込む

id が空欄の行には、そのシートの最大番号の続きを自動で振る。
1件でも入力ミスがあれば、何も書き込まずに全件を報告して終了する。
"""

import argparse
import json
import sys
from pathlib import Path

from openpyxl import load_workbook

ROOT = Path(__file__).resolve().parent.parent
WORKBOOK = ROOT / "word_bank.xlsx"
RESOURCES = ROOT / "HayaosiApp" / "Resources"

# シート名 → (出力ファイル名, IDの接頭辞)
SHEETS = {
    "中学英単語": ("junior_high.json", "jh_"),
    "高校英単語": ("high_school.json", "hs_"),
    "TOEIC単語": ("toeic.json", "tc_"),
}
# シート名 → JSONの category 値。アプリが category を読まなくなったら --no-category で外す
CATEGORIES = {"中学英単語": "junior_high", "高校英単語": "high_school", "TOEIC単語": "toeic"}

COLUMNS = ["id", "word", "meaning", "pos", "difficulty"]
VALID_POS = {"動詞", "名詞", "形容詞"}
ID_DIGITS = 4


def read_sheet(worksheet):
    """見出し行を除いた各行を、空行を飛ばして辞書で返す。"""
    rows = []
    for number, values in enumerate(worksheet.iter_rows(min_row=2, values_only=True), start=2):
        cells = [v.strip() if isinstance(v, str) else v for v in values[: len(COLUMNS)]]
        if all(v is None or v == "" for v in cells):
            continue
        rows.append({"row": number, **dict(zip(COLUMNS, cells))})
    return rows


def validate(sheet_name, rows, prefix):
    """入力ミスを漏れなく集める。1件でも返れば呼び出し側が中止する。"""
    problems = []
    seen_words, seen_ids = {}, {}

    for entry in rows:
        where = f"{sheet_name} {entry['row']}行目"

        for column in ("word", "meaning", "pos", "difficulty"):
            if entry[column] in (None, ""):
                problems.append(f"{where}: {column} が空")

        word = entry["word"]
        if isinstance(word, str) and word:
            key = word.lower()
            if key in seen_words:
                problems.append(f"{where}: 「{word}」が{seen_words[key]}行目と重複")
            seen_words[key] = entry["row"]

        if entry["pos"] not in VALID_POS and entry["pos"] not in (None, ""):
            problems.append(f"{where}: 品詞「{entry['pos']}」は 動詞/名詞/形容詞 のいずれかにする")

        difficulty = entry["difficulty"]
        if difficulty not in (None, "") and (not isinstance(difficulty, int) or not 1 <= difficulty <= 5):
            problems.append(f"{where}: 難易度「{difficulty}」は1〜5の整数にする")

        identifier = entry["id"]
        if identifier in (None, ""):
            continue
        if not (isinstance(identifier, str) and identifier.startswith(prefix)):
            problems.append(f"{where}: id「{identifier}」の接頭辞が {prefix} でない")
        elif identifier in seen_ids:
            problems.append(f"{where}: id「{identifier}」が{seen_ids[identifier]}行目と重複")
        seen_ids[identifier] = entry["row"]

    return problems


def assign_ids(rows, prefix):
    """空欄のidへ、既存の最大番号の続きを振る。振った分を一覧で返す。"""
    numbers = [
        int(entry["id"][len(prefix):])
        for entry in rows
        if isinstance(entry["id"], str) and entry["id"].startswith(prefix)
    ]
    next_number = max(numbers, default=0) + 1

    assigned = []
    for entry in rows:
        if entry["id"] not in (None, ""):
            continue
        entry["id"] = f"{prefix}{next_number:0{ID_DIGITS}d}"
        assigned.append((entry["id"], entry["word"]))
        next_number += 1
    return assigned


def build_entries(rows, category):
    entries = []
    for row in rows:
        entry = {"id": row["id"], "word": row["word"], "meaning": row["meaning"], "pos": row["pos"]}
        if category:
            entry["category"] = category
        entry["difficulty"] = row["difficulty"]
        entries.append(entry)
    return entries


def main():
    parser = argparse.ArgumentParser(description="word_bank.xlsx を単語JSONへ変換する")
    parser.add_argument("--write", action="store_true", help="JSONへ書き込む(既定は確認のみ)")
    parser.add_argument("--no-category", action="store_true",
                        help="category を出力しない(アプリ側の対応後に使う)")
    parser.add_argument("--workbook", type=Path, default=WORKBOOK)
    args = parser.parse_args()

    if not args.workbook.exists():
        sys.exit(f"見つからない: {args.workbook}")

    workbook = load_workbook(args.workbook, data_only=True)
    missing = [name for name in SHEETS if name not in workbook.sheetnames]
    if missing:
        sys.exit("シートが足りない: " + " / ".join(missing))

    problems, results = [], {}
    for sheet_name, (filename, prefix) in SHEETS.items():
        rows = read_sheet(workbook[sheet_name])
        found = validate(sheet_name, rows, prefix)
        problems.extend(found)
        if not found:
            results[sheet_name] = (filename, prefix, rows)

    if problems:
        print(f"入力を直してから実行する({len(problems)}件):\n", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        sys.exit(1)

    changed = False
    for sheet_name, (filename, prefix, rows) in results.items():
        assigned = assign_ids(rows, prefix)
        category = None if args.no_category else CATEGORIES[sheet_name]
        text = json.dumps(build_entries(rows, category), ensure_ascii=False, indent=2) + "\n"

        path = RESOURCES / filename
        current = path.read_text(encoding="utf-8") if path.exists() else ""
        status = "変更なし" if text == current else "更新あり"
        if text != current:
            changed = True

        print(f"{sheet_name} → {filename}: {len(rows)}語 / 新規{len(assigned)}語 / {status}")
        for identifier, word in assigned:
            print(f"    + {identifier}  {word}")

        if args.write:
            path.write_text(text, encoding="utf-8")

    if not changed:
        return
    if args.write:
        print("\n書き込んだ。QuestionSeeder.dataVersion を +1 すること(このスクリプトでは変更しない)")
    else:
        print("\n確認のみ。反映するには --write を付けて実行する")


if __name__ == "__main__":
    main()
