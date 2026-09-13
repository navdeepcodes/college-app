/**
 * Firestore security-rule tests for the college-isolated user directory
 * (task #32): profile reads scoped to the caller's own college.
 *
 * Covers: same-college get/query allowed; cross-college and unfiltered
 * queries denied; own-doc and admin reads allowed; legacy unstamped
 * profiles hidden (strictest-first). Plus the anonId immutability contract on
 * update: first mint allowed (heal), mutation of an existing value denied.
 * And the users.create (signup) contract: collegeId must equal the value the
 * rules derive from the verified email (collegeIdFromEmail).
 */
const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, getDoc, collection, getDocs, query, where } =
  require('@firebase/firestore');

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
const LEGACY = 'legacy-uid';
const ADMIN = 'OImOQirOL7eQNftKASo4FTrF6XA3';

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
      console.log(`  ✘ ${name}\n      ${String(e.message || e)}`);
    });
}

function userDoc(uid, collegeId, extra = {}) {
  return Object.assign(
    { uid, name: 'Test User', email: `t@${collegeId}.college`, collegeId },
    extra,
  );
}

async function main() {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { host, port },
  });

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    // Emails must be CONSISTENT with their collegeId: the rules derive the
    // sanctioned slug from the email, and an update to an inconsistent doc
    // (collegeId ≠ collegeIdFromEmail(email)) is correctly denied.
    await setDoc(doc(db, 'users', NMIT), userDoc(NMIT, 'nmit', { email: 't@nmit.ac.in' }));
    await setDoc(doc(db, 'users', RVCE), userDoc(RVCE, 'rvce', { email: 't@rvce.edu.in' }));
    // Legacy profile: predates collegeId stamping — must be hidden.
    await setDoc(doc(db, 'users', LEGACY), {
      uid: LEGACY,
      name: 'Old Profile',
      email: 't@nmit.ac.in',
    });
    await setDoc(doc(db, 'users', ADMIN), userDoc(ADMIN, 'rvce', { email: 't@rvce.edu.in' }));
  });

  const nmit = testEnv.authenticatedContext(NMIT, { email: 't@nmit.ac.in' });
  const rvce = testEnv.authenticatedContext(RVCE, { email: 't@rvce.edu.in' });
  const admin = testEnv.authenticatedContext(ADMIN, { email: 't@rvce.edu.in' });
  const anon = testEnv.unauthenticatedContext();

  const n = nmit.firestore();
  const r = rvce.firestore();
  const a = admin.firestore();
  const u = anon.firestore();

  console.log('\n== Profile reads ==');

  await test('1 unauth profile read denied', () =>
    assertFails(getDoc(doc(u, 'users', NMIT))));
  await test('2 same-college profile read allowed', () =>
    assertSucceeds(getDoc(doc(n, 'users', NMIT))));
  await test('3 cross-college profile read denied', () =>
    assertFails(getDoc(doc(n, 'users', RVCE))));
  await test('4 own profile read allowed', () =>
    assertSucceeds(getDoc(doc(n, 'users', NMIT))));
  await test('5 legacy unstamped profile read denied', () =>
    assertFails(getDoc(doc(n, 'users', LEGACY))));
  await test('6 admin reads cross-college profile allowed', () =>
    assertSucceeds(getDoc(doc(a, 'users', RVCE))));

  console.log('\n== Directory queries ==');

  // A same-college query surfaces only profiles matching the caller's college.
  await test('7 same-college filtered query allowed', () =>
    assertSucceeds(
      getDocs(query(collection(n, 'users'), where('collegeId', '==', 'nmit')))));
  // An UNFILTERED users query now violates the per-doc same-college rule for
  // the out-of-college rows it would return, so the whole query is denied —
  // this is what closes global profile enumeration.
  await test('8 unfiltered users query denied', () =>
    assertFails(getDocs(collection(n, 'users'))));
  await test('9 querying another college denied', () =>
    assertFails(
      getDocs(query(collection(n, 'users'), where('collegeId', '==', 'rvce')))));

  console.log('\n== Profile updates (anonId immutability) ==');

  // NMIT's seeded doc has no anonId yet → the first mint is the lawful heal.
  await test('10 first anonId mint on null doc allowed (heal)', () =>
    assertSucceeds(
      updateDoc(doc(n, 'users', NMIT), { anonId: 'healme12' })));
  // Once set, the value is locked: any change is a re-mint → denied.
  await test('11 mutating an existing anonId denied', () =>
    assertFails(
      updateDoc(doc(n, 'users', NMIT), { anonId: 'swapped99' })));
  await test('12 unrelated profile field update allowed', () =>
    assertSucceeds(
      updateDoc(doc(n, 'users', NMIT), { bio: 'updated' })));
  await test('13 peer cannot update another users doc', () =>
    assertFails(
      updateDoc(doc(r, 'users', NMIT), { bio: 'hijack' })));

  console.log('\n== Signup (users.create) ==');

  const signup = (email, uid) =>
    testEnv.authenticatedContext(uid, { email }).firestore();
  // Sanctioned domain: the client derives collegeId nmit AND the rules agree.
  await test('s1 signup with nmit email -> collegeId nmit allowed', async () => {
    const s = signup('new@nmit.ac.in', 'uid-nmit-new');
    await assertSucceeds(
      setDoc(doc(s, 'users', 'uid-nmit-new'), {
        uid: 'uid-nmit-new', email: 'new@nmit.ac.in',
        collegeId: 'nmit', profileCompleted: false,
      }));
  });
  // A sanctioned email can only ever claim its own domain's slug.
  await test('s2 nmit email claiming rvce collegeId denied', async () => {
    const s = signup('new@nmit.ac.in', 'uid-nmit-forge');
    await assertFails(
      setDoc(doc(s, 'users', 'uid-nmit-forge'), {
        uid: 'uid-nmit-forge', email: 'new@nmit.ac.in',
        collegeId: 'rvce', profileCompleted: false,
      }));
  });
  await test('s3 unsanctioned email -> collegeId unknown allowed', async () => {
    const s = signup('x@somedomain.edu', 'uid-other');
    await assertSucceeds(
      setDoc(doc(s, 'users', 'uid-other'), {
        uid: 'uid-other', email: 'x@somedomain.edu',
        collegeId: 'unknown', profileCompleted: false,
      }));
  });
  await test('s4 unsanctioned email forged nmit collegeId denied', async () => {
    const s = signup('x@somedomain.edu', 'uid-other-forge');
    await assertFails(
      setDoc(doc(s, 'users', 'uid-other-forge'), {
        uid: 'uid-other-forge', email: 'x@somedomain.edu',
        collegeId: 'nmit', profileCompleted: false,
      }));
  });

  await testEnv.cleanup();
  console.log(`\n${passCount} passed, ${failCount} failed`);
  process.exit(failCount ? 1 : 0);
}

main().catch((e) => {
  console.error('Test harness error:', e);
  process.exit(1);
});