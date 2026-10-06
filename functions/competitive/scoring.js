const CORRECT_POINTS = Object.freeze([20, 10, 5]);
const LATER_CORRECT_POINT = 1;
const WRONG_POINT = -10;

function canonicalAnswers(answers, participantOrder, deadlineEpochMs) {
  const slot = new Map(participantOrder.map((uid, index) => [uid, index]));
  return Object.values(answers || {})
    .filter((answer) => slot.has(answer.uid)
      && Number.isFinite(answer.acceptedAtEpochMs)
      && answer.acceptedAtEpochMs <= deadlineEpochMs)
    .sort((left, right) => {
      if (left.acceptedAtEpochMs === right.acceptedAtEpochMs) {
        return slot.get(left.uid) - slot.get(right.uid);
      }
      return left.acceptedAtEpochMs - right.acceptedAtEpochMs;
    });
}

function scoreQuestion({ answers, participantOrder, deadlineEpochMs, correctAnswerId }) {
  const orderedAnswers = canonicalAnswers(answers, participantOrder, deadlineEpochMs);
  const scoreDeltas = Object.fromEntries(participantOrder.map((uid) => [uid, 0]));
  const correctUIDs = [];
  const wrongUIDs = [];

  for (const answer of orderedAnswers) {
    if (answer.answerId === correctAnswerId) {
      const correctRank = correctUIDs.length;
      correctUIDs.push(answer.uid);
      scoreDeltas[answer.uid] = CORRECT_POINTS[correctRank] ?? LATER_CORRECT_POINT;
    } else {
      wrongUIDs.push(answer.uid);
      scoreDeltas[answer.uid] = WRONG_POINT;
    }
  }

  const answered = new Set(orderedAnswers.map((answer) => answer.uid));
  return {
    answerOrder: orderedAnswers.map((answer) => answer.uid),
    answerEventIds: Object.fromEntries(
      orderedAnswers.map((answer) => [answer.uid, answer.eventId])
    ),
    correctUIDs,
    wrongUIDs,
    unansweredUIDs: participantOrder.filter((uid) => !answered.has(uid)),
    scoreDeltas,
  };
}

function rankedScores(scores, participantOrder) {
  const ordered = participantOrder
    .map((uid, slot) => ({ uid, slot, score: scores[uid] || 0 }))
    .sort((left, right) => right.score - left.score || left.slot - right.slot);
  return ordered.map((entry) => ({
    uid: entry.uid,
    score: entry.score,
    rank: ordered.filter((other) => other.score > entry.score).length + 1,
  }));
}

module.exports = {
  LATER_CORRECT_POINT,
  WRONG_POINT,
  canonicalAnswers,
  rankedScores,
  scoreQuestion,
};
