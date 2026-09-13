/**
 * Firestore security-rule tests for the club-request notification contract
 * (task #25 / #29).
 *
 * Verifies, against the Firestore emulator:
 *   club_requests – owner-only create (pending), admin review (read all /
 *                   approve / reject), owner reads own;
 *   notifications – recipient-only read, recipient != sender on create,
 *                   recipient-only delete;
 *   clubs.create  – platform-admin bootstrap on behalf of an approved
 *                   requester is allowed; impersonation is denied;
 *   club_members  – admin can add members; non-admins cannot.
 */
const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const {
  doc,
  setDoc,
  getDoc,
  addDoc,
  collection,
  updateDoc,
  deleteDoc,
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

// Mirrors ADMIN_UID in lib/core/admin.dart.
const ADMIN = 'OImOQirOL7eQNftKASo4FTrF6XA3';
const REQUESTER = 'requester-uid';
const OTHER = 'other-uid';

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

function clubRequest(overrides = {}) {
  return Object.assign(
    {
      ownerUid: REQUESTER,
      clubName: 'Chess Club',
      description: 'We play chess',
      phone: '9876543210',
      usn: '1NM21CS001',
      status: 'pending',
      idCardUrl: 'https://x.supabase.co/club_id_cards/x.jpg',
      createdAt: serverTimestamp(),
    },
    overrides,
  );
}

function notification(overrides = {}) {
  return Object.assign(
    {
      type: 'club_request',
      requestId: 'req-1',
      clubName: 'Chess Club',
      fromUid: REQUESTER,
      toUid: ADMIN,
      createdAt: serverTimestamp(),
      read: false,
    },
    overrides,
  );
}

async function main() {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { host, port },
  });

  // Seed one club owned by REQUESTER (needed by club_members get() checks).
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', REQUESTER), {
      collegeId: 'nmit',
      email: 'student@nmit.ac.in',
      profileCompleted: true,
    });
    await setDoc(doc(db, 'users', ADMIN), {
      collegeId: 'unknown',
      email: 'admin@truekinn.app',
      profileCompleted: true,
    });
    await setDoc(doc(db, 'clubs', 'club-1'), {
      name: 'Chess Club',
      ownerUid: REQUESTER,
      admins: [REQUESTER],
      membersCount: 1,
    });
    await setDoc(doc(db, 'club_requests', 'req-1'), clubRequest());
    await setDoc(doc(db, 'club_requests', 'req-2'), clubRequest({ clubName: 'Robotics Club' }));
    await setDoc(doc(db, 'notifications', 'ntf-1'), notification());
    // Pending JOIN requests: jr-1 from OTHER, jr-2 from REQUESTER (both to club-1).
    await setDoc(doc(db, 'club_join_requests', 'jr-1'), {
      clubId: 'club-1', userId: OTHER, status: 'pending',
    });
    await setDoc(doc(db, 'club_join_requests', 'jr-2'), {
      clubId: 'club-1', userId: REQUESTER, status: 'pending',
    });
  });

  const requester = testEnv.authenticatedContext(REQUESTER, {
    email: 'student@nmit.ac.in',
  });
  const admin = testEnv.authenticatedContext(ADMIN, {
    email: 'admin@truekinn.app',
  });
  const other = testEnv.authenticatedContext(OTHER, {
    email: 'student@rvce.edu.in',
  });
  const anon = testEnv.unauthenticatedContext();

  const r = requester.firestore();
  const a = admin.firestore();
  const o = other.firestore();
  const n = anon.firestore();

  console.log('\n== Notifications contract ==');

  await test('n1 unauth notification write denied', () =>
    assertFails(addDoc(collection(n, 'notifications'), notification())));
  await test('n2 notification without toUid denied', () =>
    assertFails(addDoc(collection(r, 'notifications'), notification({ toUid: '' }))));
  await test('n3 notification to self denied', () =>
    assertFails(addDoc(collection(r, 'notifications'), notification({ toUid: REQUESTER }))));
  await test('n4 sender impersonation denied (fromUid != auth)', () =>
    assertFails(addDoc(collection(r, 'notifications'), notification({ fromUid: OTHER }))));
  await test('n5 valid notification to admin allowed', () =>
    assertSucceeds(addDoc(collection(r, 'notifications'), notification())));
  await test('n6 non-recipient cannot read notification', () =>
    assertFails(getDoc(doc(o, 'notifications', 'ntf-1'))));
  await test('n7 recipient (admin) can read notification', () =>
    assertSucceeds(getDoc(doc(a, 'notifications', 'ntf-1'))));
  await test('n8 sender (requester) cannot read notification', () =>
    assertFails(getDoc(doc(r, 'notifications', 'ntf-1'))));
  await test('n9 recipient can delete own notification', () =>
    assertSucceeds(deleteDoc(doc(a, 'notifications', 'ntf-1'))));

  console.log('\n== Club requests ==');

  await test('r1 unauth club_request write denied', () =>
    assertFails(addDoc(collection(n, 'club_requests'), clubRequest())));
  await test('r2 owner submits own pending request allowed', () =>
    assertSucceeds(addDoc(collection(r, 'club_requests'), clubRequest({ clubName: 'Dance Club' }))));
  await test('r3 impersonating ownerUid denied', () =>
    assertFails(addDoc(collection(o, 'club_requests'), clubRequest({ ownerUid: REQUESTER }))));
  await test('r4 request not pending denied', () =>
    assertFails(addDoc(collection(r, 'club_requests'), clubRequest({ status: 'approved' }))));
  await test('r5 requester reads own request allowed', () =>
    assertSucceeds(getDoc(doc(r, 'club_requests', 'req-1'))));
  await test('r6 other user cannot read someone elses request', () =>
    assertFails(getDoc(doc(o, 'club_requests', 'req-1'))));
  await test('r7 admin reads all requests allowed', () =>
    assertSucceeds(getDoc(doc(a, 'club_requests', 'req-1'))));
  await test('r8 non-admin cannot approve/reject', () =>
    assertFails(updateDoc(doc(o, 'club_requests', 'req-1'), { status: 'approved' })));
  await test('r9 admin approve allowed', () =>
    assertSucceeds(updateDoc(doc(a, 'club_requests', 'req-1'), { status: 'approved' })));
  await test('r10 admin reject allowed', () =>
    assertSucceeds(updateDoc(doc(a, 'club_requests', 'req-2'), { status: 'rejected' })));
  await test('r11 non-admin cannot delete request', () =>
    assertFails(deleteDoc(doc(r, 'club_requests', 'req-1'))));
  await test('r12 admin can delete request', () =>
    assertSucceeds(deleteDoc(doc(a, 'club_requests', 'req-1'))));
  await test('r13 request without ID-card upload denied', () =>
    assertFails(addDoc(collection(r, 'club_requests'), clubRequest({ clubName: 'Art Club', idCardUrl: '' }))));

  console.log('\n== Clubs.create (admin bootstrap) ==');

  const clubDoc = (db) => addDoc(collection(db, 'clubs'), {
    name: 'Bootstrap Club',
    description: 'built by admin',
    ownerUid: REQUESTER,
    admins: [REQUESTER],
    membersCount: 1,
  });
  await test('c1 admin bootstraps club for requester allowed', () =>
    assertSucceeds(clubDoc(a)));
  await test('c2 non-admin cannot create club for another user', () =>
    assertFails(clubDoc(o)));
  await test('c3 user creates own club (admins=[self]) allowed', () =>
    assertSucceeds(addDoc(collection(r, 'clubs'), {
      name: 'Own Club',
      ownerUid: REQUESTER,
      admins: [REQUESTER],
      membersCount: 1,
    })));

  console.log('\n== Club members ==');

  const member = (db) => setDoc(doc(db, 'club_members', 'club-1_requester'), {
    clubId: 'club-1',
    userId: REQUESTER,
    role: 'admin',
  });
  await test('m1 admin bootstraps club member allowed', () =>
    assertSucceeds(member(a)));
  await test('m2 non-admin cannot add member without admin role', () =>
    assertFails(member(o)));
  await test('m3 unauth cannot read club members', () =>
    assertFails(getDoc(doc(n, 'club_members', 'club-1_requester'))));
  // m1 ran first and bootstrapped club-1_requester, so reads can target it.
  await test('m4 user reads their own membership allowed', () =>
    assertSucceeds(getDoc(doc(r, 'club_members', 'club-1_requester'))));
  await test('m5 outsider cannot read membership', () =>
    assertFails(getDoc(doc(o, 'club_members', 'club-1_requester'))));
  await test('m6 platform admin reads any membership allowed', () =>
    assertSucceeds(getDoc(doc(a, 'club_members', 'club-1_requester'))));

  console.log('\n== Club join requests ==');

  const jr = (db, id) => doc(db, 'club_join_requests', id);
  await test('j1 applicant creates own pending join request allowed', () =>
    assertSucceeds(addDoc(collection(o, 'club_join_requests'), {
      clubId: 'club-1', userId: OTHER, status: 'pending',
      createdAt: serverTimestamp(),
    })));
  await test('j2 creating join request for another denied', () =>
    assertFails(addDoc(collection(o, 'club_join_requests'), {
      clubId: 'club-1', userId: REQUESTER, status: 'pending',
    })));
  await test('j3 non-pending join request denied', () =>
    assertFails(addDoc(collection(o, 'club_join_requests'), {
      clubId: 'club-1', userId: OTHER, status: 'active',
    })));
  await test('j4 applicant reads own join request allowed', () =>
    assertSucceeds(getDoc(jr(o, 'jr-1'))));
  await test('j5 club admin reads pending join request allowed', () =>
    assertSucceeds(getDoc(jr(r, 'jr-1'))));
  await test('j6 outsider cannot read someone elses join request', () =>
    assertFails(getDoc(jr(o, 'jr-2'))));
  await test('j7 applicant cannot approve own request', () =>
    assertFails(updateDoc(jr(o, 'jr-1'), { status: 'active' })));
  await test('j8 club admin approves join request allowed', () =>
    assertSucceeds(updateDoc(jr(r, 'jr-1'), { status: 'active' })));
  await test('j9 club admin clears join request (approve flow) allowed', () =>
    assertSucceeds(deleteDoc(jr(r, 'jr-2'))));

  await testEnv.cleanup();

  console.log(`\n${passCount} passed, ${failCount} failed`);
  process.exit(failCount ? 1 : 0);
}

main().catch((e) => {
  console.error('Test harness error:', e);
  process.exit(1);
});