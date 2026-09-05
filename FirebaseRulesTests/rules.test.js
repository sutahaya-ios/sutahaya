const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { after, before, beforeEach, describe, it } = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  writeBatch,
} = require("firebase/firestore");
const {
  get,
  ref,
  remove,
  runTransaction,
  serverTimestamp: databaseServerTimestamp,
  set,
  update,
} = require("firebase/database");

const projectId = "demo-hayaosiapp";
const rootDir = path.resolve(__dirname, "..");

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(path.join(rootDir, "firestore.rules"), "utf8"),
    },
    database: {
      rules: fs.readFileSync(path.join(rootDir, "database.rules.json"), "utf8"),
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearDatabase();
});

after(async () => {
  await testEnv.cleanup();
});

async function seedUser(uid, friendCode, nickname = uid) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users", uid), {
      nickname,
      friendCode,
      createdAt: new Date(),
    });
    await setDoc(doc(db, "friendCodes", friendCode), { uid });
  });
}

async function seedMutualFriends(senderUID = "alice", recipientUID = "bob") {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const addedAt = new Date();
    await setDoc(doc(db, "users", senderUID, "friends", recipientUID), {
      nickname: recipientUID,
      friendCode: "BOB001",
      addedAt,
    });
    await setDoc(doc(db, "users", recipientUID, "friends", senderUID), {
      nickname: senderUID,
      friendCode: "ALICE1",
      addedAt,
    });
  });
}

function inviteDocumentID(roomInstanceID = "room-instance", senderUID = "alice") {
  return `${roomInstanceID}_${senderUID}`;
}

function pendingInvite({
  roomInstanceID = "room-instance",
  roomCode = "1234",
  senderUID = "alice",
  recipientUID = "bob",
  fromNickname = "Alice",
  generation = 1,
  sentAt = serverTimestamp(),
} = {}) {
  return {
    roomInstanceID,
    roomCode,
    fromUID: senderUID,
    toUID: recipientUID,
    fromNickname,
    status: "pending",
    generation,
    sentAt,
  };
}

function rolledBackPendingInvite({ claimID = "claim-current", ...overrides } = {}) {
  return {
    ...pendingInvite(overrides),
    rolledBackClaimID: claimID,
  };
}

function acceptingInvite({
  sentAgoMS = 1_000,
  acceptingAgoMS = 500,
  claimID = "claim-current",
  ...overrides
} = {}) {
  return {
    ...pendingInvite({
      ...overrides,
      sentAt: new Date(Date.now() - sentAgoMS),
    }),
    status: "accepting",
    acceptClaimID: claimID,
    acceptingAt: new Date(Date.now() - acceptingAgoMS),
  };
}

async function seedInvite(data, recipientUID = "bob", documentID = null) {
  const id = documentID ?? inviteDocumentID(data.roomInstanceID, data.fromUID);
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users", recipientUID, "invites", id), data);
  });
  return id;
}

async function seedRoom({ status = "playing" } = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), "rooms/1234"), {
      roomInstanceID: "room-instance",
      hostID: "host",
      status,
      createdAt: 1,
      settings: { questionCount: 10 },
      playerSlots: { 0: "host", 1: "guest" },
      players: {
        host: {
          nickname: "Host", score: 0, joinedAt: 1, roomInstanceID: "room-instance", slot: 0,
        },
        guest: {
          nickname: "Guest", score: 0, joinedAt: 2, roomInstanceID: "room-instance", slot: 1,
        },
      },
      game: { questionIndex: 0, phase: "question" },
    });
  });
}

function playerPayload(uid, slot, {
  roomInstanceID = "room-instance",
  score = 0,
  joinedAt = slot + 1,
  nickname = uid,
} = {}) {
  return { nickname, score, joinedAt, roomInstanceID, slot };
}

async function joinPlayer(db, uid, slot, options = {}) {
  const slotRef = ref(db, `rooms/1234/playerSlots/${slot}`);
  await set(slotRef, uid);
  try {
    await set(ref(db, `rooms/1234/players/${uid}`), playerPayload(uid, slot, options));
  } catch (error) {
    await remove(slotRef).catch(() => {});
    throw error;
  }
}

async function addNPC(db, profileID, slot) {
  const slotRef = ref(db, `rooms/1234/playerSlots/${slot}`);
  await set(slotRef, profileID);
  try {
    await set(ref(db, `rooms/1234/players/${profileID}`), playerPayload(profileID, slot, {
      nickname: profileID,
    }));
  } catch (error) {
    await remove(slotRef).catch(() => {});
    throw error;
  }
}

function leavePlayer(db, uid, slot) {
  return update(ref(db, "rooms/1234"), {
    [`playerSlots/${slot}`]: null,
    [`players/${uid}`]: null,
  });
}

describe("Cloud Firestore rules", () => {
  it("rejects unauthenticated reads", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "users", "alice")));
  });

  it("allows a signed-in user to get one profile but rejects listing all profiles", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    const db = testEnv.authenticatedContext("bob").firestore();
    await assertSucceeds(getDoc(doc(db, "users", "alice")));
    await assertFails(getDocs(collection(db, "users")));
  });

  it("requires a profile and its friend-code index to be created atomically", async () => {
    const db = testEnv.authenticatedContext("alice").firestore();
    await assertFails(setDoc(doc(db, "users", "alice"), {
      nickname: "Alice",
      friendCode: "ALICE1",
      createdAt: new Date(),
    }));

    const batch = writeBatch(db);
    batch.set(doc(db, "users", "alice"), {
      nickname: "Alice",
      friendCode: "ALICE1",
      createdAt: new Date(),
    });
    batch.set(doc(db, "friendCodes", "ALICE1"), { uid: "alice" });
    await assertSucceeds(batch.commit());
  });

  it("allows a legacy profile to create its missing friend-code index atomically", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users", "legacy"), {
        nickname: "Old Name",
        friendCode: "LEGACY",
        createdAt: new Date(),
      });
    });

    const db = testEnv.authenticatedContext("legacy").firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, "users", "legacy"), { nickname: "New Name" }, { merge: true });
    batch.set(doc(db, "friendCodes", "LEGACY"), { uid: "legacy" });
    await assertSucceeds(batch.commit());
  });

  it("allows exact friend-code lookup but rejects index enumeration", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    const db = testEnv.authenticatedContext("bob").firestore();
    await assertSucceeds(getDoc(doc(db, "friendCodes", "ALICE1")));
    await assertFails(getDocs(collection(db, "friendCodes")));
  });

  it("rejects invite creation and re-invite from every client", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    await seedUser("bob", "BOB001", "Bob");
    await seedMutualFriends();
    const aliceDB = testEnv.authenticatedContext("alice").firestore();
    const inviteRef = doc(
      aliceDB, "users", "bob", "invites", inviteDocumentID()
    );

    await assertFails(setDoc(inviteRef, pendingInvite()));
    await seedInvite(pendingInvite({ sentAt: new Date(Date.now() - 11_000) }));
    await assertFails(setDoc(inviteRef, pendingInvite({ generation: 2 })));
  });

  it("allows only the recipient to claim a non-expired pending generation", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    await seedUser("bob", "BOB001", "Bob");
    await seedMutualFriends();
    const sentAt = new Date(Date.now() - 1_000);
    await seedInvite(pendingInvite({ sentAt }));
    const bobDB = testEnv.authenticatedContext("bob").firestore();
    const aliceDB = testEnv.authenticatedContext("alice").firestore();
    const accepting = {
      ...pendingInvite({ sentAt }),
      status: "accepting",
      acceptClaimID: "claim-current",
      acceptingAt: serverTimestamp(),
    };
    const bobRef = doc(bobDB, "users", "bob", "invites", inviteDocumentID());

    await assertSucceeds(setDoc(bobRef, accepting));
    await seedInvite(pendingInvite({ sentAt }));
    await assertFails(setDoc(
      doc(aliceDB, "users", "bob", "invites", inviteDocumentID()), accepting
    ));
    await seedInvite(pendingInvite({ sentAt: new Date(Date.now() - 31_000) }));
    await assertFails(setDoc(bobRef, {
      ...pendingInvite({ sentAt: new Date(Date.now() - 31_000) }),
      status: "accepting",
      acceptClaimID: "claim-expired",
      acceptingAt: serverTimestamp(),
    }));
  });

  it("finalizes only the current generation and claim, even after lease and invite expiry", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    await seedUser("bob", "BOB001", "Bob");
    const bobDB = testEnv.authenticatedContext("bob").firestore();
    const inviteRef = doc(bobDB, "users", "bob", "invites", inviteDocumentID());
    const current = acceptingInvite({ sentAgoMS: 31_000, acceptingAgoMS: 11_000 });
    await seedInvite(current);

    await assertSucceeds(setDoc(inviteRef, {
      ...current,
      status: "accepted",
      acceptedAt: serverTimestamp(),
    }));

    await seedInvite(current);
    await assertFails(setDoc(inviteRef, {
      ...current,
      status: "accepted",
      acceptClaimID: "claim-stale",
      acceptedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(inviteRef, {
      ...current,
      status: "accepted",
      generation: 2,
      acceptedAt: serverTimestamp(),
    }));
  });

  it("requires the current claim proof for rollback and preserves identity and generation", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    await seedUser("bob", "BOB001", "Bob");
    const bobDB = testEnv.authenticatedContext("bob").firestore();
    const inviteRef = doc(bobDB, "users", "bob", "invites", inviteDocumentID());
    let current = acceptingInvite({ sentAgoMS: 1_000 });
    await seedInvite(current);
    await assertSucceeds(setDoc(inviteRef, rolledBackPendingInvite({ sentAt: current.sentAt })));
    let rolledBack = (await getDoc(inviteRef)).data();
    assert.equal(rolledBack.rolledBackClaimID, "claim-current");
    assert.equal(rolledBack.acceptClaimID, undefined);
    assert.equal(rolledBack.acceptingAt, undefined);
    assert.equal(rolledBack.generation, current.generation);
    assert.equal(rolledBack.roomInstanceID, current.roomInstanceID);

    current = acceptingInvite({ sentAgoMS: 31_000 });
    await seedInvite(current);
    await assertFails(setDoc(
      inviteRef, rolledBackPendingInvite({ sentAt: current.sentAt })
    ));
    current = acceptingInvite({ sentAgoMS: 1_000 });
    await seedInvite(current);
    await assertFails(setDoc(
      inviteRef,
      rolledBackPendingInvite({ sentAt: current.sentAt, generation: 2 })
    ));
    await assertFails(setDoc(
      inviteRef,
      pendingInvite({ sentAt: current.sentAt })
    ));
    await assertFails(setDoc(
      inviteRef,
      rolledBackPendingInvite({ sentAt: current.sentAt, claimID: "claim-stale" })
    ));
  });

  it("removes rollback proof on the next recipient claim", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    await seedUser("bob", "BOB001", "Bob");
    await seedMutualFriends();
    const sentAt = new Date(Date.now() - 1_000);
    const bobDB = testEnv.authenticatedContext("bob").firestore();
    const bobRef = doc(bobDB, "users", "bob", "invites", inviteDocumentID());
    await seedInvite(rolledBackPendingInvite({ sentAt }));

    await assertSucceeds(setDoc(bobRef, {
      ...pendingInvite({ sentAt }),
      status: "accepting",
      acceptClaimID: "claim-next",
      acceptingAt: serverTimestamp(),
    }));
    assert.equal((await getDoc(bobRef)).data().rolledBackClaimID, undefined);
  });

  it("rejects old-claim finalize and rollback after the server advances generation", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    await seedUser("bob", "BOB001", "Bob");
    await seedMutualFriends();
    const oldClaim = acceptingInvite({ sentAgoMS: 12_000, acceptingAgoMS: 11_000 });
    await seedInvite(pendingInvite({ generation: 2, sentAt: new Date() }));
    const bobRef = doc(
      testEnv.authenticatedContext("bob").firestore(),
      "users", "bob", "invites", inviteDocumentID()
    );

    await assertFails(setDoc(bobRef, {
      ...oldClaim,
      status: "accepted",
      acceptedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(bobRef, rolledBackPendingInvite({
      sentAt: oldClaim.sentAt,
      generation: oldClaim.generation,
    })));
  });

  it("rejects client delete and limits reads to recipient and sender-specific get", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    await seedUser("bob", "BOB001", "Bob");
    await seedInvite(pendingInvite({ sentAt: new Date() }));
    const aliceDB = testEnv.authenticatedContext("alice").firestore();
    const bobDB = testEnv.authenticatedContext("bob").firestore();
    const malloryDB = testEnv.authenticatedContext("mallory").firestore();
    const aliceRef = doc(aliceDB, "users", "bob", "invites", inviteDocumentID());

    await assertSucceeds(getDoc(aliceRef));
    await assertSucceeds(getDoc(doc(
      aliceDB, "users", "bob", "invites", inviteDocumentID("new-room-instance")
    )));
    await assertSucceeds(getDoc(doc(bobDB, "users", "bob", "invites", inviteDocumentID())));
    await assertSucceeds(getDocs(collection(bobDB, "users", "bob", "invites")));
    await assertFails(getDocs(collection(aliceDB, "users", "bob", "invites")));
    await assertFails(getDoc(doc(malloryDB, "users", "bob", "invites", inviteDocumentID())));
    await assertFails(deleteDoc(aliceRef));
    await assertFails(deleteDoc(doc(bobDB, "users", "bob", "invites", inviteDocumentID())));
  });

  it("allows the client-shaped friend flow but rejects its direct invite write", async () => {
    await seedUser("bob", "BOB001", "Bob");
    const aliceDB = testEnv.authenticatedContext("alice").firestore();
    const bobDB = testEnv.authenticatedContext("bob").firestore();

    const profileBatch = writeBatch(aliceDB);
    profileBatch.set(doc(aliceDB, "users", "alice"), {
      nickname: "Alice",
      friendCode: "ALICE1",
      icon: "📚",
      bio: "英単語を勉強中",
      createdAt: new Date(),
    });
    profileBatch.set(doc(aliceDB, "friendCodes", "ALICE1"), { uid: "alice" });
    await assertSucceeds(profileBatch.commit());

    const codeSnapshot = await getDoc(doc(aliceDB, "friendCodes", "BOB001"));
    const friendUID = codeSnapshot.data().uid;
    const requestRef = doc(aliceDB, "users", friendUID, "friendRequests", "alice");
    const sentRequestRef = doc(aliceDB, "users", "alice", "sentFriendRequests", friendUID);
    const requestBatch = writeBatch(aliceDB);
    requestBatch.set(requestRef, {
      fromUID: "alice",
      fromNickname: "Alice",
      fromFriendCode: "ALICE1",
      createdAt: serverTimestamp(),
    });
    requestBatch.set(sentRequestRef, {
      toUID: friendUID,
      toNickname: "Bob",
      toFriendCode: "BOB001",
      createdAt: serverTimestamp(),
    });
    await assertSucceeds(requestBatch.commit());
    await assertSucceeds(getDoc(requestRef));
    await assertSucceeds(getDocs(collection(bobDB, "users", "bob", "friendRequests")));
    await assertSucceeds(getDoc(sentRequestRef));
    await assertSucceeds(getDocs(collection(aliceDB, "users", "alice", "sentFriendRequests")));
    await assertFails(getDoc(doc(bobDB, "users", "alice", "sentFriendRequests", "bob")));

    const aliceProfile = (await getDoc(doc(bobDB, "users", "alice"))).data();
    const bobProfile = (await getDoc(doc(bobDB, "users", "bob"))).data();
    const acceptance = writeBatch(bobDB);
    acceptance.set(doc(bobDB, "users", "bob", "friends", "alice"), {
      nickname: aliceProfile.nickname,
      friendCode: aliceProfile.friendCode,
      icon: aliceProfile.icon ?? "",
      bio: aliceProfile.bio ?? "",
      addedAt: serverTimestamp(),
    });
    acceptance.set(doc(bobDB, "users", "alice", "friends", "bob"), {
      nickname: bobProfile.nickname,
      friendCode: bobProfile.friendCode,
      icon: bobProfile.icon ?? "",
      bio: bobProfile.bio ?? "",
      addedAt: serverTimestamp(),
    });
    acceptance.delete(doc(bobDB, "users", "bob", "friendRequests", "alice"));
    acceptance.delete(doc(bobDB, "users", "alice", "sentFriendRequests", "bob"));
    await assertSucceeds(acceptance.commit());

    await assertSucceeds(getDoc(doc(aliceDB, "users", "alice", "friends", "bob")));
    await assertSucceeds(getDoc(doc(bobDB, "users", "bob", "friends", "alice")));
    await assertFails(setDoc(
      doc(aliceDB, "users", friendUID, "invites", inviteDocumentID()),
      pendingInvite()
    ));
  });

  it("requires a paired request, rejects spoofing, and lets the receiver decline both records", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    await seedUser("bob", "BOB001", "Bob");
    const aliceDB = testEnv.authenticatedContext("alice").firestore();
    const bobDB = testEnv.authenticatedContext("bob").firestore();

    await assertFails(setDoc(doc(aliceDB, "users", "alice", "friends", "bob"), {
      nickname: "Bob",
      friendCode: "BOB001",
      icon: "",
      bio: "",
      addedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(aliceDB, "users", "bob", "friendRequests", "alice"), {
      fromUID: "alice",
      fromNickname: "Not Alice",
      fromFriendCode: "ALICE1",
      createdAt: serverTimestamp(),
    }));

    const request = doc(aliceDB, "users", "bob", "friendRequests", "alice");
    const sentRequest = doc(aliceDB, "users", "alice", "sentFriendRequests", "bob");
    await assertFails(setDoc(request, {
      fromUID: "alice",
      fromNickname: "Alice",
      fromFriendCode: "ALICE1",
      createdAt: serverTimestamp(),
    }));

    const spoofedPair = writeBatch(aliceDB);
    spoofedPair.set(request, {
      fromUID: "alice",
      fromNickname: "Alice",
      fromFriendCode: "ALICE1",
      createdAt: serverTimestamp(),
    });
    spoofedPair.set(sentRequest, {
      toUID: "bob",
      toNickname: "Not Bob",
      toFriendCode: "BOB001",
      createdAt: serverTimestamp(),
    });
    await assertFails(spoofedPair.commit());

    const requestPair = writeBatch(aliceDB);
    requestPair.set(request, {
      fromUID: "alice",
      fromNickname: "Alice",
      fromFriendCode: "ALICE1",
      createdAt: serverTimestamp(),
    });
    requestPair.set(sentRequest, {
      toUID: "bob",
      toNickname: "Bob",
      toFriendCode: "BOB001",
      createdAt: serverTimestamp(),
    });
    await assertSucceeds(requestPair.commit());
    await assertFails(deleteDoc(request));
    await assertFails(deleteDoc(doc(bobDB, "users", "bob", "friendRequests", "alice")));

    const decline = writeBatch(bobDB);
    decline.delete(doc(bobDB, "users", "bob", "friendRequests", "alice"));
    decline.delete(doc(bobDB, "users", "alice", "sentFriendRequests", "bob"));
    await assertSucceeds(decline.commit());
  });

  it("lets the sender add a missing sent-request mirror to a legacy incoming request", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    await seedUser("bob", "BOB001", "Bob");
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users", "bob", "friendRequests", "alice"), {
        fromUID: "alice",
        fromNickname: "Alice",
        fromFriendCode: "ALICE1",
        createdAt: new Date(),
      });
    });

    const aliceDB = testEnv.authenticatedContext("alice").firestore();
    await assertSucceeds(setDoc(
      doc(aliceDB, "users", "alice", "sentFriendRequests", "bob"),
      {
        toUID: "bob",
        toNickname: "Bob",
        toFriendCode: "BOB001",
        createdAt: serverTimestamp(),
      }
    ));
  });

  it("lets the sender restore a missing incoming request from its sent-request mirror", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    await seedUser("bob", "BOB001", "Bob");
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users", "alice", "sentFriendRequests", "bob"), {
        toUID: "bob",
        toNickname: "Bob",
        toFriendCode: "BOB001",
        createdAt: new Date(),
      });
    });

    const aliceDB = testEnv.authenticatedContext("alice").firestore();
    await assertSucceeds(setDoc(
      doc(aliceDB, "users", "bob", "friendRequests", "alice"),
      {
        fromUID: "alice",
        fromNickname: "Alice",
        fromFriendCode: "ALICE1",
        createdAt: serverTimestamp(),
      }
    ));
  });

  it("removes both sides of a mutual friendship in one batch", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    await seedUser("bob", "BOB001", "Bob");
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const addedAt = new Date();
      await setDoc(doc(db, "users", "alice", "friends", "bob"), {
        nickname: "Bob", friendCode: "BOB001", icon: "", bio: "", addedAt,
      });
      await setDoc(doc(db, "users", "bob", "friends", "alice"), {
        nickname: "Alice", friendCode: "ALICE1", icon: "", bio: "", addedAt,
      });
    });

    const aliceDB = testEnv.authenticatedContext("alice").firestore();
    await assertFails(deleteDoc(doc(aliceDB, "users", "alice", "friends", "bob")));
    const removal = writeBatch(aliceDB);
    removal.delete(doc(aliceDB, "users", "alice", "friends", "bob"));
    removal.delete(doc(aliceDB, "users", "bob", "friends", "alice"));
    await assertSucceeds(removal.commit());
  });

  it("upgrades a legacy one-way friendship through request acceptance", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    await seedUser("bob", "BOB001", "Bob");
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users", "alice", "friends", "bob"), {
        nickname: "Bob", friendCode: "BOB001", icon: "", bio: "", addedAt: new Date(),
      });
    });

    const aliceDB = testEnv.authenticatedContext("alice").firestore();
    const bobDB = testEnv.authenticatedContext("bob").firestore();
    await assertSucceeds(getDoc(doc(bobDB, "users", "alice", "friends", "bob")));
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users", "alice", "friendRequests", "bob"), {
        fromUID: "bob",
        fromNickname: "Bob",
        fromFriendCode: "BOB001",
        createdAt: new Date(),
      });
    });

    const acceptance = writeBatch(aliceDB);
    acceptance.set(doc(aliceDB, "users", "alice", "friends", "bob"), {
      nickname: "Bob", friendCode: "BOB001", icon: "", bio: "", addedAt: serverTimestamp(),
    });
    acceptance.set(doc(aliceDB, "users", "bob", "friends", "alice"), {
      nickname: "Alice", friendCode: "ALICE1", icon: "", bio: "", addedAt: serverTimestamp(),
    });
    acceptance.delete(doc(aliceDB, "users", "alice", "friendRequests", "bob"));
    acceptance.delete(doc(aliceDB, "users", "bob", "sentFriendRequests", "alice"));
    await assertSucceeds(acceptance.commit());
  });

  it("validates profile icons and biography length", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    const db = testEnv.authenticatedContext("alice").firestore();
    const profile = doc(db, "users", "alice");

    await assertSucceeds(setDoc(profile, {
      icon: "⭐️",
      bio: "a".repeat(140),
    }, { merge: true }));
    await assertFails(setDoc(profile, { icon: "not-an-icon" }, { merge: true }));
    await assertFails(setDoc(profile, { bio: "a".repeat(141) }, { merge: true }));
  });
});

describe("Realtime Database rules", () => {
  it("allows only an authenticated host to create a room", async () => {
    const room = {
      roomInstanceID: "room-instance",
      hostID: "host",
      status: "waiting",
      createdAt: 1,
      settings: { questionCount: 10 },
      playerSlots: { 0: "host" },
      players: {
        host: {
          nickname: "Host", score: 0, joinedAt: 1, roomInstanceID: "room-instance", slot: 0,
        },
      },
    };
    const unauthenticatedDB = testEnv.unauthenticatedContext().database();
    const hostDB = testEnv.authenticatedContext("host").database();
    await assertFails(get(ref(unauthenticatedDB, "rooms/1234")));
    await assertSucceeds(get(ref(hostDB, "rooms/1234")));
    await assertFails(set(ref(unauthenticatedDB, "rooms/1234"), room));
    await assertSucceeds(set(ref(hostDB, "rooms/1234"), room));
    await assertFails(set(ref(testEnv.authenticatedContext("guest").database(), "rooms/5678"), room));
    await assertFails(set(ref(hostDB, "rooms/9012"), {
      ...room,
      playerSlots: { 1: "host" },
      players: { host: { ...room.players.host, slot: 1 } },
    }));
  });

  it("requires an immutable roomInstanceID on room creation", async () => {
    const hostDB = testEnv.authenticatedContext("host").database();
    const room = {
      roomInstanceID: "room-instance",
      hostID: "host",
      status: "waiting",
      createdAt: 1,
      settings: { questionCount: 10 },
      playerSlots: { 0: "host" },
      players: {
        host: {
          nickname: "Host", score: 0, joinedAt: 1, roomInstanceID: "room-instance", slot: 0,
        },
      },
    };

    const { roomInstanceID, ...missingInstanceID } = room;
    await assertFails(set(ref(hostDB, "rooms/1234"), missingInstanceID));
    await assertSucceeds(set(ref(hostDB, "rooms/1234"), room));
    await assertFails(set(ref(hostDB, "rooms/1234/roomInstanceID"), "replacement-instance"));
  });

  it("allows signed-in users to inspect waiting rooms but restricts playing rooms to participants", async () => {
    await seedRoom({ status: "waiting" });
    await assertSucceeds(get(ref(testEnv.authenticatedContext("outsider").database(), "rooms/1234")));

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await update(ref(context.database(), "rooms/1234"), { status: "playing" });
    });
    await assertFails(get(ref(testEnv.authenticatedContext("outsider").database(), "rooms/1234")));
    await assertSucceeds(get(ref(testEnv.authenticatedContext("guest").database(), "rooms/1234")));
  });

  it("requires a player to use its own previously reserved empty slot", async () => {
    await seedRoom({ status: "waiting" });
    const guestDB = testEnv.authenticatedContext("newGuest").database();
    await assertSucceeds(joinPlayer(guestDB, "newGuest", 2, { nickname: "New Guest" }));
    await assertFails(set(ref(guestDB, "rooms/1234/players/newGuest/score"), 99));

    const playerOnlyDB = testEnv.authenticatedContext("playerOnly").database();
    await assertFails(set(
      ref(playerOnlyDB, "rooms/1234/players/playerOnly"),
      playerPayload("playerOnly", 3)
    ));
    const slotOnlyDB = testEnv.authenticatedContext("slotOnly").database();
    await assertSucceeds(set(ref(slotOnlyDB, "rooms/1234/playerSlots/3"), "slotOnly"));
    await assertFails(set(
      ref(slotOnlyDB, "rooms/1234/players/differentUID"),
      playerPayload("differentUID", 3)
    ));
    await assertSucceeds(remove(ref(slotOnlyDB, "rooms/1234/playerSlots/3")));
  });

  it("rejects UID, slot, and roomInstanceID mismatches", async () => {
    await seedRoom({ status: "waiting" });
    const guestDB = testEnv.authenticatedContext("newGuest").database();
    await assertFails(joinPlayer(guestDB, "newGuest", 2, {
      roomInstanceID: "old-room-instance",
    }));
    await assertFails(update(ref(guestDB, "rooms/1234"), {
      "playerSlots/2": "differentUID",
      "players/newGuest": playerPayload("newGuest", 2),
    }));
    await assertFails(update(ref(guestDB, "rooms/1234"), {
      "playerSlots/2": "newGuest",
      "players/newGuest": playerPayload("newGuest", 3),
    }));
  });

  it("rejects occupied, out-of-range, and duplicate slot claims", async () => {
    await seedRoom({ status: "waiting" });
    const newGuestDB = testEnv.authenticatedContext("newGuest").database();
    await assertFails(joinPlayer(newGuestDB, "newGuest", 1));
    await assertFails(joinPlayer(newGuestDB, "newGuest", 8));
    await assertFails(update(ref(newGuestDB, "rooms/1234"), {
      "playerSlots/2": "newGuest",
      "playerSlots/3": "newGuest",
      "players/newGuest": playerPayload("newGuest", 2),
    }));
  });

  it("allows the eighth player and rejects the ninth", async () => {
    await seedRoom({ status: "waiting" });
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const updates = {};
      for (let slot = 2; slot <= 6; slot += 1) {
        const uid = `player${slot + 1}`;
        updates[`playerSlots/${slot}`] = uid;
        updates[`players/${uid}`] = playerPayload(uid, slot);
      }
      await update(ref(context.database(), "rooms/1234"), updates);
    });

    const eighthDB = testEnv.authenticatedContext("player8").database();
    await assertSucceeds(joinPlayer(eighthDB, "player8", 7));

    const ninthDB = testEnv.authenticatedContext("player9").database();
    await assertFails(joinPlayer(ninthDB, "player9", 8));
  });

  it("allows only the host to add NPCs into the remaining eight player slots", async () => {
    await seedRoom({ status: "waiting" });
    const hostDB = testEnv.authenticatedContext("host").database();
    const guestDB = testEnv.authenticatedContext("guest").database();

    await assertFails(addNPC(guestDB, "cpu-normal", 2));
    await assertSucceeds(addNPC(hostDB, "cpu-normal", 2));
    await assertSucceeds(addNPC(hostDB, "cpu-strong", 3));
    assert.equal(
      (await get(ref(guestDB, "rooms/1234/players/cpu-normal/nickname"))).val(),
      "cpu-normal"
    );

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const updates = {};
      for (let slot = 4; slot <= 7; slot += 1) {
        const profileID = `cpu-fill-${slot}`;
        updates[`playerSlots/${slot}`] = profileID;
        updates[`players/${profileID}`] = playerPayload(profileID, slot);
      }
      await update(ref(context.database(), "rooms/1234"), updates);
    });

    assert.equal((await get(ref(hostDB, "rooms/1234/players"))).size, 8);
    await assertFails(addNPC(hostDB, "cpu-ninth", 8));
    await assertFails(set(ref(hostDB, "rooms/1234/players/cpu-without-slot"),
      playerPayload("cpu-without-slot", 7)));
  });

  it("treats an existing UID join as idempotent without changing score or joinedAt", async () => {
    await seedRoom({ status: "waiting" });
    const guestDB = testEnv.authenticatedContext("guest").database();
    const playerRef = ref(guestDB, "rooms/1234/players/guest");
    const before = (await get(playerRef)).val();

    const result = await runTransaction(playerRef, (current) => {
      if (current != null) return;
      return {
        nickname: "Changed",
        score: 0,
        joinedAt: 999,
        roomInstanceID: "room-instance",
        slot: 1,
      };
    }, { applyLocally: false });

    const after = (await get(playerRef)).val();
    assert.equal(result.committed, false);
    assert.equal(after.score, before.score);
    assert.equal(after.joinedAt, before.joinedAt);
    assert.equal(after.nickname, before.nickname);
    assert.equal(after.slot, before.slot);
    assert.equal((await get(ref(guestDB, "rooms/1234/playerSlots/1"))).val(), "guest");
  });

  it("rejects joining after the match starts", async () => {
    await seedRoom();
    const lateGuestDB = testEnv.authenticatedContext("lateGuest").database();
    await assertFails(joinPlayer(lateGuestDB, "lateGuest", 2));
  });

  it("allows a participant disconnect cleanup without cross-branch rule dependency", async () => {
    await seedRoom();
    const guestDB = testEnv.authenticatedContext("guest").database();
    const outsiderDB = testEnv.authenticatedContext("outsider").database();

    await assertFails(remove(ref(outsiderDB, "rooms/1234/players/guest")));
    await assertFails(remove(ref(outsiderDB, "rooms/1234/playerSlots/1")));
    await assertSucceeds(leavePlayer(guestDB, "guest", 1));
  });

  it("allows only one of two users to claim the same slot concurrently", async () => {
    await seedRoom({ status: "waiting" });
    const firstDB = testEnv.authenticatedContext("first").database();
    const secondDB = testEnv.authenticatedContext("second").database();
    const results = await Promise.allSettled([
      joinPlayer(firstDB, "first", 2),
      joinPlayer(secondDB, "second", 2),
    ]);
    assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  });

  it("allows only the host to update game state and scores", async () => {
    await seedRoom();
    const hostDB = testEnv.authenticatedContext("host").database();
    const guestDB = testEnv.authenticatedContext("guest").database();
    await assertSucceeds(update(ref(hostDB, "rooms/1234"), {
      "game/phase": "reveal",
      "players/guest/score": 1,
    }));
    await assertFails(set(ref(guestDB, "rooms/1234/game/phase"), "finished"));
    await assertFails(set(ref(guestDB, "rooms/1234/players/guest/score"), 99));
  });

  it("lets the host close answering with a game transaction and rejects later answers", async () => {
    await seedRoom();
    const hostDB = testEnv.authenticatedContext("host").database();
    const guestDB = testEnv.authenticatedContext("guest").database();

    await assertSucceeds(set(ref(hostDB, "rooms/1234/game/answers/host"), {
      questionIndex: 0,
      choice: "answer",
      ts: 100,
      visibleCount: 3,
    }));
    await assertSucceeds(runTransaction(ref(hostDB, "rooms/1234/game"), (game) => ({
      ...game,
      phase: "reveal",
    }), { applyLocally: false }));
    await assertSucceeds(update(ref(hostDB, "rooms/1234"), {
      "players/host/score": 20,
      "game/answers": {
        host: {
          questionIndex: 0,
          choice: "answer",
          ts: 100,
          visibleCount: 3,
        },
      },
      "game/failed": null,
      "game/reveal": {
        correctAnswer: "answer",
        correctIDs: ["host"],
      },
    }));
    await assertFails(set(ref(guestDB, "rooms/1234/game/answers/guest"), {
      questionIndex: 0,
      choice: "answer",
      ts: 101,
      visibleCount: 3,
    }));
  });

  it("allows the client-shaped flow from room creation through a guest answer", async () => {
    const hostDB = testEnv.authenticatedContext("host").database();
    const guestDB = testEnv.authenticatedContext("guest").database();
    const roomRef = ref(hostDB, "rooms/4321");

    await assertSucceeds(get(roomRef));
    await assertSucceeds(set(roomRef, {
      roomInstanceID: "room-instance-4321",
      hostID: "host",
      status: "waiting",
      createdAt: 1,
      settings: {
        questionCount: 5,
        timeLimit: 5,
        genre: "englishWord",
        wordCategory: "junior_high",
        wordDifficulty: 1,
      },
      playerSlots: { 0: "host" },
      players: {
        host: {
          nickname: "Host", score: 0, joinedAt: 1,
          roomInstanceID: "room-instance-4321", slot: 0,
        },
      },
    }));
    await assertSucceeds(get(ref(guestDB, "rooms/4321")));
    await assertSucceeds(set(ref(guestDB, "rooms/4321/playerSlots/1"), "guest"));
    await assertSucceeds(set(
      ref(guestDB, "rooms/4321/players/guest"),
      playerPayload("guest", 1, {
        nickname: "Guest", roomInstanceID: "room-instance-4321",
        joinedAt: databaseServerTimestamp(),
      })
    ));
    await assertSucceeds(update(roomRef, {
      status: "playing",
      questions: [{
        id: "jh_0001",
        text: "apple",
        choices: ["りんご", "本", "水", "犬"],
        answer: "りんご",
      }],
      game: {
        questionIndex: 0,
        phase: "question",
        startDelayMS: 0,
        startedAt: 10,
      },
    }));
    await assertSucceeds(set(ref(guestDB, "rooms/4321/game/answers/guest"), {
      questionIndex: 0,
      choice: "りんご",
      ts: 11,
      visibleCount: 3,
    }));
    await assertSucceeds(update(roomRef, {
      "players/guest/score": 20,
      "game/phase": "reveal",
      "game/reveal": {
        correctAnswer: "りんご",
        correctIDs: ["guest"],
      },
    }));
    await assertSucceeds(update(roomRef, {
      status: "finished",
      "game/phase": "finished",
    }));
  });

  it("lets a participant submit only their first well-formed answer during a question", async () => {
    await seedRoom();
    const guestDB = testEnv.authenticatedContext("guest").database();
    const answer = {
      questionIndex: 0,
      choice: "answer",
      ts: 100,
      visibleCount: 3,
    };

    await assertSucceeds(set(ref(guestDB, "rooms/1234/game/answers/guest"), answer));
    await assertFails(set(ref(guestDB, "rooms/1234/game/answers/guest"), {
      ...answer,
      choice: "rewritten",
    }));
    await assertFails(set(ref(guestDB, "rooms/1234/game/answers/host"), answer));
  });

  it("rejects answers from outsiders, outside the question phase, and with invalid fields", async () => {
    await seedRoom();
    const answer = {
      questionIndex: 0,
      choice: "answer",
      ts: 100,
      visibleCount: 3,
    };
    const outsiderDB = testEnv.authenticatedContext("outsider").database();
    const guestDB = testEnv.authenticatedContext("guest").database();

    await assertFails(set(ref(outsiderDB, "rooms/1234/game/answers/outsider"), answer));
    await assertFails(set(ref(guestDB, "rooms/1234/game/answers/guest"), {
      ...answer,
      visibleCount: -1,
    }));
    await assertFails(set(ref(guestDB, "rooms/1234/game/answers/guest"), {
      ...answer,
      unexpected: true,
    }));

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await set(ref(context.database(), "rooms/1234/game/phase"), "reveal");
    });
    await assertFails(set(ref(guestDB, "rooms/1234/game/answers/guest"), answer));
  });

  it("rejects an answer that belongs to a previous question", async () => {
    await seedRoom();
    const guestDB = testEnv.authenticatedContext("guest").database();

    await assertFails(set(ref(guestDB, "rooms/1234/game/answers/guest"), {
      questionIndex: -1,
      choice: "late answer",
      ts: 100,
      visibleCount: 3,
    }));
  });

  it("accepts only an お手つき tagged for the current question", async () => {
    await seedRoom();
    const hostDB = testEnv.authenticatedContext("host").database();

    await assertSucceeds(set(ref(hostDB, "rooms/1234/game/failed/guest"), {
      questionIndex: 0,
    }));
    await assertFails(set(ref(hostDB, "rooms/1234/game/failed/host"), {
      questionIndex: -1,
    }));
  });
});
