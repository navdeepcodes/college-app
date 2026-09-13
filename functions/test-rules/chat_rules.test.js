/**
 * Firestore security-rule tests for 1:1 chats + friends (task #33):
 * chats, chat messages, friends, friend_requests, club_chats.
 *
 * Covers: membership-scoped reads; canonical sorted 2-member chat create;
 * immutable messages with sender-auth; recipient-only status transitions;
 * friendship edge privacy; friend-request sender/recipient scoping;
 * club-chat membership gating via club_members/{clubId}_{uid}; the
 * club_chats/{clubId} parent doc (Phase 18 — previously had no rule block
 * at all); and the friends.create consent check tying a friendship to a
 * still-pending friend_requests doc (Phase 18 — previously any client
 * could mint a friendship with an arbitrary uid unilaterally).
 */
const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const {
  doc,
  setDoc,
  getDoc,
  addDoc,
  deleteDoc,
  updateDoc,
  collection,
  serverTimestamp,
} = require('@firebase/firestore');

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-truekinn';

let host = '127.0.0.1';
let port = 8080;
if (process.env.FIRESTORE_EMULATOR_HOST) {
  const [h, p] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  host = h;
  port = Number(p);
}

const NMIT = 'nmit-uid';
const RVCE = 'rvce-uid';
const TMIT = 'third-uid'; // non-member third party
const CHAT_NR = 'nmit-uid_rvce-uid'; // sorted join
const CHAT_RT = 'rvce-uid_third-uid';

let testEnv;
let passCount = 0;
let failCount = 0;

function test(name, fn) {
  return fn()
    .then(() => {
      passCount++;
      console.log(`  ✔ ${name}`);
    })
    .catch((e) => {
      failCount++;
      console.log(`  ✘ ${name}\n      ${String(e.message || e).split('\n')[0]}`);
    });
}

function chatDoc(members, overrides = {}) {
  return Object.assign(
    {
      members,
      createdAt: serverTimestamp(),
      lastMessage: '',
      lastMessageAt: serverTimestamp(),
    },
    overrides,
  );
}

function msg(overrides = {}) {
  return Object.assign(
    {
      fromUid: NMIT,
      toUid: RVCE,
      text: 'hey',
      status: 'sent',
      createdAt: serverTimestamp(),
    },
    overrides,
  );
}

async function main() {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { host, port },
  });

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', NMIT), {
      collegeId: 'nmit', email: 's@nmit.ac.in',
    });
    await setDoc(doc(db, 'users', RVCE), {
      collegeId: 'rvce', email: 's@rvce.edu.in',
    });
    await setDoc(doc(db, 'users', TMIT), {
      collegeId: 'nmit', email: 's3@nmit.ac.in',
    });

    // Existing 1:1 chats: NMIT<->RVCE and RVCE<->TMIT.
    await setDoc(doc(db, 'chats', CHAT_NR), chatDoc([NMIT, RVCE]));
    await setDoc(doc(db, 'chats', CHAT_RT), chatDoc([RVCE, TMIT]));
    await setDoc(doc(db, 'chats', CHAT_NR, 'messages', 'm1'), msg());
    await setDoc(doc(db, 'chats', CHAT_RT, 'messages', 'm2'), {
      fromUid: RVCE, toUid: TMIT, text: 'hi', status: 'sent',
      createdAt: serverTimestamp(),
    });

    // A friendship and a pending friend request.
    await setDoc(doc(db, 'friends', 'f1'), { members: [NMIT, RVCE], sourceRequestId: 'r0' });
    await setDoc(doc(db, 'friend_requests', 'r0'), {
      fromUid: NMIT, toUid: RVCE, status: 'pending',
    });
    await setDoc(doc(db, 'friend_requests', 'r1'), {
      fromUid: NMIT, toUid: RVCE, status: 'pending',
    });
    // For the friends.create consent-check tests below.
    await setDoc(doc(db, 'friend_requests', 'r2'), {
      fromUid: RVCE, toUid: TMIT, status: 'pending',
    });
    await setDoc(doc(db, 'friend_requests', 'r-accepted'), {
      fromUid: NMIT, toUid: TMIT, status: 'accepted',
    });
    // Simulates a request already consumed by a prior accept (deleted).
    await setDoc(doc(db, 'friend_requests', 'r-used'), {
      fromUid: NMIT, toUid: TMIT, status: 'pending',
    });
    await deleteDoc(doc(db, 'friend_requests', 'r-used'));

    // A club with NMIT + RVCE as members (club_members doc ids: {clubId}_{uid}).
    await setDoc(doc(db, 'clubs', 'club1'), {
      admins: [NMIT], name: 'C', membersCount: 2,
    });
    await setDoc(doc(db, 'club_members', 'club1_nmit-uid'), {
      clubId: 'club1', userId: NMIT, role: 'admin',
    });
    await setDoc(doc(db, 'club_members', 'club1_rvce-uid'), {
      clubId: 'club1', userId: RVCE, role: 'member',
    });
    await setDoc(doc(db, 'club_chats', 'club1', 'messages', 'cm1'), {
      userId: NMIT, text: 'club hello', createdAt: serverTimestamp(),
    });
  });

  const nmit = testEnv.authenticatedContext(NMIT, { email: 's@nmit.ac.in' });
  const rvce = testEnv.authenticatedContext(RVCE, { email: 's@rvce.edu.in' });
  const tmit = testEnv.authenticatedContext(TMIT, { email: 's3@nmit.ac.in' });
  const anon = testEnv.unauthenticatedContext();

  const n = nmit.firestore();
  const r = rvce.firestore();
  const t = tmit.firestore();
  const u = anon.firestore();

  const chatRef = (db, id) => doc(db, 'chats', id);

  console.log('\n== Chats ==');

  await test('1 unauth chat read denied', () =>
    assertFails(getDoc(chatRef(u, CHAT_NR))));
  await test('2 member reads their chat allowed', () =>
    assertSucceeds(getDoc(chatRef(n, CHAT_NR))));
  await test('3 non-member reads a chat denied', () =>
    assertFails(getDoc(chatRef(t, CHAT_NR))));
  await test('4 create own sorted 2-member chat allowed', () => // fresh pair: not pre-seeded
    assertSucceeds(setDoc(doc(r, 'chats', 'newbie-uid_rvce-uid'), chatDoc(['newbie-uid', RVCE]))));
  await test('5 create chat not containing me denied', () =>
    assertFails(setDoc(chatRef(t, CHAT_RT), chatDoc([RVCE, TMIT]))));
  await test('6 create 3-member chat denied', () =>
    assertFails(setDoc(doc(n, 'chats', 'a_b_c'), chatDoc([NMIT, RVCE, TMIT]))));
  await test('7 create duplicate-member chat denied', () =>
    assertFails(setDoc(doc(n, 'chats', 'a_a'), chatDoc([NMIT, NMIT]))));
  await test('8 create unsorted members denied', () =>
    assertFails(setDoc(doc(r, 'chats', 'rvce-uid_nmit-uid'), chatDoc([RVCE, NMIT]))));
  await test('9 member updates chat footer allowed', () =>
    assertSucceeds(updateDoc(chatRef(n, CHAT_NR), {
      lastMessage: 'hey', lastMessageAt: serverTimestamp(),
    })));
  await test('10 non-member updates chat denied', () =>
    assertFails(updateDoc(chatRef(t, CHAT_NR), { lastMessage: 'hack' })));
  await test('11 chat delete denied', () =>
    assertFails(deleteDoc(chatRef(n, CHAT_NR))));

  console.log('\n== Messages ==');

  const msgs = (db) => collection(db, 'chats', CHAT_NR, 'messages');
  await test('12 member reads messages allowed', () =>
    assertSucceeds(getDoc(doc(n, 'chats', CHAT_NR, 'messages', 'm1'))));
  await test('13 non-member reads messages denied', () =>
    assertFails(getDoc(doc(t, 'chats', CHAT_NR, 'messages', 'm1'))));
  await test('14 send message allowed', () =>
    assertSucceeds(addDoc(msgs(n), msg({ text: 'hello there' }))));
  await test('15 blank text denied', () =>
    assertFails(addDoc(msgs(n), msg({ text: '   ' }))));
  await test('16 bogus status denied', () =>
    assertFails(addDoc(msgs(n), msg({ status: 'shouted' }))));
  await test('17 forged fromUid denied', () =>
    assertFails(addDoc(msgs(n), msg({ fromUid: RVCE }))));
  await test('18 messaging self denied', () =>
    assertFails(addDoc(msgs(n), msg({ toUid: NMIT }))));
  await test('19 non-member send denied', () =>
    assertFails(addDoc(msgs(t), msg({ fromUid: TMIT, toUid: NMIT }))));
  await test('20 recipient marks delivered allowed', () =>
    assertSucceeds(updateDoc(doc(r, 'chats', CHAT_NR, 'messages', 'm1'), {
      status: 'delivered',
    })));
  await test('21 sender cannot set status denied', () =>
    assertFails(updateDoc(doc(n, 'chats', CHAT_NR, 'messages', 'm1'), {
      status: 'delivered',
    })));
  await test('22 editing message text denied', () =>
    assertFails(updateDoc(doc(n, 'chats', CHAT_NR, 'messages', 'm1'), {
      text: 'edited',
    })));
  await test('23 message delete denied', () =>
    assertFails(deleteDoc(doc(n, 'chats', CHAT_NR, 'messages', 'm1'))));

  console.log('\n== Friends ==');

  const friendRef = (db, id) => doc(db, 'friends', id);
  await test('24 member reads friend edge allowed', () =>
    assertSucceeds(getDoc(friendRef(n, 'f1'))));
  await test('25 non-member reads friend edge denied', () =>
    assertFails(getDoc(friendRef(t, 'f1'))));

  // Consent check (Phase 18): a friends doc must reference a still-pending
  // friend_requests doc naming exactly these two members — closes a hole
  // where any authenticated user could mint a "friendship" with an
  // arbitrary victim uid (discoverable via search) with no consent at all,
  // which also inflated the victim's friendsCount via the friendCreated
  // Cloud Function trigger.
  await test('26 create friendship via valid pending request allowed', () =>
    assertSucceeds(setDoc(doc(r, 'friends', 'rt'), {
      members: [RVCE, TMIT], sourceRequestId: 'r2', createdAt: serverTimestamp(),
    })));
  await test('27 create friendship with no sourceRequestId denied', () =>
    assertFails(setDoc(doc(n, 'friends', 'nf'), {
      members: [NMIT, RVCE], createdAt: serverTimestamp(),
    })));
  await test('28 create friendship without me denied', () =>
    // members exclude the acting user (TMIT) entirely -> must be rejected
    assertFails(setDoc(doc(t, 'friends', 'tf'), {
      members: [NMIT, RVCE], sourceRequestId: 'r1', createdAt: serverTimestamp(),
    })));
  await test('29 self-pair friendship denied', () =>
    assertFails(setDoc(doc(n, 'friends', 'sf'), {
      members: [NMIT, NMIT], sourceRequestId: 'r1', createdAt: serverTimestamp(),
    })));
  await test('30 sourceRequestId naming unrelated members denied', () =>
    // r1 is NMIT->RVCE; claiming members [NMIT, TMIT] doesn't match it.
    assertFails(setDoc(doc(n, 'friends', 'mismatched'), {
      members: [NMIT, TMIT], sourceRequestId: 'r1', createdAt: serverTimestamp(),
    })));
  await test('31 sourceRequestId pointing at a non-pending request denied', () =>
    assertFails(setDoc(doc(n, 'friends', 'notpending'), {
      members: [NMIT, TMIT], sourceRequestId: 'r-accepted', createdAt: serverTimestamp(),
    })));
  await test('32 sourceRequestId pointing at a deleted/consumed request denied', () =>
    // Guards against replaying an already-accepted request to mint a
    // second friends doc after the original request was deleted.
    assertFails(setDoc(doc(n, 'friends', 'replayed'), {
      members: [NMIT, TMIT], sourceRequestId: 'r-used', createdAt: serverTimestamp(),
    })));
  await test('33 sourceRequestId pointing at a nonexistent request denied', () =>
    assertFails(setDoc(doc(n, 'friends', 'bogus'), {
      members: [NMIT, TMIT], sourceRequestId: 'no-such-request', createdAt: serverTimestamp(),
    })));
  await test('34 friend edge immutable', () =>
    assertFails(updateDoc(friendRef(n, 'f1'), { members: [NMIT, TMIT] })));

  console.log('\n== Friend requests ==');

  const reqRef = (db, id) => doc(db, 'friend_requests', id);
  await test('35 sender reads own request allowed', () =>
    assertSucceeds(getDoc(reqRef(n, 'r1'))));
  await test('36 recipient reads request allowed', () =>
    assertSucceeds(getDoc(reqRef(r, 'r1'))));
  await test('37 third party reads request denied', () =>
    assertFails(getDoc(reqRef(t, 'r1'))));
  await test('38 create pending request allowed', () =>
    assertSucceeds(addDoc(collection(n, 'friend_requests'), {
      fromUid: NMIT, toUid: TMIT, status: 'pending',
      createdAt: serverTimestamp(),
    })));
  await test('39 request to self denied', () =>
    assertFails(addDoc(collection(n, 'friend_requests'), {
      fromUid: NMIT, toUid: NMIT, status: 'pending',
    })));
  await test('40 forged pending status denied', () =>
    assertFails(addDoc(collection(n, 'friend_requests'), {
      fromUid: NMIT, toUid: TMIT, status: 'accepted',
    })));
  await test('41 recipient updates status allowed', () =>
    assertSucceeds(updateDoc(reqRef(r, 'r1'), { status: 'accepted' })));
  await test('42 sender updates status denied', () =>
    assertFails(updateDoc(reqRef(n, 'r1'), { status: 'declined' })));
  await test('43 recipient deletes request allowed', () =>
    assertSucceeds(deleteDoc(reqRef(r, 'r1'))));

  console.log('\n== Club chats ==');

  // Parent doc (club_chats/{clubId} itself, not just its messages
  // subcollection) — was previously MISSING a rule block entirely, so every
  // access fell to Firestore's default deny. club_chat_screen.dart's
  // "ensure chat doc exists" bootstrap called .get() on this path before
  // ever rendering the screen, so this made club chat permanently stuck on
  // a loading spinner for every club, every time it was opened.
  const clubChatRoot = (db) => doc(db, 'club_chats', 'club1');
  await test('44 club member reads club_chats parent doc allowed', () =>
    assertSucceeds(getDoc(clubChatRoot(n))));
  await test('45 non-member reads club_chats parent doc denied', () =>
    assertFails(getDoc(clubChatRoot(t))));
  await test('46 club member creates club_chats parent doc (first open) allowed', () =>
    // club1's parent doc is deliberately NOT pre-seeded (only its messages
    // subcollection is) — this is exactly club_chat_screen.dart's real
    // first-open bootstrap path. RVCE is a genuine club1 member.
    assertSucceeds(setDoc(clubChatRoot(r), {
      clubId: 'club1', createdAt: serverTimestamp(),
    })));
  await test('47 non-member cannot create a club_chats parent doc', () =>
    assertFails(setDoc(doc(t, 'club_chats', 'club-nonmember'), {
      clubId: 'club-nonmember', createdAt: serverTimestamp(),
    })));
  await test('48 club_chats parent doc immutable', () =>
    assertFails(updateDoc(clubChatRoot(n), { clubId: 'hacked' })));

  const clubMsgs = (db) => collection(db, 'club_chats', 'club1', 'messages');
  await test('49 club member reads club chat allowed', () =>
    assertSucceeds(getDoc(doc(n, 'club_chats', 'club1', 'messages', 'cm1'))));
  await test('50 non-member reads club chat denied', () =>
    assertFails(getDoc(doc(t, 'club_chats', 'club1', 'messages', 'cm1'))));
  await test('51 member sends club message allowed', () =>
    assertSucceeds(addDoc(clubMsgs(n), {
      userId: NMIT, text: 'anyone here?', createdAt: serverTimestamp(),
    })));
  await test('52 non-member sends club message denied', () =>
    assertFails(addDoc(clubMsgs(t), {
      userId: TMIT, text: 'spam', createdAt: serverTimestamp(),
    })));
  await test('53 forged club message userId denied', () =>
    assertFails(addDoc(clubMsgs(n), {
      userId: RVCE, text: 'spoofed', createdAt: serverTimestamp(),
    })));
  await test('54 blank club message denied', () =>
    assertFails(addDoc(clubMsgs(n), {
      userId: NMIT, text: '  ', createdAt: serverTimestamp(),
    })));

  await testEnv.cleanup();
  console.log(`\n${passCount} passed, ${failCount} failed`);
  process.exit(failCount ? 1 : 0);
}

main().catch((e) => {
  console.error('Test harness error:', e);
  process.exit(1);
});