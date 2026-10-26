const { createHash } = require("node:crypto");
const {
  CONFIG_VERSION,
  PARTICIPANT_KIND,
  PARTICIPANT_STATUS,
  PHASE,
  PROTOCOL_VERSION,
  SERVER_VERSION,
  SETTLEMENT_VERSION,
} = require("./constants");
const { rankedScores, scoreQuestion } = require("./scoring");

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function intentFingerprint(envelope, uid) {
  return createHash("sha256").update(JSON.stringify({
    uid,
    type: envelope.type,
    protocolVersion: envelope.protocolVersion,
    sessionId: envelope.sessionId,
    sessionEpoch: envelope.sessionEpoch,
    matchId: envelope.matchId,
    questionId: envelope.questionId || null,
    stateVersion: envelope.stateVersion ?? null,
    payload: envelope.payload,
  })).digest("hex");
}

function publicParticipants(privateState) {
  const currentAnswers = acceptedAnswersForCurrentQuestion(privateState);
  const terminal = [
    PHASE.MATCH_FINISHED,
    PHASE.SETTLEMENT_PENDING,
    PHASE.SETTLED,
  ].includes(privateState.phase);
  const visibleUIDs = terminal
    ? privateState.participantOrder
    : activeParticipantUIDs(privateState);
  return Object.fromEntries(visibleUIDs.map((uid) => {
    const participant = privateState.participants[uid];
    return [uid, {
      uid,
      slot: participant.slot,
      kind: participant.kind || PARTICIPANT_KIND.HUMAN,
      displayName: participant.displayName,
      joined: participant.joined ?? false,
      ready: participant.ready ?? false,
      active: participant.active,
      forfeited: participant.forfeited,
      status: participant.status || PARTICIPANT_STATUS.CONNECTED,
      disconnectedAtEpochMs: participant.disconnectedAtEpochMs ?? null,
      reconnectDeadlineEpochMs: participant.reconnectDeadlineEpochMs ?? null,
      answerQuestionId: privateState.currentQuestion?.questionId ?? null,
      answered: Boolean(currentAnswers[uid]),
      score: privateState.scores[uid] || 0,
    }];
  }));
}

function publicQuestion(privateState) {
  const question = privateState.currentQuestion;
  if (!question) return null;
  const projection = {
    questionId: question.questionId,
    questionIndex: privateState.currentQuestionIndex,
    prompt: question.prompt,
    choices: question.choices,
    openedAtEpochMs: question.openedAtEpochMs,
    deadlineEpochMs: question.deadlineEpochMs,
  };
  const nextServerActionAtEpochMs = nextPendingNPCActionEpochMs(privateState);
  if (privateState.phase === PHASE.QUESTION_OPEN
      && Number.isFinite(nextServerActionAtEpochMs)) {
    // Clientはこの時刻にServer reconcileを起こすだけで、answered自体はServer投影を正とする。
    projection.nextServerActionAtEpochMs = nextServerActionAtEpochMs;
  }
  if (privateState.phase === PHASE.QUESTION_RESULT) {
    projection.correctAnswerId = question.correctAnswerId;
  }
  return projection;
}

function publicQuestionResult(privateState) {
  const result = privateState.currentQuestion?.result;
  if (!result) return null;
  const liveUIDs = new Set(activeParticipantUIDs(privateState));
  const liveValues = (values) => (values || []).filter((uid) => liveUIDs.has(uid));
  const liveScores = (values) => Object.fromEntries(
    Object.entries(values || {}).filter(([uid]) => liveUIDs.has(uid))
  );
  return {
    questionId: result.questionId,
    questionIndex: result.questionIndex,
    closeReason: result.closeReason,
    answerOrder: liveValues(result.answerOrder),
    correctUIDs: liveValues(result.correctUIDs),
    wrongUIDs: liveValues(result.wrongUIDs),
    unansweredUIDs: liveValues(result.unansweredUIDs),
    scoreDeltas: liveScores(result.scoreDeltas),
    cumulativeScores: liveScores(result.cumulativeScores),
    correctAnswerId: result.correctAnswerId,
    closedAtEpochMs: result.closedAtEpochMs,
  };
}

function syncPublic(match) {
  const state = match.private;
  match.public = {
    matchId: state.matchId,
    protocolVersion: state.protocolVersion,
    configVersion: state.configVersion,
    phase: state.phase,
    stateVersion: state.stateVersion,
    serverSequence: state.serverSequence,
    forfeitedUIDs: state.participantOrder.filter(
      (uid) => state.participants[uid]?.forfeited
    ),
    participants: publicParticipants(state),
    currentQuestionIndex: state.currentQuestionIndex,
    currentQuestion: publicQuestion(state),
    questionResult: publicQuestionResult(state),
    countdownEndsAtEpochMs: state.countdownEndsAtEpochMs ?? null,
    resultEndsAtEpochMs: state.resultEndsAtEpochMs ?? null,
    finalResult: state.matchResult || null,
    settlement: state.settlement
      ? {
        status: state.settlement.status,
        settlementId: state.settlement.settlementId,
        playerResults: state.settlement.publicPlayerResults || {},
      }
      : null,
  };
}

function activeParticipantUIDs(privateState) {
  return privateState.participantOrder.filter(
    (uid) => privateState.participants[uid]?.active
  );
}

function acceptedAnswersForCurrentQuestion(privateState) {
  const question = privateState.currentQuestion;
  if (!question) return {};
  const inboxAnswers = privateState.answerInbox?.[question.questionId];
  const candidates = inboxAnswers || question.answers || {};
  return Object.fromEntries(Object.entries(candidates).filter(([uid, answer]) => (
    privateState.participants?.[uid]
      && !privateState.participants[uid].scoreFrozen
      && answer?.uid === uid
      && answer.questionId === question.questionId
      && answer.status !== "REJECTED"
      && Number.isFinite(answer.acceptedAtEpochMs)
      && answer.acceptedAtEpochMs <= question.deadlineEpochMs
  )));
}

function allActivePlayersAnswered(privateState) {
  const answers = acceptedAnswersForCurrentQuestion(privateState);
  return activeParticipantUIDs(privateState).every((uid) => Boolean(answers[uid]));
}

function makeAck(envelope, status, privateState, rejectionCode = null, retryable = false) {
  return {
    intentId: envelope.intentId,
    status,
    serverSequence: privateState.serverSequence,
    publicStateVersion: privateState.stateVersion,
    rejectionCode,
    retryable,
  };
}

function recordOutcome(match, envelope, uid, {
  accepted,
  rejectionCode = null,
  retryable = false,
  stateChanged = false,
  stateBefore,
  authorityTimestamp,
}) {
  const state = match.private;
  state.intentResults ||= {};
  state.audit ||= {};
  state.serverSequence += 1;
  if (stateChanged) state.stateVersion += 1;
  const ack = makeAck(
    envelope,
    accepted ? "ACCEPTED" : "REJECTED",
    state,
    rejectionCode,
    retryable
  );
  state.intentResults[envelope.intentId] = {
    fingerprint: intentFingerprint(envelope, uid),
    ack,
  };
  const audit = {
    eventId: envelope.intentId,
    eventType: envelope.type,
    matchId: state.matchId,
    serverSequence: state.serverSequence,
    sessionId: envelope.sessionId,
    sessionEpoch: envelope.sessionEpoch,
    playerUID: uid,
    stateBefore,
    stateAfter: state.phase,
    questionId: envelope.questionId || state.currentQuestion?.questionId || null,
    accepted,
    rejectionCode,
    authorityTimestamp,
    protocolVersion: state.protocolVersion,
    serverVersion: state.serverVersion,
    configVersion: state.configVersion,
  };
  if (state.currentQuestion?.result?.closedAtEpochMs === authorityTimestamp) {
    audit.questionResult = {
      answerOrder: state.currentQuestion.result.answerOrder,
      scoreDeltas: state.currentQuestion.result.scoreDeltas,
    };
  }
  state.audit[String(state.serverSequence)] = audit;
  syncPublic(match);
  return ack;
}

function existingIntentOutcome(match, envelope, uid) {
  const saved = match.private.intentResults?.[envelope.intentId];
  if (!saved) return null;
  if (saved.fingerprint !== intentFingerprint(envelope, uid)) {
    return {
      intentId: envelope.intentId,
      status: "REJECTED",
      serverSequence: match.private.serverSequence,
      publicStateVersion: match.private.stateVersion,
      rejectionCode: "INTENT_REPLAY_MISMATCH",
      retryable: false,
    };
  }
  return {
    ...saved.ack,
    status: "DUPLICATE",
    originalStatus: saved.ack.status,
  };
}

function reject(match, envelope, uid, code, authorityTimestamp, stateBefore) {
  return recordOutcome(match, envelope, uid, {
    accepted: false,
    rejectionCode: code,
    stateChanged: false,
    stateBefore,
    authorityTimestamp,
  });
}

function validateParticipant(privateState, envelope, uid) {
  const participant = privateState.participants?.[uid];
  if (!participant) return { code: "NOT_MATCH_MEMBER" };
  if (participant.kind === PARTICIPANT_KIND.NPC) return { code: "NOT_HUMAN_PLAYER" };
  if (participant.sessionId !== envelope.sessionId
      || participant.sessionEpoch !== envelope.sessionEpoch) {
    return { code: "STALE_SESSION_EPOCH" };
  }
  return { participant };
}

function npcPlans(privateState, questionIndex, question) {
  const reactionBaseMs = Number.isFinite(privateState.config?.npcSkillInput?.reactionBaseMs)
    ? privateState.config.npcSkillInput.reactionBaseMs
    : 250;
  const answerRemainingMs = privateState.config?.npcSkillInput?.answerRemainingMs;
  return Object.fromEntries(privateState.participantOrder.flatMap((uid) => {
    const participant = privateState.participants[uid];
    if (participant?.kind !== PARTICIPANT_KIND.NPC || !participant.active) return [];
    const configuredAccuracy = privateState.config?.npcSkillInput?.accuracyPermille;
    let answerId;
    if (Number.isFinite(configuredAccuracy)) {
      const attemptRoll = (questionIndex * 173 + participant.slot * 271) % 1_000;
      const attemptPermille = privateState.config?.npcSkillInput?.attemptPermille ?? 920;
      if (attemptRoll >= attemptPermille) return [];
      answerId = attemptRoll < configuredAccuracy
        ? question.correctAnswerId
        : question.choices.find((choice) => choice.answerId !== question.correctAnswerId).answerId;
    } else {
      // Phase Cの固定test inputとの後方互換。
      const behavior = (questionIndex + participant.slot) % 3;
      if (behavior === 2) return [];
      answerId = behavior === 0
        ? question.correctAnswerId
        : question.choices.find((choice) => choice.answerId !== question.correctAnswerId).answerId;
    }
    const acceptedAtEpochMs = Number.isFinite(answerRemainingMs)
      ? question.deadlineEpochMs
        - answerRemainingMs
        + (participant.slot * 25)
        + ((questionIndex % 5) * 20)
      : question.openedAtEpochMs
        + reactionBaseMs
        + (participant.slot * 25)
        + ((questionIndex % 5) * 20);
    return [[uid, {
      uid,
      eventId: `npc-answer-${question.questionId}-${uid}`,
      questionId: question.questionId,
      answerId,
      acceptedAtEpochMs,
      status: "ACCEPTED",
      source: "SERVER_NPC",
    }]];
  }));
}

function nextPendingNPCActionEpochMs(privateState) {
  const question = privateState.currentQuestion;
  if (!question) return null;
  const currentAnswers = acceptedAnswersForCurrentQuestion(privateState);
  const pendingTimes = Object.entries(question.npcPlans || {}).flatMap(([uid, plan]) => (
    privateState.participants[uid]?.active
      && !currentAnswers[uid]
      && Number.isFinite(plan.acceptedAtEpochMs)
      ? [plan.acceptedAtEpochMs]
      : []
  ));
  return pendingTimes.length > 0 ? Math.min(...pendingTimes) : null;
}

function applyDueNPCActions(privateState, nowEpochMs, limit = 1) {
  const question = privateState.currentQuestion;
  if (privateState.phase !== PHASE.QUESTION_OPEN || !question) return false;
  let changed = false;
  let applied = 0;
  privateState.answerInbox ||= {};
  privateState.answerInbox[question.questionId] ||= {};
  question.answers ||= {};
  const orderedPlans = Object.entries(question.npcPlans || {}).sort((left, right) => (
    left[1].acceptedAtEpochMs - right[1].acceptedAtEpochMs
      || left[0].localeCompare(right[0])
  ));
  for (const [uid, plan] of orderedPlans) {
    if (plan.acceptedAtEpochMs > nowEpochMs
        || plan.acceptedAtEpochMs > question.deadlineEpochMs
        || privateState.answerInbox[question.questionId][uid]) continue;
    privateState.answerInbox[question.questionId][uid] = plan;
    question.answers[uid] = plan;
    changed = true;
    applied += 1;
    if (applied >= limit) break;
  }
  return changed;
}

function forfeitParticipant(privateState, participant, nowEpochMs, reason) {
  if (!participant.active || participant.forfeited) return false;
  participant.active = false;
  participant.forfeited = true;
  participant.scoreFrozen = true;
  participant.status = PARTICIPANT_STATUS.FORFEITED;
  participant.forfeitReason = reason;
  participant.forfeitedAtEpochMs = nowEpochMs;
  delete participant.joined;
  delete participant.ready;
  delete participant.assignmentTicket;
  delete participant.presenceAuthorityEventKey;
  delete participant.disconnectedAtEpochMs;
  delete participant.reconnectDeadlineEpochMs;
  return true;
}

function expireReconnectGrace(privateState, nowEpochMs) {
  let changed = false;
  for (const uid of privateState.participantOrder) {
    const participant = privateState.participants[uid];
    if (participant?.status !== PARTICIPANT_STATUS.RECONNECTING
        || !Number.isFinite(participant.reconnectDeadlineEpochMs)
        || nowEpochMs < participant.reconnectDeadlineEpochMs) continue;
    changed = forfeitParticipant(privateState, participant, nowEpochMs, "RECONNECT_TIMEOUT")
      || changed;
  }
  return changed;
}

function openQuestion(privateState, questionIndex, nowEpochMs, nextStateVersion) {
  const source = privateState.questionInstances[questionIndex];
  if (!source) throw new Error("QUESTION_FIXTURE_MISSING");
  privateState.phase = PHASE.QUESTION_OPEN;
  privateState.phaseOpenedStateVersion = nextStateVersion;
  privateState.currentQuestionIndex = questionIndex;
  privateState.currentQuestion = {
    canonicalId: source.canonicalId,
    questionId: source.questionId,
    prompt: source.prompt,
    choices: source.choices,
    correctAnswerId: source.correctAnswerId,
    openedAtEpochMs: nowEpochMs,
    deadlineEpochMs: nowEpochMs + privateState.config.questionDurationMs,
    openedStateVersion: nextStateVersion,
    answers: {},
    result: null,
  };
  privateState.currentQuestion.npcPlans = npcPlans(
    privateState,
    questionIndex,
    privateState.currentQuestion
  );
  privateState.resultEndsAtEpochMs = null;
}

function closeQuestion(privateState, nowEpochMs, closeReason) {
  const question = privateState.currentQuestion;
  const acceptedAnswers = acceptedAnswersForCurrentQuestion(privateState);
  question.answers = acceptedAnswers;
  const scoring = scoreQuestion({
    answers: acceptedAnswers,
    participantOrder: activeParticipantUIDs(privateState),
    deadlineEpochMs: question.deadlineEpochMs,
    correctAnswerId: question.correctAnswerId,
  });
  const cumulativeScores = { ...privateState.scores };
  for (const uid of privateState.participantOrder) {
    cumulativeScores[uid] = (cumulativeScores[uid] || 0) + (scoring.scoreDeltas[uid] || 0);
  }
  privateState.scores = cumulativeScores;
  question.result = {
    questionId: question.questionId,
    questionIndex: privateState.currentQuestionIndex,
    closeReason,
    closedAtEpochMs: nowEpochMs,
    correctAnswerId: question.correctAnswerId,
    ...scoring,
    cumulativeScores,
  };
  privateState.phase = PHASE.QUESTION_RESULT;
  privateState.resultEndsAtEpochMs = nowEpochMs + privateState.config.resultDurationMs;
}

function finishMatch(privateState, nowEpochMs) {
  const activeUIDs = privateState.participantOrder.filter(
    (uid) => !privateState.participants[uid].forfeited
  );
  const forfeitedUIDs = privateState.participantOrder.filter(
    (uid) => privateState.participants[uid].forfeited
  );
  const activeRanked = rankedScores(privateState.scores, activeUIDs);
  const forfeitedRank = activeRanked.length + 1;
  const ranked = [
    ...activeRanked,
    ...forfeitedUIDs.map((uid) => ({
      uid,
      score: privateState.scores[uid] || 0,
      rank: forfeitedRank,
    })),
  ];
  privateState.phase = PHASE.MATCH_FINISHED;
  privateState.matchResult = {
    matchId: privateState.matchId,
    outcome: "COMPLETED",
    finalScores: Object.fromEntries(ranked.map((entry) => [entry.uid, entry.score])),
    ranks: Object.fromEntries(ranked.map((entry) => [entry.uid, entry.rank])),
    winnerUIDs: activeRanked.filter((entry) => entry.rank === 1).map((entry) => entry.uid),
    forfeitedUIDs,
    finishedAtEpochMs: nowEpochMs,
    configVersion: privateState.configVersion,
  };
}

function processClientIntent(
  inputMatch,
  envelope,
  uid,
  nowEpochMs,
  stagedAnswer = null,
  stageErrorCode = null
) {
  const match = clone(inputMatch);
  const duplicate = existingIntentOutcome(match, envelope, uid);
  if (duplicate) return { match, ack: duplicate, duplicate: true };

  const state = match.private;
  const stateBefore = state.phase;
  const validation = validateParticipant(state, envelope, uid);
  if (validation.code) {
    return { match, ack: reject(match, envelope, uid, validation.code, nowEpochMs, stateBefore) };
  }
  const participant = validation.participant;

  if (envelope.type === "joinMatch") {
    if (state.phase !== PHASE.WAITING_PLAYERS) {
      return { match, ack: reject(match, envelope, uid, "INVALID_MATCH_STATE", nowEpochMs, stateBefore) };
    }
    if (envelope.payload.assignmentTicket !== participant.assignmentTicket) {
      return { match, ack: reject(match, envelope, uid, "INVALID_ASSIGNMENT_TICKET", nowEpochMs, stateBefore) };
    }
    participant.joined = true;
    return {
      match,
      ack: recordOutcome(match, envelope, uid, {
        accepted: true, stateChanged: true, stateBefore, authorityTimestamp: nowEpochMs,
      }),
    };
  }

  if (envelope.type === "ready") {
    if (state.phase !== PHASE.WAITING_PLAYERS || !participant.joined) {
      return { match, ack: reject(match, envelope, uid, "INVALID_MATCH_STATE", nowEpochMs, stateBefore) };
    }
    participant.ready = true;
    if (state.participantOrder.every((id) => state.participants[id].joined
        && state.participants[id].ready)) {
      state.phase = PHASE.COUNTDOWN;
      state.countdownEndsAtEpochMs = nowEpochMs + state.config.countdownDurationMs;
      state.rosterCommitted = true;
    }
    return {
      match,
      ack: recordOutcome(match, envelope, uid, {
        accepted: true, stateChanged: true, stateBefore, authorityTimestamp: nowEpochMs,
      }),
    };
  }

  if (envelope.type === "reconnect") {
    if ([PHASE.MATCH_FINISHED, PHASE.SETTLEMENT_PENDING, PHASE.SETTLED].includes(state.phase)) {
      return { match, ack: reject(match, envelope, uid, "INVALID_MATCH_STATE", nowEpochMs, stateBefore) };
    }
    if (participant.forfeited || !participant.active) {
      return { match, ack: reject(match, envelope, uid, "PLAYER_FORFEITED", nowEpochMs, stateBefore) };
    }
    if (participant.status === PARTICIPANT_STATUS.CONNECTED) {
      return {
        match,
        ack: recordOutcome(match, envelope, uid, {
          accepted: true, stateChanged: false, stateBefore, authorityTimestamp: nowEpochMs,
        }),
      };
    }
    if (participant.status !== PARTICIPANT_STATUS.RECONNECTING) {
      return { match, ack: reject(match, envelope, uid, "NOT_RECONNECTING", nowEpochMs, stateBefore) };
    }
    if (nowEpochMs > participant.reconnectDeadlineEpochMs) {
      forfeitParticipant(state, participant, nowEpochMs, "RECONNECT_TIMEOUT");
      return {
        match,
        ack: recordOutcome(match, envelope, uid, {
          accepted: false,
          rejectionCode: "RECONNECT_GRACE_EXPIRED",
          stateChanged: true,
          stateBefore,
          authorityTimestamp: nowEpochMs,
        }),
      };
    }
    participant.status = PARTICIPANT_STATUS.CONNECTED;
    delete participant.disconnectedAtEpochMs;
    delete participant.reconnectDeadlineEpochMs;
    return {
      match,
      ack: recordOutcome(match, envelope, uid, {
        accepted: true, stateChanged: true, stateBefore, authorityTimestamp: nowEpochMs,
      }),
    };
  }

  if (envelope.type === "forfeit") {
    if ([PHASE.CREATED, PHASE.WAITING_PLAYERS].includes(state.phase)) {
      return { match, ack: reject(match, envelope, uid, "MATCH_NOT_COMMITTED", nowEpochMs, stateBefore) };
    }
    if ([PHASE.MATCH_FINISHED, PHASE.SETTLEMENT_PENDING, PHASE.SETTLED].includes(state.phase)) {
      return { match, ack: reject(match, envelope, uid, "INVALID_MATCH_STATE", nowEpochMs, stateBefore) };
    }
    if (!forfeitParticipant(state, participant, nowEpochMs, "EXPLICIT_FORFEIT")) {
      return { match, ack: reject(match, envelope, uid, "PLAYER_FORFEITED", nowEpochMs, stateBefore) };
    }
    if (state.phase === PHASE.QUESTION_OPEN && allActivePlayersAnswered(state)) {
      closeQuestion(state, nowEpochMs, "ALL_ACTIVE_PLAYERS_ANSWERED");
    }
    return {
      match,
      ack: recordOutcome(match, envelope, uid, {
        accepted: true, stateChanged: true, stateBefore, authorityTimestamp: nowEpochMs,
      }),
    };
  }

  if (envelope.type === "leave") {
    if (state.phase !== PHASE.WAITING_PLAYERS) {
      return { match, ack: reject(match, envelope, uid, "FORFEIT_REQUIRED", nowEpochMs, stateBefore) };
    }
    participant.active = false;
    participant.status = PARTICIPANT_STATUS.FORFEITED;
    state.phase = PHASE.MATCH_FINISHED;
    state.matchResult = {
      matchId: state.matchId,
      outcome: "ABORTED",
      abortReason: "PLAYER_LEFT_BEFORE_COUNTDOWN",
      finishedAtEpochMs: nowEpochMs,
      configVersion: state.configVersion,
    };
    return {
      match,
      ack: recordOutcome(match, envelope, uid, {
        accepted: true, stateChanged: true, stateBefore, authorityTimestamp: nowEpochMs,
      }),
    };
  }

  if (envelope.type !== "submitAnswer") {
    return { match, ack: reject(match, envelope, uid, "INVALID_PAYLOAD", nowEpochMs, stateBefore) };
  }

  const question = state.currentQuestion;
  if (state.phase !== PHASE.QUESTION_OPEN || !question) {
    return { match, ack: reject(match, envelope, uid, "INVALID_MATCH_STATE", nowEpochMs, stateBefore) };
  }
  if (!participant.active) {
    return { match, ack: reject(match, envelope, uid, "NOT_ACTIVE_PLAYER", nowEpochMs, stateBefore) };
  }
  if (envelope.questionId !== question.questionId) {
    return { match, ack: reject(match, envelope, uid, "QUESTION_MISMATCH", nowEpochMs, stateBefore) };
  }
  if (!Number.isSafeInteger(envelope.stateVersion)
      || envelope.stateVersion < question.openedStateVersion
      || envelope.stateVersion > state.stateVersion) {
    return { match, ack: reject(match, envelope, uid, "STALE_STATE_VERSION", nowEpochMs, stateBefore) };
  }
  if (!question.choices.some((choice) => choice.answerId === envelope.payload.answerId)) {
    return { match, ack: reject(match, envelope, uid, "INVALID_ANSWER_ID", nowEpochMs, stateBefore) };
  }
  question.answers ||= {};
  if (question.answers[uid]) {
    return { match, ack: reject(match, envelope, uid, "ALREADY_ANSWERED", nowEpochMs, stateBefore) };
  }
  if (stageErrorCode) {
    return { match, ack: reject(match, envelope, uid, stageErrorCode, nowEpochMs, stateBefore) };
  }
  if (!stagedAnswer || stagedAnswer.uid !== uid
      || stagedAnswer.eventId !== envelope.intentId
      || stagedAnswer.questionId !== envelope.questionId
      || stagedAnswer.answerId !== envelope.payload.answerId) {
    return { match, ack: reject(match, envelope, uid, "ANSWER_STAGE_MISMATCH", nowEpochMs, stateBefore) };
  }
  if (!Number.isFinite(stagedAnswer.acceptedAtEpochMs)
      || stagedAnswer.acceptedAtEpochMs > question.deadlineEpochMs) {
    return { match, ack: reject(match, envelope, uid, "DEADLINE_EXCEEDED", nowEpochMs, stateBefore) };
  }

  // Invalid/stale human requests must not advance server-owned NPC state.
  applyDueNPCActions(state, nowEpochMs);
  state.answerInbox ||= {};
  state.answerInbox[question.questionId] ||= {};
  if (state.answerInbox[question.questionId][uid]) {
    return { match, ack: reject(match, envelope, uid, "ALREADY_ANSWERED", nowEpochMs, stateBefore) };
  }
  state.answerInbox[question.questionId][uid] = stagedAnswer;
  question.answers[uid] = stagedAnswer;
  if (allActivePlayersAnswered(state)) {
    closeQuestion(state, nowEpochMs, "ALL_ANSWERED");
  }
  return {
    match,
    ack: recordOutcome(match, envelope, uid, {
      accepted: true, stateChanged: true, stateBefore, authorityTimestamp: nowEpochMs,
    }),
  };
}

function processReconcile(inputMatch, envelope, uid, nowEpochMs) {
  const match = clone(inputMatch);
  const duplicate = existingIntentOutcome(match, envelope, uid);
  if (duplicate) return { match, ack: duplicate, duplicate: true };
  const state = match.private;
  const stateBefore = state.phase;
  const validation = validateParticipant(state, envelope, uid);
  if (validation.code) {
    return { match, ack: reject(match, envelope, uid, validation.code, nowEpochMs, stateBefore) };
  }

  let changed = expireReconnectGrace(state, nowEpochMs);
  if (state.phase === PHASE.CREATED) {
    state.phase = PHASE.WAITING_PLAYERS;
    changed = true;
  } else if (state.phase === PHASE.COUNTDOWN
      && nowEpochMs >= state.countdownEndsAtEpochMs) {
    openQuestion(state, 0, nowEpochMs, state.stateVersion + 1);
    changed = true;
  } else if (state.phase === PHASE.QUESTION_OPEN) {
    const reachedDeadline = nowEpochMs >= state.currentQuestion.deadlineEpochMs;
    changed = applyDueNPCActions(
      state,
      nowEpochMs,
      reachedDeadline ? Number.POSITIVE_INFINITY : 1
    ) || changed;
    if (allActivePlayersAnswered(state)) {
      closeQuestion(state, nowEpochMs, "ALL_ANSWERED");
      changed = true;
    } else if (reachedDeadline) {
      closeQuestion(state, nowEpochMs, "DEADLINE");
      changed = true;
    }
  } else if (state.phase === PHASE.QUESTION_RESULT
      && nowEpochMs >= state.resultEndsAtEpochMs) {
    if (state.currentQuestionIndex + 1 >= state.questionInstances.length) {
      finishMatch(state, nowEpochMs);
    } else {
      state.phase = PHASE.NEXT_QUESTION;
    }
    changed = true;
  } else if (state.phase === PHASE.NEXT_QUESTION) {
    openQuestion(state, state.currentQuestionIndex + 1, nowEpochMs, state.stateVersion + 1);
    changed = true;
  } else if (state.phase === PHASE.MATCH_FINISHED
      && state.matchResult?.outcome === "COMPLETED") {
    state.phase = PHASE.SETTLEMENT_PENDING;
    state.settlement = {
      settlementId: `${state.matchId}:${SETTLEMENT_VERSION}`,
      settlementVersion: SETTLEMENT_VERSION,
      status: "CORE_RESULT_READY",
    };
    changed = true;
  }

  return {
    match,
    ack: recordOutcome(match, envelope, uid, {
      accepted: true,
      stateChanged: changed,
      stateBefore,
      authorityTimestamp: nowEpochMs,
    }),
  };
}

function processPresenceSignal(inputMatch, signal, uid, nowEpochMs) {
  const match = clone(inputMatch);
  const state = match.private;
  const participant = state?.participants?.[uid];
  if (!state || !participant || participant.kind === PARTICIPANT_KIND.NPC) {
    return { match, changed: false, rejectionCode: "NOT_MATCH_MEMBER" };
  }
  if (participant.sessionId !== signal.sessionId
      || participant.sessionEpoch !== signal.sessionEpoch) {
    return { match, changed: false, rejectionCode: "STALE_SESSION_EPOCH" };
  }
  if (participant.forfeited || !participant.active
      || [PHASE.MATCH_FINISHED, PHASE.SETTLEMENT_PENDING, PHASE.SETTLED].includes(state.phase)) {
    return { match, changed: false, rejectionCode: "INVALID_MATCH_STATE" };
  }
  if (typeof signal.authorityEventKey === "string"
      && typeof participant.presenceAuthorityEventKey === "string"
      && signal.authorityEventKey <= participant.presenceAuthorityEventKey) {
    return { match, changed: false, rejectionCode: "STALE_PRESENCE_EVENT" };
  }
  const stateBefore = state.phase;
  if (signal.status === "DISCONNECTED") {
    if (participant.status === PARTICIPANT_STATUS.RECONNECTING) {
      return { match, changed: false, rejectionCode: null };
    }
    participant.status = PARTICIPANT_STATUS.RECONNECTING;
    participant.disconnectedAtEpochMs = nowEpochMs;
    participant.reconnectDeadlineEpochMs = nowEpochMs + state.config.reconnectGraceMs;
  } else if (signal.status === "CONNECTED") {
    if (participant.status !== PARTICIPANT_STATUS.RECONNECTING) {
      return { match, changed: false, rejectionCode: null };
    }
    if (nowEpochMs > participant.reconnectDeadlineEpochMs) {
      forfeitParticipant(state, participant, nowEpochMs, "RECONNECT_TIMEOUT");
    } else {
      participant.status = PARTICIPANT_STATUS.CONNECTED;
      delete participant.disconnectedAtEpochMs;
      delete participant.reconnectDeadlineEpochMs;
    }
  } else {
    return { match, changed: false, rejectionCode: "INVALID_PRESENCE_STATUS" };
  }
  if (typeof signal.authorityEventKey === "string") {
    participant.presenceAuthorityEventKey = signal.authorityEventKey;
  }
  state.serverSequence += 1;
  state.stateVersion += 1;
  state.audit ||= {};
  state.audit[String(state.serverSequence)] = {
    eventId: `presence-${uid}-${nowEpochMs}`,
    eventType: `presence:${signal.status}`,
    matchId: state.matchId,
    serverSequence: state.serverSequence,
    sessionId: signal.sessionId,
    sessionEpoch: signal.sessionEpoch,
    playerUID: uid,
    stateBefore,
    stateAfter: state.phase,
    accepted: true,
    authorityTimestamp: nowEpochMs,
    protocolVersion: state.protocolVersion,
    serverVersion: state.serverVersion,
    configVersion: state.configVersion,
  };
  syncPublic(match);
  return { match, changed: true, rejectionCode: null };
}

module.exports = {
  acceptedAnswersForCurrentQuestion,
  activeParticipantUIDs,
  allActivePlayersAnswered,
  existingIntentOutcome,
  intentFingerprint,
  processClientIntent,
  processPresenceSignal,
  processReconcile,
  syncPublic,
};
