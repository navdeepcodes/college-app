/**
 * Overnight productionization mission, Part 4: a live, chained,
 * multi-account walkthrough against the real Firestore emulator.
 *
 * This is deliberately NOT another isolated per-rule assertion file like
 * the other functions/test-rules/*.test.js suites. Every other suite in
 * this directory tests one rule at a time against hand-seeded fixtures —
 * which is exactly the blind spot that let the Phase 20 users.read bug
 * (broke every real signup) and the Phase 21 club_members.read bug (broke
 * every non-member's first club view) both ship with 100% green isolated
 * tests. Both were only found by replaying the REAL CLIENT SEQUENCE of
 * operations in order. This file replays realistic sequences — the same
 * order of reads/writes the actual screens issue, per the .dart source —
 * for three synthetic accounts:
 *
 *   A (uid nmit-a) — NMIT
 *   B (uid nmit-b) — NMIT (same college as A)
 *   C (uid rvce-c) — RVCE (different college)
 *
 * and asserts both the "should work" paths (A and B can be friends, chat,
 * share a club, see each other's posts/events) AND the "should stay
 * denied" paths (C must never see A/B's college-scoped data), end to end,
 * using the actual multi-step sequences from:
 *   lib/app/auth_gate.dart (_UserBootstrap._bootstrap)
 *   lib/services/friend_service.dart (sendRequest/acceptRequest)
 *   lib/chat/chat_screen.dart (_ensureChatExists)
 *   lib/clubs/*.dart (create_club_screen, admin_club_requests_screen,
 *     club_profile_screen._RoleActions, club_join_requests_screen,
 *     club_chat_screen)
 *   lib/feed/create_event_screen.dart
 */
const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const {
  doc, setDoc, getDoc, addDoc, updateDoc, deleteDoc, collection,
  serverTimestamp, runTransaction,
} = require('@firebase/firestore');

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-truekinn';

let host = '127.0.0.1';
let port = 8080;
if (process.env.FIRESTORE_EMULATOR_HOST) {
  const [h, p] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  host = h;
  port = Number(p);
}

const ADMIN = 'OImOQirOL7eQNftKASo4FTrF6XA3';
const A = 'nmit-a';
const B = 'nmit-b';
const C = 'rvce-c';

let testEnv;
let passCount = 0;
let failCount = 0;

function test(name, fn) {
  return fn()
    .then(() => { passCount++; console.log(`  ✔ ${name}`); })
    .catch((e) => {
      failCount++;
      console.log(`  ✘ ${name}\n      ${String(e.message || e).split('\n')[0]}`);
    });
}

function pairId(a, b) {
  return [a, b].sort().join('_');
}

async function main() {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { host, port },
  });

  const a = testEnv.authenticatedContext(A, { email: 'a@nmit.ac.in' }).firestore();
  const b = testEnv.authenticatedContext(B, { email: 'b@nmit.ac.in' }).firestore();
  const c = testEnv.authenticatedContext(C, { email: 'c@rvce.edu.in' }).firestore();
  const admin = testEnv.authenticatedContext(ADMIN, { email: 'admin@truekinn.app' }).firestore();

  console.log('\n== Step 1: signup bootstrap (auth_gate.dart _UserBootstrap) ==');
  // Exact sequence: get own doc (doesn't exist) -> create with merge.
  await test('1a A bootstrap: own doc read before it exists succeeds', () =>
    assertSucceeds(getDoc(doc(a, 'users', A))));
  await test('1b A bootstrap create', () =>
    assertSucceeds(setDoc(doc(a, 'users', A), {
      uid: A, email: 'a@nmit.ac.in', collegeId: 'nmit', anonId: 'anonA001',
      profileCompleted: false, createdAt: serverTimestamp(),
    }, { merge: true })));
  await test('1c B bootstrap create', () =>
    assertSucceeds(setDoc(doc(b, 'users', B), {
      uid: B, email: 'b@nmit.ac.in', collegeId: 'nmit', anonId: 'anonB001',
      profileCompleted: false, createdAt: serverTimestamp(),
    }, { merge: true })));
  await test('1d C bootstrap create (different college)', () =>
    assertSucceeds(setDoc(doc(c, 'users', C), {
      uid: C, email: 'c@rvce.edu.in', collegeId: 'rvce', anonId: 'anonC001',
      profileCompleted: false, createdAt: serverTimestamp(),
    }, { merge: true })));
  // Admin doc, needed for club_requests review + club_members bootstrap gets().
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users', ADMIN), {
      uid: ADMIN, email: 'admin@truekinn.app', collegeId: 'unknown', profileCompleted: true,
    });
  });
  await test('1e profile completion (A)', () =>
    assertSucceeds(updateDoc(doc(a, 'users', A), { profileCompleted: true, name: 'Alice' })));
  await test('1f profile completion (B)', () =>
    assertSucceeds(updateDoc(doc(b, 'users', B), { profileCompleted: true, name: 'Bob' })));
  await test('1g profile completion (C)', () =>
    assertSucceeds(updateDoc(doc(c, 'users', C), { profileCompleted: true, name: 'Cara' })));

  console.log('\n== Step 2: feed (college isolation) ==');
  // NOTE: a DocumentReference/CollectionReference is bound to the Firestore
  // instance (and therefore the auth identity) it was created from — every
  // reference below is reconstructed per-context by id string rather than
  // reused across a/b/c, or the operation would silently run as the WRONG
  // user regardless of which variable's rules are under test.
  let postId;
  await test('2a A posts to nmit feed', async () => {
    const ref = doc(collection(a, 'posts'));
    postId = ref.id;
    await assertSucceeds(setDoc(ref, {
      userId: A, collegeId: 'nmit', text: 'hello nmit', likesCount: 0, commentsCount: 0,
      createdAt: serverTimestamp(),
    }));
  });
  await test('2b B (same college) reads A post', () =>
    assertSucceeds(getDoc(doc(b, 'posts', postId))));
  await test('2c C (different college) cannot read A post', () =>
    assertFails(getDoc(doc(c, 'posts', postId))));
  await test('2d B likes A post (uid-keyed)', () =>
    assertSucceeds(setDoc(doc(b, 'posts', postId, 'likes', B), { userId: B })));
  await test('2e C cannot like A post (cross-college)', () =>
    assertFails(setDoc(doc(c, 'posts', postId, 'likes', C), { userId: C })));
  await test('2f B comments on A post', () =>
    assertSucceeds(addDoc(collection(b, 'posts', postId, 'comments'), {
      userId: B, text: 'nice post', createdAt: serverTimestamp(),
    })));

  console.log('\n== Step 3: friends (friend_service.dart sequence) ==');
  let reqId;
  await test('3a A checks not-yet-friends with B (nonexistent doc, real rule eval)', async () => {
    // Mirrors FriendService._areFriends' raw call before its try/catch —
    // this is expected to fail at the RULE layer (documented, tested
    // client-side workaround exists); asserting assertFails here pins
    // that the underlying rule behavior hasn't silently changed under us.
    await assertFails(getDoc(doc(a, 'friends', pairId(A, B))));
  });
  await test('3b A sends friend request to B', async () => {
    const ref = await addDoc(collection(a, 'friend_requests'), {
      fromUid: A, toUid: B, status: 'pending', createdAt: serverTimestamp(),
    });
    reqId = ref.id;
  });
  await test('3c B reads incoming request', () =>
    assertSucceeds(getDoc(doc(b, 'friend_requests', reqId))));
  await test('3d B creates friends doc (accept — friend_service.acceptRequest)', () =>
    assertSucceeds(setDoc(doc(b, 'friends', pairId(A, B)), {
      members: [A, B], sourceRequestId: reqId, createdAt: serverTimestamp(),
    })));
  await test('3e B deletes the consumed request', () =>
    assertSucceeds(deleteDoc(doc(b, 'friend_requests', reqId))));
  await test('3f now-friends: A reads the friends doc (exists)', () =>
    assertSucceeds(getDoc(doc(a, 'friends', pairId(A, B)))));
  await test('3g C cannot read A/B friendship (not a member)', () =>
    assertFails(getDoc(doc(c, 'friends', pairId(A, B)))));
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    // friendCreated Cloud Function isn't running against the emulator here
    // (functions emulator not started for this scenario) — bump the
    // counters the same way the real trigger would, so later assertions
    // about user doc shape stay realistic. Call ctx.firestore() ONCE and
    // reuse it — a second call on the same context throws "Firestore has
    // already been started and its settings can no longer be changed."
    const db = ctx.firestore();
    await updateDoc(doc(db, 'users', A), { friendsCount: 1 });
    await updateDoc(doc(db, 'users', B), { friendsCount: 1 });
  });

  console.log('\n== Step 4: 1:1 chat (chat_screen.dart _ensureChatExists sequence) ==');
  const chatId = pairId(A, B);
  await test('4a A checks chat exists (nonexistent, real rule eval)', () =>
    assertFails(getDoc(doc(a, 'chats', chatId))));
  await test('4b A creates the chat doc (sorted members)', () =>
    assertSucceeds(setDoc(doc(a, 'chats', chatId), {
      members: [A, B].sort(), createdAt: serverTimestamp(),
      lastMessage: '', lastMessageAt: serverTimestamp(),
    })));
  await test('4c A sends first message', () =>
    assertSucceeds(addDoc(collection(a, 'chats', chatId, 'messages'), {
      fromUid: A, toUid: B, text: 'hey!', status: 'sent', createdAt: serverTimestamp(),
    })));
  await test('4d B reads the conversation', () =>
    assertSucceeds(getDoc(doc(b, 'chats', chatId))));
  await test('4e C cannot read A/B chat', () =>
    assertFails(getDoc(doc(c, 'chats', chatId))));

  console.log('\n== Step 5: club lifecycle (create_club_screen -> admin approval -> join -> group chat) ==');
  let clubReqRef;
  await test('5a A submits a club creation request', async () => {
    clubReqRef = await addDoc(collection(a, 'club_requests'), {
      ownerUid: A, clubName: 'Chess Club', status: 'pending',
      idCardUrl: 'https://x.supabase.co/id.jpg', createdAt: serverTimestamp(),
    });
  });
  let clubId;
  await test('5b admin approves: creates club + bootstraps A as admin member (transaction)', () =>
    assertSucceeds(runTransaction(admin, async (tx) => {
      const clubRef = doc(collection(admin, 'clubs'));
      clubId = clubRef.id;
      tx.set(clubRef, { name: 'Chess Club', ownerUid: A, admins: [A], membersCount: 1 });
      tx.set(doc(admin, 'club_members', `${clubId}_${A}`), { clubId, userId: A, role: 'admin' });
      // clubReqRef was created via addDoc(collection(a, ...)) — bound to A's
      // Firestore instance. A transaction only accepts references bound to
      // the SAME instance it was created from, so reconstruct by id here.
      tx.update(doc(admin, 'club_requests', clubReqRef.id), { status: 'approved' });
    })));
  await test('5c B has not joined: own club_members row read succeeds as not-found '
    + '(Phase 21 fix — club_profile_screen._RoleActions)', async () => {
    const snap = await getDoc(doc(b, 'club_members', `${clubId}_${B}`));
    if (snap.exists()) throw new Error('expected the row not to exist yet');
  });
  await test('5d C reading someone elses (Bs) nonexistent membership row still denied', () =>
    assertFails(getDoc(doc(c, 'club_members', `${clubId}_${B}`))));
  let joinReqRef;
  await test('5e B requests to join the club', async () => {
    joinReqRef = await addDoc(collection(b, 'club_join_requests'), {
      clubId, userId: B, status: 'pending', createdAt: serverTimestamp(),
    });
  });
  await test('5f club admin (A) approves the join: creates membership + bumps count (transaction)', () =>
    assertSucceeds(runTransaction(a, async (tx) => {
      tx.set(doc(a, 'club_members', `${clubId}_${B}`), { clubId, userId: B, role: 'member' });
      tx.update(doc(a, 'clubs', clubId), { membersCount: 2 });
      // joinReqRef was created via addDoc(collection(b, ...)) — bound to
      // B's instance; reconstruct against A's for the same reason as 5b.
      tx.delete(doc(a, 'club_join_requests', joinReqRef.id));
    })));
  await test('5g B now reads their own membership row (exists)', () =>
    assertSucceeds(getDoc(doc(b, 'club_members', `${clubId}_${B}`))));
  await test('5h club chat: B bootstraps the parent doc on first open (club_chat_screen.dart)', () =>
    assertSucceeds(setDoc(doc(b, 'club_chats', clubId), { clubId })));
  await test('5i B sends a club chat message', () =>
    assertSucceeds(addDoc(collection(b, 'club_chats', clubId, 'messages'), {
      userId: B, text: 'hi club', createdAt: serverTimestamp(),
    })));
  await test('5j A (fellow member) reads the club chat', () =>
    assertSucceeds(getDoc(doc(a, 'club_chats', clubId))));
  await test('5k C (non-member) cannot open club chat', () =>
    assertFails(getDoc(doc(c, 'club_chats', clubId))));

  console.log('\n== Step 6: anonymous college chat (strict isolation) ==');
  const nmitRoom = 'college_nmit';
  const rvceRoom = 'college_rvce';
  // The room id is a fixed, well-known 'college_<collegeId>' value (not a
  // fresh auto-id like the club/event/post ids above), so — exactly like
  // the real anon_home_screen.dart flow, and chat_screen.dart's
  // _ensureChatExists for 1:1 chats — the "create" step must be an
  // ensure-exists: whoever's college room happens to already exist (e.g.
  // from another test file sharing this emulator's data, or a prior user
  // at the same college in production) makes a second create() attempt an
  // 'update', which the rules correctly deny unconditionally.
  async function ensureAnonRoom(db, uid, collegeId, roomId) {
    const ref = doc(db, 'anon_chats', roomId);
    const snap = await getDoc(ref);
    if (snap.exists()) return;
    await setDoc(ref, { createdBy: uid, members: [uid], collegeId });
  }
  await test('6a A creates/opens the nmit anon room', () =>
    ensureAnonRoom(a, A, 'nmit', nmitRoom));
  await test('6b B (same college) reads the nmit anon room', () =>
    assertSucceeds(getDoc(doc(b, 'anon_chats', nmitRoom))));
  await test('6c C (different college) cannot read the nmit anon room', () =>
    assertFails(getDoc(doc(c, 'anon_chats', nmitRoom))));
  await test('6d C cannot even create/touch the nmit room under their own uid', () =>
    assertFails(setDoc(doc(c, 'anon_chats', nmitRoom), {
      createdBy: C, members: [C], collegeId: 'rvce',
    })));
  await test('6e C opens their OWN college room instead', () =>
    ensureAnonRoom(c, C, 'rvce', rvceRoom));
  const now = new Date();
  await test('6f A sends an anon message (TTL fields correct)', () =>
    assertSucceeds(addDoc(collection(a, 'anon_chats', nmitRoom, 'messages'), {
      userId: A, anonId: 'anonA001', collegeId: 'nmit', text: 'anon hello',
      // createdAt must be the serverTimestamp sentinel (rule requires
      // createdAt == request.time); expiresAt is client-supplied, exactly
      // matching the real app's "clientNow + 90s" pattern.
      createdAt: serverTimestamp(), expiresAt: new Date(now.getTime() + 90 * 1000),
    })));

  console.log('\n== Step 7: events (write path, college-scoped read per rules) ==');
  let eventId;
  await test('7a A creates a college event', async () => {
    const ref = doc(collection(a, 'events'));
    eventId = ref.id;
    await assertSucceeds(setDoc(ref, {
      title: 'Chess Tournament', createdBy: A, collegeId: 'nmit',
      startDate: now, endDate: now,
    }));
  });
  await test('7b B (same college) can read the event at the rules layer', () =>
    assertSucceeds(getDoc(doc(b, 'events', eventId))));
  await test('7c C (different college) cannot read the event', () =>
    assertFails(getDoc(doc(c, 'events', eventId))));

  console.log('\n== Step 8: notifications ==');
  let notifRef;
  await test('8a notification created for club_request (to admin) readable by admin only', async () => {
    notifRef = await addDoc(collection(a, 'notifications'), {
      type: 'club_request', requestId: clubReqRef.id, fromUid: A, toUid: ADMIN,
      createdAt: serverTimestamp(), read: false,
    });
    await assertSucceeds(getDoc(doc(admin, 'notifications', notifRef.id)));
  });
  await test('8b non-recipient (B) cannot read that notification', () =>
    assertFails(getDoc(doc(b, 'notifications', notifRef.id))));

  await testEnv.cleanup();
  console.log(`\n${passCount} passed, ${failCount} failed`);
  process.exit(failCount ? 1 : 0);
}

main().catch((e) => {
  console.error('Test harness error:', e);
  process.exit(1);
});
