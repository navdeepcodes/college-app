/**
 * Firestore security-rule tests for the anonymous-chat college room.
 *
 * Runs against the local Firestore emulator (started by
 * `firebase emulators:exec --only firestore` from the project root). The
 * emulator loads ./firestore.rules from firebase.json.
 *
 * 11-scenario security matrix (task #24):
 *   #1  auth — unauthenticated read denied
 *   #2  auth — unauthenticated write denied
 *   #3  isolation — read own college room allowed
 *   #4  isolation — read another college's room denied
 *   #5  isolation — write into another college's room denied
 *   #6  isolation — write own room but forge collegeId denied
 *   #7  identity — forged userId denied
 *   #8  identity — forged anonId denied
 *   #9  immutability — update/delete message denied
 *   #10 ttl — far-future expiresAt (persistence attempt) denied
 *   #11 ttl — expired/past expiresAt denied
 *
 * Plus negative controls (own-room valid write allowed) and room-doc rules.
 */
const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const {
  doc,
  setDoc,
  getDoc,
  deleteDoc,
  updateDoc,
  collection,
  addDoc,
  serverTimestamp,
  Timestamp,
} = require('@firebase/firestore');

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-truekinn';

// FIRESTORE_EMULATOR_HOST is set by `firebase emulators:exec`.
let host = '127.0.0.1';
let port = 8080;
if (process.env.FIRESTORE_EMULATOR_HOST) {
  const [h, p] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  host = h;
  port = Number(p);
}

const NMIT = 'nmit-uid';
const RVCE = 'rvce-uid';
const NMIT_ROOM = 'college_nmit';
const RVCE_ROOM = 'college_rvce';

let testEnv;
let passCount = 0;
let failCount = 0;
const failures = [];

function test(name, fn) {
  return fn()
    .then(() => {
      passCount++;
      console.log(`  ✔ ${name}`);
    })
    .catch((e) => {
      failCount++;
      failures.push({ name, error: e });
      console.log(`  ✘ ${name}\n      ${e.message.split('\n')[0]}`);
    });
}

const now = () => Timestamp.fromDate(new Date());

function msgData(overrides = {}) {
  return Object.assign(
    {
      anonId: 'an_nmit',
      text: 'Hello campus',
      userId: NMIT,
      collegeId: 'nmit',
      createdAt: serverTimestamp(),
      expiresAt: nowAdd(90),
    },
    overrides,
  );
}

function nowAdd(sec) {
  return Timestamp.fromDate(new Date(Date.now() + sec * 1000));
}

async function seed(ctx) {
  const db = ctx.firestore();
  // NMIT and RVCE users with their college identity + anonId.
  await setDoc(doc(db, 'users', NMIT), {
    collegeId: 'nmit',
    anonId: 'an_nmit',
    email: 'student@nmit.ac.in',
    profileCompleted: true,
  });
  await setDoc(doc(db, 'users', RVCE), {
    collegeId: 'rvce',
    anonId: 'an_rvce',
    email: 'student@rvce.edu.in',
    profileCompleted: true,
  });
  // One live (unexpired) message in each college room so read tests are real.
  await setDoc(doc(db, 'anon_chats', NMIT_ROOM, 'messages', 'm1'), {
    anonId: 'an_nmit',
    text: 'first',
    userId: NMIT,
    createdAt: now(),
    expiresAt: nowAdd(90),
  });
  await setDoc(doc(db, 'anon_chats', RVCE_ROOM, 'messages', 'm1'), {
    anonId: 'an_rvce',
    text: 'rvce first',
    userId: RVCE,
    createdAt: now(),
    expiresAt: nowAdd(90),
  });
}

async function main() {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { host, port },
  });

  // seed with rules disabled
  await testEnv.withSecurityRulesDisabled(seed);

  const nmit = testEnv.authenticatedContext(NMIT, {
    email: 'student@nmit.ac.in',
  });
  const anon = testEnv.unauthenticatedContext();
  const nmitDb = nmit.firestore();
  const anonDb = anon.firestore();

  const nmitMsg = (id) =>
    doc(nmitDb, 'anon_chats', NMIT_ROOM, 'messages', id);
  const rvceMsg = (id) =>
    doc(nmitDb, 'anon_chats', RVCE_ROOM, 'messages', id);

  console.log('\n== Anonymous chat security matrix ==');

  // #1/#2 auth required
  await test('#1 unauth read denied', () =>
    assertFails(getDoc(doc(anonDb, 'anon_chats', NMIT_ROOM, 'messages', 'm1'))));
  await test('#2 unauth write denied', () =>
    assertFails(addDoc(collection(anonDb, 'anon_chats', NMIT_ROOM, 'messages'), msgData())));

  // #3/#4 read isolation
  await test('#3 own-college read allowed', () =>
    assertSucceeds(getDoc(nmitMsg('m1'))));
  await test('#4 cross-college read denied', () =>
    assertFails(getDoc(rvceMsg('m1'))));

  // #5/#6 write isolation
  await test('#5 cross-college write denied', () =>
    assertFails(addDoc(collection(nmitDb, 'anon_chats', RVCE_ROOM, 'messages'), msgData({ userId: RVCE, anonId: 'an_rvce' }))));
  await test('#6 own-room write with forged collegeId denied', () =>
    assertFails(addDoc(collection(nmitDb, 'anon_chats', NMIT_ROOM, 'messages'), msgData({ collegeId: 'rvce' }))));

  // #7/#8 identity
  await test('#7 forged userId denied', () =>
    assertFails(addDoc(collection(nmitDb, 'anon_chats', NMIT_ROOM, 'messages'), msgData({ userId: RVCE }))));
  await test('#8 forged anonId denied', () =>
    assertFails(addDoc(collection(nmitDb, 'anon_chats', NMIT_ROOM, 'messages'), msgData({ anonId: 'an_rvce' }))));

  // #9 immutability
  await test('#9a message update denied', () =>
    assertFails(updateDoc(nmitMsg('m1'), { text: 'edited' })));
  await test('#9b message delete denied', () =>
    assertFails(deleteDoc(nmitMsg('m1'))));

  // #10/#11 ttl
  await test('#10 far-future expiresAt denied', () =>
    assertFails(addDoc(collection(nmitDb, 'anon_chats', NMIT_ROOM, 'messages'), msgData({ expiresAt: nowAdd(7200) }))));
  await test('#11 past expiresAt denied', () =>
    assertFails(addDoc(collection(nmitDb, 'anon_chats', NMIT_ROOM, 'messages'), msgData({ expiresAt: nowAdd(-600) }))));

  // negative controls
  await test('control: own-room valid write allowed', () =>
    assertSucceeds(addDoc(collection(nmitDb, 'anon_chats', NMIT_ROOM, 'messages'), msgData())));
  await test('control: empty text denied', () =>
    assertFails(addDoc(collection(nmitDb, 'anon_chats', NMIT_ROOM, 'messages'), msgData({ text: '  ' }))));
  await test('control: expired message not readable', async () => {
  // Seed an already-expired message (bypasses rules), then assert the
  // authenticated NMIT user cannot read it: expiresAt > request.time fails.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'anon_chats', NMIT_ROOM, 'messages', 'expired'), {
      text: 'old',
      userId: NMIT,
      anonId: 'an_nmit',
      createdAt: nowAdd(-1000),
      expiresAt: nowAdd(-100),
    });
  });
  await assertFails(getDoc(nmitMsg('expired')));
});

  // room doc rules
  const roomRef = (id) => doc(nmitDb, 'anon_chats', id);
  await test('control: create own-college room allowed', () =>
    assertSucceeds(setDoc(roomRef(NMIT_ROOM), {
      createdBy: NMIT,
      members: [NMIT],
      collegeId: 'nmit',
    })));
  await test('control: create cross-college room denied', () =>
    assertFails(setDoc(roomRef(RVCE_ROOM), {
      createdBy: NMIT,
      members: [NMIT],
      collegeId: 'rvce',
    })));
  await test('control: room delete denied', () =>
    assertFails(deleteDoc(roomRef(NMIT_ROOM))));

  await testEnv.cleanup();

  console.log(`\n${passCount} passed, ${failCount} failed`);
  // Force-exit: rules-unit-testing keeps live clients (websocket) that would
  // otherwise leave the event loop open and hang `firebase emulators:exec`.
  process.exit(failures.length ? 1 : 0);
}

main().catch((e) => {
  console.error('Test harness error:', e);
  process.exit(1);
});