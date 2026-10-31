const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { after, before, beforeEach, describe, it } = require("node:test");
const { assertFails, assertSucceeds, initializeTestEnvironment } = require("@firebase/rules-unit-testing");
const {
  collection, deleteDoc, doc, getDoc, getDocs, runTransaction,
  serverTimestamp, setDoc, updateDoc, writeBatch,
} = require("firebase/firestore");

// rules.test.jsと並列実行してもclearFirestoreが互いのデータを消さない。
const projectId = "demo-hayaosiapp-authoring";
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../firestore.rules"), "utf8"),
    },
  });
});
beforeEach(async () => { await testEnv.clearFirestore(); });
after(async () => { await testEnv?.cleanup(); });

function database(uid) {
  return uid ? testEnv.authenticatedContext(uid).firestore() : testEnv.unauthenticatedContext().firestore();
}

function question(format = "trueFalse", overrides = {}) {
  const formatFields = {
    trueFalse: { choices: ["○", "×"], answers: ["○"] },
    multipleChoice: { choices: ["東京", "大阪", "京都", "札幌"], answers: ["東京"] },
    shortAnswer: { choices: [], answers: ["東京", "とうきょう", "Tokyo", "tokyo", "東京都"] },
  };
  return {
    id: "question-1", format, text: "日本の首都について答えてください。",
    ...formatFields[format], explanation: "解説です。", ...overrides,
  };
}

function questionSet(overrides = {}) {
  return {
    title: "地理の問題集", creatorUID: "alice", createdAt: serverTimestamp(),
    questions: [question()], status: "active", schemaVersion: 1, ...overrides,
  };
}

function libraryEntry(setID = "set-1", overrides = {}) {
  return { questionSetID: setID, addedAt: serverTimestamp(), ...overrides };
}

function share(setID = "set-1", overrides = {}) {
  return {
    questionSetID: setID, fromUID: "alice", toUID: "bob", fromNickname: "Alice",
    title: "地理の問題集", sentAt: serverTimestamp(), ...overrides,
  };
}

async function seedProfilesAndFriends({ reciprocal = true, friends = true } = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [uid, nickname] of [["alice", "Alice"], ["bob", "Bob"], ["eve", "Eve"]]) {
      await setDoc(doc(db, "users", uid), { nickname });
    }
    if (friends) {
      await setDoc(doc(db, "users", "alice", "friends", "bob"), { nickname: "Bob" });
      if (reciprocal) {
        await setDoc(doc(db, "users", "bob", "friends", "alice"), { nickname: "Alice" });
      }
    }
  });
}

async function createSet(db, setID = "set-1", overrides = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, "questionSets", setID), questionSet(overrides));
  batch.set(doc(db, "users", "alice", "library", setID), libraryEntry(setID));
  return batch.commit();
}

// QuestionSetService.swiftと同じ順番で全readを済ませてからwriteする。
async function createSetTransaction(db, setID = "set-1", overrides = {}) {
  const setRef = doc(db, "questionSets", setID);
  const libraryRef = doc(db, "users", "alice", "library", setID);
  const payload = questionSet({
    questions: [question(), question("multipleChoice", { id: "question-2" }), question("shortAnswer", { id: "question-3" })],
    ...overrides,
  });
  await runTransaction(db, async (transaction) => {
    const existing = await transaction.get(setRef);
    const library = await transaction.get(libraryRef);
    if (existing.exists()) {
      const saved = existing.data();
      if (saved.creatorUID !== "alice" || saved.status !== "active"
          || saved.title !== payload.title) {
        throw new Error("conflicting-draft");
      }
      assert.deepEqual(saved.questions, payload.questions, "conflicting-draft");
    } else {
      transaction.set(setRef, payload);
    }
    if (!library.exists()) transaction.set(libraryRef, libraryEntry(setID));
  });
}

async function shareTransaction(db, setID = "set-1") {
  const setRef = doc(db, "questionSets", setID);
  const shareRef = doc(db, "users", "bob", "sharedQuestionSets", setID);
  const profileRef = doc(db, "users", "alice");
  await runTransaction(db, async (transaction) => {
    const current = (await transaction.get(setRef)).data();
    const existing = await transaction.get(shareRef);
    const profile = (await transaction.get(profileRef)).data();
    if (current.status !== "active" || current.creatorUID !== "alice") throw new Error("unavailable");
    if (existing.exists()) return;
    transaction.set(shareRef, share(setID, { title: current.title, fromNickname: profile.nickname }));
  });
}

async function addTransaction(db, setID = "set-1") {
  const setRef = doc(db, "questionSets", setID);
  const shareRef = doc(db, "users", "bob", "sharedQuestionSets", setID);
  const entryRef = doc(db, "users", "bob", "library", setID);
  await runTransaction(db, async (transaction) => {
    const current = (await transaction.get(setRef)).data();
    const incoming = (await transaction.get(shareRef)).data();
    const existing = await transaction.get(entryRef);
    if (current.status !== "active" || incoming.fromUID !== current.creatorUID) throw new Error("unavailable");
    if (!existing.exists()) transaction.set(entryRef, libraryEntry(setID));
  });
}

async function deleteTransaction(db, setID = "set-1") {
  const setRef = doc(db, "questionSets", setID);
  await runTransaction(db, async (transaction) => {
    const current = (await transaction.get(setRef)).data();
    if (current.creatorUID !== "alice") throw new Error("not-creator");
    if (current.status === "deleted") return;
    if (current.status !== "active") throw new Error("unavailable");
    transaction.update(setRef, { status: "deleted" });
  });
}

describe("Question authoring Firestore rules", () => {
  it("completes create, library, friend share, recipient add and repeated transaction no-ops", async () => {
    await seedProfilesAndFriends();
    const alice = database("alice");
    const bob = database("bob");
    await assertSucceeds(createSetTransaction(alice));
    await assertSucceeds(createSetTransaction(alice));
    const ownLibrary = await assertSucceeds(getDocs(collection(alice, "users", "alice", "library")));
    assert.equal(ownLibrary.size, 1);
    await assertFails(getDoc(doc(bob, "questionSets", "set-1")));
    await assertSucceeds(shareTransaction(alice));
    const firstShare = (await getDoc(doc(bob, "users", "bob", "sharedQuestionSets", "set-1"))).data();
    await assertSucceeds(shareTransaction(alice));
    const inbox = await assertSucceeds(getDocs(collection(bob, "users", "bob", "sharedQuestionSets")));
    assert.equal(inbox.size, 1);
    assert.equal(inbox.docs[0].data().sentAt.toMillis(), firstShare.sentAt.toMillis());
    const received = await assertSucceeds(getDoc(doc(bob, "questionSets", "set-1")));
    assert.equal(received.data().questions.length, 3);
    await assertSucceeds(addTransaction(bob));
    await assertSucceeds(addTransaction(bob));
    const recipientLibrary = await assertSucceeds(getDocs(collection(bob, "users", "bob", "library")));
    assert.equal(recipientLibrary.size, 1);
    // 新しいクライアントからも保存データを読み出せる（Simulator再起動の代用ではない）。
    assert.equal((await assertSucceeds(getDoc(doc(database("bob"), "questionSets", "set-1")))).data().title, "地理の問題集");
  });

  for (const format of ["trueFalse", "multipleChoice", "shortAnswer"]) {
    it(`accepts all 20 structurally validated ${format} questions within the rules expression limit`, async () => {
      const questions = Array.from({ length: 20 }, (_, i) => question(format, { id: `question-${i}` }));
      await assertSucceeds(createSetTransaction(database("alice"), "max-20", { questions }));
    });
  }

  it("preserves the saved body on a conflicting retry and supports repeated logical deletion", async () => {
    const alice = database("alice");
    await assertSucceeds(createSetTransaction(alice));
    await assert.rejects(createSetTransaction(alice, "set-1", { title: "Different draft" }), /conflicting-draft/);
    assert.equal((await getDoc(doc(alice, "questionSets", "set-1"))).data().title, "地理の問題集");
    await assertSucceeds(deleteTransaction(alice));
    await assertSucceeds(deleteTransaction(alice));
    assert.equal((await getDoc(doc(alice, "questionSets", "set-1"))).data().status, "deleted");
  });

  it("requires the author library and question set in one atomic write", async () => {
    const alice = database("alice");
    await assertFails(setDoc(doc(alice, "questionSets", "set-1"), questionSet()));
    await assertFails(setDoc(doc(alice, "users", "alice", "library", "set-1"), libraryEntry()));
    await assertSucceeds(createSet(alice));
  });

  it("rejects anonymous access, forged creator and another user's library write", async () => {
    await assertFails(createSet(database()));
    await assertFails(createSet(database("eve")));
    const alice = database("alice");
    await assertSucceeds(createSet(alice));
    await assertFails(getDoc(doc(database(), "questionSets", "set-1")));
    await assertFails(setDoc(doc(alice, "users", "bob", "library", "set-1"), libraryEntry()));
    await assertFails(setDoc(doc(database("eve"), "users", "eve", "library", "set-1"), libraryEntry()));
  });

  it("allows signed-in absent-document checks but keeps existing sets and all enumeration private", async () => {
    const alice = database("alice");
    const eve = database("eve");
    await assertSucceeds(getDoc(doc(eve, "questionSets", "unknown")));
    await assertFails(getDoc(doc(database(), "questionSets", "unknown")));
    await assertSucceeds(createSet(alice));
    await assertFails(getDoc(doc(eve, "questionSets", "set-1")));
    await assertFails(getDocs(collection(alice, "questionSets")));
    await assertFails(getDocs(collection(eve, "questionSets")));
    await assertFails(getDocs(collection(eve, "users", "alice", "library")));
    await assertFails(getDocs(collection(eve, "users", "bob", "sharedQuestionSets")));
  });

  it("rejects sender, recipient, name, title, ID and timestamp spoofing", async () => {
    await seedProfilesAndFriends();
    const alice = database("alice");
    await createSet(alice);
    for (const overrides of [
      { fromUID: "eve" }, { toUID: "eve" }, { fromNickname: "Someone else" },
      { title: "Different title" }, { questionSetID: "other-set" },
      { sentAt: new Date(0) }, { extra: "forbidden" },
    ]) {
      await assertFails(setDoc(doc(alice, "users", "bob", "sharedQuestionSets", "set-1"), share("set-1", overrides)));
    }
    await assertFails(setDoc(doc(database("eve"), "users", "bob", "sharedQuestionSets", "set-1"), share()));
    await assertFails(setDoc(doc(alice, "users", "alice", "sharedQuestionSets", "set-1"), share("set-1", { toUID: "alice" })));
  });

  for (const options of [{ friends: false }, { reciprocal: false }]) {
    it(`rejects sharing without mutual friendship: ${JSON.stringify(options)}`, async () => {
      await seedProfilesAndFriends(options);
      const alice = database("alice");
      await createSet(alice);
      await assertFails(setDoc(doc(alice, "users", "bob", "sharedQuestionSets", "set-1"), share()));
    });
  }

  it("does not let a recipient reshare or write another recipient's inbox", async () => {
    await seedProfilesAndFriends();
    const alice = database("alice");
    const bob = database("bob");
    await createSet(alice);
    await shareTransaction(alice);
    await addTransaction(bob);
    await assertFails(setDoc(doc(bob, "users", "eve", "sharedQuestionSets", "set-1"), share("set-1", { fromUID: "bob", fromNickname: "Bob", toUID: "eve" })));
    await assertFails(getDoc(doc(database("eve"), "users", "bob", "sharedQuestionSets", "set-1")));
    await assertFails(getDoc(doc(bob, "users", "eve", "sharedQuestionSets", "set-1")));
  });

  it("keeps question body, library references and inbox immutable", async () => {
    await seedProfilesAndFriends();
    const alice = database("alice");
    const bob = database("bob");
    await createSet(alice);
    await shareTransaction(alice);
    await addTransaction(bob);
    await assertFails(updateDoc(doc(alice, "questionSets", "set-1"), { title: "編集" }));
    await assertFails(updateDoc(doc(alice, "questionSets", "set-1"), { questions: [question("shortAnswer")] }));
    await assertFails(deleteDoc(doc(alice, "questionSets", "set-1")));
    await assertFails(setDoc(doc(alice, "users", "bob", "sharedQuestionSets", "set-1"), share()));
    await assertFails(deleteDoc(doc(bob, "users", "bob", "sharedQuestionSets", "set-1")));
    await assertFails(setDoc(doc(bob, "users", "bob", "library", "set-1"), libraryEntry()));
    await assertFails(deleteDoc(doc(bob, "users", "bob", "library", "set-1")));
  });

  it("allows only author logical deletion, preserving readable status but denying new share or add", async () => {
    await seedProfilesAndFriends();
    const alice = database("alice");
    const bob = database("bob");
    await createSet(alice);
    await shareTransaction(alice);
    const ref = doc(alice, "questionSets", "set-1");
    await assertFails(updateDoc(doc(bob, "questionSets", "set-1"), { status: "deleted" }));
    await assertFails(updateDoc(ref, { status: "blocked" }));
    await assertFails(updateDoc(ref, { status: "deleted", title: "Changed" }));
    await assertSucceeds(updateDoc(ref, { status: "deleted" }));
    assert.equal((await assertSucceeds(getDoc(doc(bob, "questionSets", "set-1")))).data().status, "deleted");
    await assert.rejects(addTransaction(bob), /unavailable/);
    await assertFails(setDoc(doc(bob, "users", "bob", "library", "set-1"), libraryEntry()));
    await assertFails(updateDoc(ref, { status: "active" }));
    await assertFails(setDoc(doc(alice, "users", "eve", "sharedQuestionSets", "set-1"), share("set-1", { toUID: "eve" })));
  });

  it("rejects sharing and logical deletion in the same atomic batch", async () => {
    await seedProfilesAndFriends();
    const alice = database("alice");
    await createSet(alice);
    const batch = writeBatch(alice);
    batch.update(doc(alice, "questionSets", "set-1"), { status: "deleted" });
    batch.set(doc(alice, "users", "bob", "sharedQuestionSets", "set-1"), share());
    await assertFails(batch.commit());
    assert.equal((await getDoc(doc(alice, "questionSets", "set-1"))).data().status, "active");
    assert.equal((await getDoc(doc(database("bob"), "users", "bob", "sharedQuestionSets", "set-1"))).exists(), false);
  });

  it("retains an existing shared grant after friendship removal", async () => {
    await seedProfilesAndFriends();
    const alice = database("alice");
    const bob = database("bob");
    await createSet(alice);
    await shareTransaction(alice);
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await deleteDoc(doc(context.firestore(), "users", "alice", "friends", "bob"));
      await deleteDoc(doc(context.firestore(), "users", "bob", "friends", "alice"));
    });
    await assertSucceeds(addTransaction(bob));
    await assertSucceeds(getDoc(doc(bob, "questionSets", "set-1")));
  });

  it("rejects unshared or missing library references and forged library metadata", async () => {
    const alice = database("alice");
    const bob = database("bob");
    await createSet(alice);
    await assertFails(setDoc(doc(bob, "users", "bob", "library", "set-1"), libraryEntry()));
    await assertFails(setDoc(doc(alice, "users", "alice", "library", "other"), libraryEntry("other")));
    for (const overrides of [{ questionSetID: "wrong" }, { addedAt: new Date(0) }, { extra: true }]) {
      const batch = writeBatch(alice);
      batch.set(doc(alice, "questionSets", "new-set"), questionSet());
      batch.set(doc(alice, "users", "alice", "library", "new-set"), libraryEntry("new-set", overrides));
      await assertFails(batch.commit());
    }
  });

  it("rejects invalid set metadata and question-count limits", async () => {
    const alice = database("alice");
    for (const overrides of [
      { title: "" }, { title: "a".repeat(81) }, { createdAt: new Date(0) },
      { status: "deleted" }, { schemaVersion: 2 }, { extra: "forbidden" },
      { questions: [] }, { questions: "invalid" },
      { questions: Array.from({ length: 21 }, (_, i) => question("trueFalse", { id: `q-${i}` })) },
    ]) await assertFails(createSet(alice, "invalid", overrides));
  });

  it("validates the structure of every question, including the twentieth element", async () => {
    const alice = database("alice");
    const questions = Array.from({ length: 20 }, (_, i) => question("trueFalse", { id: `q-${i}` }));
    questions[19].text = 42;
    await assertFails(createSet(alice, "invalid-last", { questions }));
    for (const overrides of [
      { text: null }, { format: "unknown" },
    ]) await assertFails(createSet(alice, "invalid", { questions: [question("trueFalse", overrides)] }));
    await assertFails(createSet(alice, "invalid", { questions: ["not-a-map"] }));
    const missingText = question();
    delete missingText.text;
    await assertFails(createSet(alice, "invalid", { questions: [missingText] }));
  });

  it("leaves detailed content validation to the app while keeping content private and immutable", async () => {
    // この境界は意図的: Rulesは20問すべてのmap・形式・問題文型と権限を守り、詳細な型と内容はSwiftで検証。
    const alice = database("alice");
    await assertSucceeds(createSet(alice, "client-validation", {
      questions: [question("multipleChoice", {
        text: "", choices: ["duplicate", "duplicate"], answers: ["not-a-choice"],
      })],
    }));
    await assertFails(getDoc(doc(database("eve"), "questionSets", "client-validation")));
    await assertFails(updateDoc(doc(alice, "questionSets", "client-validation"), { questions: [question()] }));
  });
});
