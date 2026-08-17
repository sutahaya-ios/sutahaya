const fs = require("node:fs");
const path = require("node:path");
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

async function seedRoom({ status = "playing" } = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), "rooms/1234"), {
      hostID: "host",
      status,
      createdAt: 1,
      settings: { questionCount: 10 },
      players: {
        host: { nickname: "Host", score: 0, joinedAt: 1 },
        guest: { nickname: "Guest", score: 0, joinedAt: 2 },
      },
      game: { questionIndex: 0, phase: "question" },
    });
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

  it("allows invites only when the sender has registered the recipient as a friend", async () => {
    await seedUser("alice", "ALICE1", "Alice");
    await seedUser("bob", "BOB001", "Bob");
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users", "alice", "friends", "bob"), {
        nickname: "Bob",
        friendCode: "BOB001",
        addedAt: new Date(),
      });
    });

    const invite = {
      roomCode: "1234",
      fromUID: "alice",
      fromNickname: "Alice",
      createdAt: new Date(),
    };
    const aliceDB = testEnv.authenticatedContext("alice").firestore();
    const malloryDB = testEnv.authenticatedContext("mallory").firestore();
    const bobDB = testEnv.authenticatedContext("bob").firestore();

    await assertSucceeds(setDoc(doc(aliceDB, "users", "bob", "invites", "allowed"), invite));
    await assertFails(setDoc(doc(malloryDB, "users", "bob", "invites", "blocked"), {
      ...invite,
      fromUID: "mallory",
      fromNickname: "Mallory",
    }));
    await assertSucceeds(getDoc(doc(bobDB, "users", "bob", "invites", "allowed")));
    await assertSucceeds(deleteDoc(doc(bobDB, "users", "bob", "invites", "allowed")));
  });

  it("allows the client-shaped profile, friend request, mutual acceptance, and invite flow", async () => {
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
    await assertSucceeds(setDoc(requestRef, {
      fromUID: "alice",
      fromNickname: "Alice",
      fromFriendCode: "ALICE1",
      createdAt: serverTimestamp(),
    }));
    await assertSucceeds(getDoc(requestRef));
    await assertSucceeds(getDocs(collection(bobDB, "users", "bob", "friendRequests")));

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
    await assertSucceeds(acceptance.commit());

    await assertSucceeds(getDoc(doc(aliceDB, "users", "alice", "friends", "bob")));
    await assertSucceeds(getDoc(doc(bobDB, "users", "bob", "friends", "alice")));
    await assertSucceeds(setDoc(doc(aliceDB, "users", friendUID, "invites", "client-flow"), {
      roomCode: "1234",
      fromUID: "alice",
      fromNickname: "Alice",
      createdAt: new Date(),
    }));
  });

  it("rejects direct or spoofed friend creation and lets the receiver decline a request", async () => {
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
    await assertSucceeds(setDoc(request, {
      fromUID: "alice",
      fromNickname: "Alice",
      fromFriendCode: "ALICE1",
      createdAt: serverTimestamp(),
    }));
    await assertFails(deleteDoc(request));
    await assertSucceeds(deleteDoc(doc(bobDB, "users", "bob", "friendRequests", "alice")));
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
    await assertSucceeds(setDoc(doc(bobDB, "users", "alice", "friendRequests", "bob"), {
      fromUID: "bob",
      fromNickname: "Bob",
      fromFriendCode: "BOB001",
      createdAt: serverTimestamp(),
    }));

    const acceptance = writeBatch(aliceDB);
    acceptance.set(doc(aliceDB, "users", "alice", "friends", "bob"), {
      nickname: "Bob", friendCode: "BOB001", icon: "", bio: "", addedAt: serverTimestamp(),
    });
    acceptance.set(doc(aliceDB, "users", "bob", "friends", "alice"), {
      nickname: "Alice", friendCode: "ALICE1", icon: "", bio: "", addedAt: serverTimestamp(),
    });
    acceptance.delete(doc(aliceDB, "users", "alice", "friendRequests", "bob"));
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
      hostID: "host",
      status: "waiting",
      createdAt: 1,
      settings: { questionCount: 10 },
      players: {
        host: { nickname: "Host", score: 0, joinedAt: 1 },
      },
    };
    const unauthenticatedDB = testEnv.unauthenticatedContext().database();
    const hostDB = testEnv.authenticatedContext("host").database();
    await assertFails(get(ref(unauthenticatedDB, "rooms/1234")));
    await assertSucceeds(get(ref(hostDB, "rooms/1234")));
    await assertFails(set(ref(unauthenticatedDB, "rooms/1234"), room));
    await assertSucceeds(set(ref(hostDB, "rooms/1234"), room));
    await assertFails(set(ref(testEnv.authenticatedContext("guest").database(), "rooms/5678"), room));
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

  it("lets a guest join as themselves but not change their score", async () => {
    await seedRoom({ status: "waiting" });
    const guestDB = testEnv.authenticatedContext("newGuest").database();
    await assertSucceeds(set(ref(guestDB, "rooms/1234/players/newGuest"), {
      nickname: "New Guest",
      score: 0,
      joinedAt: 3,
    }));
    await assertFails(set(ref(guestDB, "rooms/1234/players/newGuest/score"), 99));
    await assertSucceeds(remove(ref(guestDB, "rooms/1234/players/newGuest")));
  });

  it("rejects joining after the match starts", async () => {
    await seedRoom();
    const lateGuestDB = testEnv.authenticatedContext("lateGuest").database();
    await assertFails(set(ref(lateGuestDB, "rooms/1234/players/lateGuest"), {
      nickname: "Late Guest",
      score: 0,
      joinedAt: 3,
    }));
  });

  it("still lets a participant leave after the match starts", async () => {
    await seedRoom();
    const guestDB = testEnv.authenticatedContext("guest").database();
    await assertSucceeds(remove(ref(guestDB, "rooms/1234/players/guest")));
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

  it("allows the client-shaped flow from room creation through a guest answer", async () => {
    const hostDB = testEnv.authenticatedContext("host").database();
    const guestDB = testEnv.authenticatedContext("guest").database();
    const roomRef = ref(hostDB, "rooms/4321");

    await assertSucceeds(get(roomRef));
    await assertSucceeds(set(roomRef, {
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
      players: {
        host: { nickname: "Host", score: 0, joinedAt: 1 },
      },
    }));
    await assertSucceeds(get(ref(guestDB, "rooms/4321")));
    await assertSucceeds(set(ref(guestDB, "rooms/4321/players/guest"), {
      nickname: "Guest",
      score: 0,
      joinedAt: 2,
    }));
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
});
