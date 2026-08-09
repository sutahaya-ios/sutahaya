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

  it("allows the client-shaped profile, friend lookup, friend add, and invite flow", async () => {
    await seedUser("bob", "BOB001", "Bob");
    const aliceDB = testEnv.authenticatedContext("alice").firestore();

    const profileBatch = writeBatch(aliceDB);
    profileBatch.set(doc(aliceDB, "users", "alice"), {
      nickname: "Alice",
      friendCode: "ALICE1",
      createdAt: new Date(),
    });
    profileBatch.set(doc(aliceDB, "friendCodes", "ALICE1"), { uid: "alice" });
    await assertSucceeds(profileBatch.commit());

    const codeSnapshot = await getDoc(doc(aliceDB, "friendCodes", "BOB001"));
    const friendUID = codeSnapshot.data().uid;
    const profileSnapshot = await getDoc(doc(aliceDB, "users", friendUID));
    await assertSucceeds(setDoc(doc(aliceDB, "users", "alice", "friends", friendUID), {
      nickname: profileSnapshot.data().nickname,
      friendCode: "BOB001",
      addedAt: new Date(),
    }));
    await assertSucceeds(setDoc(doc(aliceDB, "users", friendUID, "invites", "client-flow"), {
      roomCode: "1234",
      fromUID: "alice",
      fromNickname: "Alice",
      createdAt: new Date(),
    }));
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
    await assertFails(set(ref(testEnv.unauthenticatedContext().database(), "rooms/1234"), room));
    await assertSucceeds(set(ref(testEnv.authenticatedContext("host").database(), "rooms/1234"), room));
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
});
