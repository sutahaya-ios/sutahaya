import Foundation

enum CompetitivePhase: String, Equatable, Sendable {
    case created = "CREATED"
    case waitingPlayers = "WAITING_PLAYERS"
    case countdown = "COUNTDOWN"
    case questionOpen = "QUESTION_OPEN"
    case questionResult = "QUESTION_RESULT"
    case nextQuestion = "NEXT_QUESTION"
    case matchFinished = "MATCH_FINISHED"
    case settlementPending = "SETTLEMENT_PENDING"
    case settled = "SETTLED"
}

struct CompetitiveChoice: Identifiable, Equatable, Sendable {
    let answerId: String
    let text: String
    var id: String { answerId }
}

struct CompetitiveQuestion: Equatable, Sendable {
    let questionId: String
    let questionIndex: Int
    let prompt: String
    let choices: [CompetitiveChoice]
    let openedAtEpochMS: Double
    let deadlineEpochMS: Double
    /// `QUESTION_RESULT`になった後だけServerから公開される。
    let correctAnswerId: String?
}

struct CompetitiveParticipant: Identifiable, Equatable, Sendable {
    let uid: String
    let slot: Int
    let displayName: String
    let joined: Bool
    let ready: Bool
    let active: Bool
    let forfeited: Bool
    let answered: Bool
    let score: Int
    var id: String { uid }
}

struct CompetitiveQuestionResult: Equatable, Sendable {
    let questionId: String
    let questionIndex: Int
    let closeReason: String
    let answerOrder: [String]
    let correctUIDs: [String]
    let wrongUIDs: [String]
    let unansweredUIDs: [String]
    let scoreDeltas: [String: Int]
    let cumulativeScores: [String: Int]
    let correctAnswerId: String
    let closedAtEpochMS: Double
}

struct CompetitiveFinalResult: Equatable, Sendable {
    let outcome: String
    let finalScores: [String: Int]
    let ranks: [String: Int]
    let winnerUIDs: [String]
    let forfeitedUIDs: [String]
    let finishedAtEpochMS: Double
}

struct CompetitivePublicState: Equatable, Sendable {
    let matchId: String
    let protocolVersion: String
    let configVersion: String
    let phase: CompetitivePhase
    let stateVersion: Int
    let serverSequence: Int
    let participants: [CompetitiveParticipant]
    let currentQuestionIndex: Int
    let currentQuestion: CompetitiveQuestion?
    let questionResult: CompetitiveQuestionResult?
    let countdownEndsAtEpochMS: Double?
    let resultEndsAtEpochMS: Double?
    let finalResult: CompetitiveFinalResult?

    init?(databaseValue value: Any?) {
        guard let value = CompetitiveValue.dictionary(value),
              let matchId = CompetitiveValue.string(value["matchId"]),
              let protocolVersion = CompetitiveValue.string(value["protocolVersion"]),
              let configVersion = CompetitiveValue.string(value["configVersion"]),
              let phaseValue = CompetitiveValue.string(value["phase"]),
              let phase = CompetitivePhase(rawValue: phaseValue),
              let stateVersion = CompetitiveValue.int(value["stateVersion"]),
              let serverSequence = CompetitiveValue.int(value["serverSequence"]),
              let currentQuestionIndex = CompetitiveValue.int(value["currentQuestionIndex"]),
              let participantValues = CompetitiveValue.dictionary(value["participants"])
        else { return nil }

        let participants = participantValues.compactMap { uid, rawValue -> CompetitiveParticipant? in
            guard let participant = CompetitiveValue.dictionary(rawValue),
                  let slot = CompetitiveValue.int(participant["slot"]),
                  let displayName = CompetitiveValue.string(participant["displayName"]),
                  let joined = CompetitiveValue.bool(participant["joined"]),
                  let ready = CompetitiveValue.bool(participant["ready"]),
                  let active = CompetitiveValue.bool(participant["active"]),
                  let forfeited = CompetitiveValue.bool(participant["forfeited"]),
                  let answered = CompetitiveValue.bool(participant["answered"]),
                  let score = CompetitiveValue.int(participant["score"])
            else { return nil }
            return CompetitiveParticipant(
                uid: uid,
                slot: slot,
                displayName: displayName,
                joined: joined,
                ready: ready,
                active: active,
                forfeited: forfeited,
                answered: answered,
                score: score
            )
        }.sorted { $0.slot < $1.slot }
        guard participants.count == participantValues.count else { return nil }

        self.matchId = matchId
        self.protocolVersion = protocolVersion
        self.configVersion = configVersion
        self.phase = phase
        self.stateVersion = stateVersion
        self.serverSequence = serverSequence
        self.participants = participants
        self.currentQuestionIndex = currentQuestionIndex
        self.currentQuestion = Self.question(value["currentQuestion"])
        self.questionResult = Self.questionResult(value["questionResult"])
        self.countdownEndsAtEpochMS = CompetitiveValue.double(value["countdownEndsAtEpochMs"])
        self.resultEndsAtEpochMS = CompetitiveValue.double(value["resultEndsAtEpochMs"])
        self.finalResult = Self.finalResult(value["finalResult"])
    }

    private static func question(_ rawValue: Any?) -> CompetitiveQuestion? {
        guard let value = CompetitiveValue.dictionary(rawValue),
              let questionId = CompetitiveValue.string(value["questionId"]),
              let questionIndex = CompetitiveValue.int(value["questionIndex"]),
              let prompt = CompetitiveValue.string(value["prompt"]),
              let choiceValues = value["choices"] as? [Any],
              let openedAtEpochMS = CompetitiveValue.double(value["openedAtEpochMs"]),
              let deadlineEpochMS = CompetitiveValue.double(value["deadlineEpochMs"])
        else { return nil }
        let choices = choiceValues.compactMap { rawChoice -> CompetitiveChoice? in
            guard let choice = CompetitiveValue.dictionary(rawChoice),
                  let answerId = CompetitiveValue.string(choice["answerId"]),
                  let text = CompetitiveValue.string(choice["text"])
            else { return nil }
            return CompetitiveChoice(answerId: answerId, text: text)
        }
        guard choices.count == choiceValues.count else { return nil }
        return CompetitiveQuestion(
            questionId: questionId,
            questionIndex: questionIndex,
            prompt: prompt,
            choices: choices,
            openedAtEpochMS: openedAtEpochMS,
            deadlineEpochMS: deadlineEpochMS,
            correctAnswerId: CompetitiveValue.string(value["correctAnswerId"])
        )
    }

    private static func questionResult(_ rawValue: Any?) -> CompetitiveQuestionResult? {
        guard let value = CompetitiveValue.dictionary(rawValue),
              let questionId = CompetitiveValue.string(value["questionId"]),
              let questionIndex = CompetitiveValue.int(value["questionIndex"]),
              let closeReason = CompetitiveValue.string(value["closeReason"]),
              let correctAnswerId = CompetitiveValue.string(value["correctAnswerId"]),
              let closedAtEpochMS = CompetitiveValue.double(value["closedAtEpochMs"])
        else { return nil }
        return CompetitiveQuestionResult(
            questionId: questionId,
            questionIndex: questionIndex,
            closeReason: closeReason,
            answerOrder: CompetitiveValue.strings(value["answerOrder"]),
            correctUIDs: CompetitiveValue.strings(value["correctUIDs"]),
            wrongUIDs: CompetitiveValue.strings(value["wrongUIDs"]),
            unansweredUIDs: CompetitiveValue.strings(value["unansweredUIDs"]),
            scoreDeltas: CompetitiveValue.integers(value["scoreDeltas"]),
            cumulativeScores: CompetitiveValue.integers(value["cumulativeScores"]),
            correctAnswerId: correctAnswerId,
            closedAtEpochMS: closedAtEpochMS
        )
    }

    private static func finalResult(_ rawValue: Any?) -> CompetitiveFinalResult? {
        guard let value = CompetitiveValue.dictionary(rawValue),
              let outcome = CompetitiveValue.string(value["outcome"]),
              let finishedAtEpochMS = CompetitiveValue.double(value["finishedAtEpochMs"])
        else { return nil }
        return CompetitiveFinalResult(
            outcome: outcome,
            finalScores: CompetitiveValue.integers(value["finalScores"]),
            ranks: CompetitiveValue.integers(value["ranks"]),
            winnerUIDs: CompetitiveValue.strings(value["winnerUIDs"]),
            forfeitedUIDs: CompetitiveValue.strings(value["forfeitedUIDs"]),
            finishedAtEpochMS: finishedAtEpochMS
        )
    }
}

struct CompetitiveSession: Equatable, Sendable {
    let matchId: String
    let sessionId: String
    let sessionEpoch: Int
    let assignmentTicket: String
}

enum CompetitiveIntentStatus: String, Equatable, Sendable {
    case accepted = "ACCEPTED"
    case rejected = "REJECTED"
    case duplicate = "DUPLICATE"
}

struct CompetitiveIntentAck: Equatable, Sendable {
    let intentId: String
    let status: CompetitiveIntentStatus
    let serverSequence: Int?
    let publicStateVersion: Int?
    let rejectionCode: String?
    let retryable: Bool
    let originalStatus: CompetitiveIntentStatus?

    init?(value rawValue: Any) {
        guard let value = CompetitiveValue.dictionary(rawValue),
              let intentId = CompetitiveValue.string(value["intentId"]),
              let statusValue = CompetitiveValue.string(value["status"]),
              let status = CompetitiveIntentStatus(rawValue: statusValue)
        else { return nil }
        self.intentId = intentId
        self.status = status
        self.serverSequence = CompetitiveValue.int(value["serverSequence"])
        self.publicStateVersion = CompetitiveValue.int(value["publicStateVersion"])
        self.rejectionCode = CompetitiveValue.string(value["rejectionCode"])
        self.retryable = CompetitiveValue.bool(value["retryable"]) ?? false
        self.originalStatus = CompetitiveValue.string(value["originalStatus"])
            .flatMap(CompetitiveIntentStatus.init(rawValue:))
    }
}

private enum CompetitiveValue {
    static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    static func string(_ value: Any?) -> String? {
        value as? String
    }

    static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        return (value as? NSNumber)?.boolValue
    }

    static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return (value as? NSNumber)?.intValue
    }

    static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        return (value as? NSNumber)?.doubleValue
    }

    static func strings(_ value: Any?) -> [String] {
        if let value = value as? [String] { return value }
        return (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    static func integers(_ value: Any?) -> [String: Int] {
        guard let value = dictionary(value) else { return [:] }
        return value.reduce(into: [:]) { result, entry in
            if let number = int(entry.value) { result[entry.key] = number }
        }
    }
}
