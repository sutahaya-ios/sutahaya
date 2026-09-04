const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, before, beforeEach, describe, it } = require("node:test");
const { initializeTestEnvironment } = require("@firebase/rules-unit-testing");
const { deleteApp, initializeApp } = require("firebase/app");
const { connectAuthEmulator, getAuth, signInAnonymously } = require("firebase/auth");
const {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} = require("firebase/functions");
const { collection, doc, getDoc, getDocs, setDoc } = require("firebase/firestore");
const { ref, set } = require("firebase/database");

const projectId = "demo-hayaosiapp";
const rootDir = path.resolve(__dirname, "..");
const region = "asia-northeast1";
const roomCode = "1234";
const roomInstanceID = "room-instance";

let testEnv;
let clientApps = [];

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
  await Promise.all(clientApps.map((app) => deleteApp(app)));
  await testEnv.cleanup();
});

async function createClient() {
  const app = initializeApp({
    apiKey: "demo-key",
    authDomain: `${projectId}.firebaseapp.com`,
    projectId,
  }, `functions-test-${randomUUID()}`);
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  const credential = await signInAnonymously(auth);
  const functions = getFunctions(app, region);
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);
  return { uid: credential.user.uid, functions };
}

async function seedScenario(hostUID, guestUID, { mutualFriends = true, status = "waiting" } = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(doc(firestore, "users", hostUID), {
      nickname: "Host",
      friendCode: "HOST01",
      createdAt: new Date(),
    });
    await setDoc(doc(firestore, "users", guestUID), {
      nickname: "Guest",
      friendCode: "GUEST1",
      createdAt: new Date(),
    });
    if (mutualFriends) {
      await setDoc(doc(firestore, "users", hostUID, "friends", guestUID), {
        nickname: "Guest",
        friendCode: "GUEST1",
        addedAt: new Date(),
      });
      await setDoc(doc(firestore, "users", guestUID, "friends", hostUID), {
        nickname: "Host",
        friendCode: "HOST01",
        addedAt: new Date(),
      });
    }

    await set(ref(context.database(), `rooms/${roomCode}`), {
      roomInstanceID,
      hostID: hostUID,
      status,
      playerSlots: { 0: hostUID, 1: guestUID },
      players: {
        [hostUID]: { nickname: "Host", score: 0, joinedAt: 1, roomInstanceID, slot: 0 },
        [guestUID]: { nickname: "Guest", score: 0, joinedAt: 2, roomInstanceID, slot: 1 },
      },
    });
  });
}

async function seedInvite(hostUID, guestUID, data) {
  const inviteID = `${roomInstanceID}_${hostUID}`;
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users", guestUID, "invites", inviteID), {
      roomInstanceID,
      roomCode,
      fromUID: hostUID,
      toUID: guestUID,
      fromNickname: "Host",
      status: "pending",
      generation: 1,
      sentAt: new Date(Date.now() - 11_000),
      ...data,
    });
  });
}

async function savedInvites(guestUID) {
  let invites = [];
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const snapshot = await getDocs(collection(
      context.firestore(), "users", guestUID, "invites"
    ));
    invites = snapshot.docs.map((document) => ({ id: document.id, ...document.data() }));
  });
  return invites;
}

function callSendInvite(functions, friendUID, overrides = {}) {
  return httpsCallable(functions, "sendRoomInvite")({
    friendUID,
    roomCode,
    roomInstanceID,
    ...overrides,
  });
}

describe("sendRoomInvite callable", { concurrency: false }, () => {
  it("creates one canonical generation-1 invite for the real host", async () => {
    const host = await createClient();
    const guest = await createClient();
    await seedScenario(host.uid, guest.uid);

    const result = await callSendInvite(host.functions, guest.uid);
    const invites = await savedInvites(guest.uid);

    assert.equal(result.data.inviteID, `${roomInstanceID}_${host.uid}`);
    assert.equal(result.data.generation, 1);
    assert.equal(invites.length, 1);
    assert.equal(invites[0].fromUID, host.uid);
    assert.equal(invites[0].status, "pending");
  });

  it("rejects a mutual-friend guest even when a modified client calls the function", async () => {
    const host = await createClient();
    const guest = await createClient();
    await seedScenario(host.uid, guest.uid);

    await assert.rejects(
      callSendInvite(guest.functions, host.uid),
      (error) => error.code === "functions/permission-denied"
        && error.details?.reason === "not-host"
    );
    assert.equal((await savedInvites(host.uid)).length, 0);
  });

  it("rejects a host request when the recipient is not a mutual friend", async () => {
    const host = await createClient();
    const guest = await createClient();
    await seedScenario(host.uid, guest.uid, { mutualFriends: false });

    await assert.rejects(
      callSendInvite(host.functions, guest.uid),
      (error) => error.code === "functions/permission-denied"
        && error.details?.reason === "not-mutual-friends"
    );
  });

  it("rejects a stale room instance and a room that is no longer waiting", async () => {
    const host = await createClient();
    const guest = await createClient();
    await seedScenario(host.uid, guest.uid);

    await assert.rejects(
      callSendInvite(host.functions, guest.uid, { roomInstanceID: "stale-instance" }),
      (error) => error.code === "functions/failed-precondition"
        && error.details?.reason === "stale-room"
    );

    await seedScenario(host.uid, guest.uid, { status: "playing" });
    await assert.rejects(
      callSendInvite(host.functions, guest.uid),
      (error) => error.code === "functions/failed-precondition"
        && error.details?.reason === "room-not-waiting"
    );
  });

  it("enforces cooldown and then advances the same document generation", async () => {
    const host = await createClient();
    const guest = await createClient();
    await seedScenario(host.uid, guest.uid);
    await seedInvite(host.uid, guest.uid, { sentAt: new Date(Date.now() - 9_000) });

    await assert.rejects(
      callSendInvite(host.functions, guest.uid),
      (error) => error.code === "functions/resource-exhausted"
        && error.details?.reason === "cooldown"
    );

    await seedInvite(host.uid, guest.uid, {
      status: "accepted",
      acceptingAt: new Date(Date.now() - 11_000),
      acceptedAt: new Date(),
      acceptClaimID: "claim-old",
      sentAt: new Date(Date.now() - 11_000),
    });
    const result = await callSendInvite(host.functions, guest.uid);
    const invites = await savedInvites(guest.uid);

    assert.equal(result.data.generation, 2);
    assert.equal(invites.length, 1);
    assert.equal(invites[0].generation, 2);
    assert.equal(invites[0].acceptClaimID, undefined);
    assert.equal(invites[0].status, "pending");
  });

  it("does not replace an invite during its active accepting lease", async () => {
    const host = await createClient();
    const guest = await createClient();
    await seedScenario(host.uid, guest.uid);
    await seedInvite(host.uid, guest.uid, {
      status: "accepting",
      acceptClaimID: "claim-current",
      acceptingAt: new Date(Date.now() - 9_000),
      sentAt: new Date(Date.now() - 11_000),
    });

    await assert.rejects(
      callSendInvite(host.functions, guest.uid),
      (error) => error.code === "functions/aborted"
        && error.details?.reason === "claim-in-progress"
    );
    assert.equal((await savedInvites(guest.uid))[0].generation, 1);
  });
});
