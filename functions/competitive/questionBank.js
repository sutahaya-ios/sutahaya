const { QUESTION_COUNT } = require("./constants");

// Phase A-2だけで20問完走を検証するServer-only fixture。
// Client bundleやpublic projectionへcorrectChoiceIndex/canonicalIdを配信しない。
const TEST_QUESTION_BANK = Object.freeze([
  { canonicalId: "core-001", prompt: "apple の意味は？", choices: ["りんご", "机", "雲", "走る"], correctChoiceIndex: 0 },
  { canonicalId: "core-002", prompt: "book の意味は？", choices: ["川", "本", "鳥", "青い"], correctChoiceIndex: 1 },
  { canonicalId: "core-003", prompt: "cat の意味は？", choices: ["犬", "魚", "猫", "山"], correctChoiceIndex: 2 },
  { canonicalId: "core-004", prompt: "run の意味は？", choices: ["読む", "眠る", "作る", "走る"], correctChoiceIndex: 3 },
  { canonicalId: "core-005", prompt: "water の意味は？", choices: ["水", "火", "土", "風"], correctChoiceIndex: 0 },
  { canonicalId: "core-006", prompt: "school の意味は？", choices: ["駅", "学校", "病院", "店"], correctChoiceIndex: 1 },
  { canonicalId: "core-007", prompt: "green の意味は？", choices: ["赤", "白", "緑", "黒"], correctChoiceIndex: 2 },
  { canonicalId: "core-008", prompt: "speak の意味は？", choices: ["聞く", "書く", "見る", "話す"], correctChoiceIndex: 3 },
  { canonicalId: "core-009", prompt: "morning の意味は？", choices: ["朝", "昼", "夕方", "夜"], correctChoiceIndex: 0 },
  { canonicalId: "core-010", prompt: "friend の意味は？", choices: ["先生", "友達", "家族", "客"], correctChoiceIndex: 1 },
  { canonicalId: "core-011", prompt: "large の意味は？", choices: ["速い", "短い", "大きい", "軽い"], correctChoiceIndex: 2 },
  { canonicalId: "core-012", prompt: "write の意味は？", choices: ["話す", "泳ぐ", "歌う", "書く"], correctChoiceIndex: 3 },
  { canonicalId: "core-013", prompt: "music の意味は？", choices: ["音楽", "絵", "映画", "写真"], correctChoiceIndex: 0 },
  { canonicalId: "core-014", prompt: "window の意味は？", choices: ["床", "窓", "壁", "屋根"], correctChoiceIndex: 1 },
  { canonicalId: "core-015", prompt: "happy の意味は？", choices: ["眠い", "悲しい", "幸せな", "静かな"], correctChoiceIndex: 2 },
  { canonicalId: "core-016", prompt: "eat の意味は？", choices: ["飲む", "歩く", "買う", "食べる"], correctChoiceIndex: 3 },
  { canonicalId: "core-017", prompt: "river の意味は？", choices: ["川", "海", "湖", "池"], correctChoiceIndex: 0 },
  { canonicalId: "core-018", prompt: "teacher の意味は？", choices: ["生徒", "先生", "医師", "店員"], correctChoiceIndex: 1 },
  { canonicalId: "core-019", prompt: "fast の意味は？", choices: ["遅い", "高い", "速い", "遠い"], correctChoiceIndex: 2 },
  { canonicalId: "core-020", prompt: "sleep の意味は？", choices: ["起きる", "働く", "遊ぶ", "眠る"], correctChoiceIndex: 3 },
]);

if (TEST_QUESTION_BANK.length !== QUESTION_COUNT) {
  throw new Error("Competitive test question bank must contain exactly 20 questions");
}

module.exports = { TEST_QUESTION_BANK };
