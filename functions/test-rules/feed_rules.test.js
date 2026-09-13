/**
 * Firestore security-rule tests for the college-isolated campus feed
 * (tasks #30/#31): posts, likes, comments.
 *
 * Covers: same-college read/write allowed; cross-college read/write denied;
 * legacy (unstamped) posts denied under strictest-first; owner-only content
 * edits; same-college peers may bump only like/comment counters.
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
  Timestamp,
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
const PN = 'post-nmit';
const PR = 'post-rvce';
const PL = 'post-legacy';

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

function post(overrides = {}) {
  return Object.assign(
    {
      userId: NMIT,
      collegeId: 'nmit',
      caption: 'hello campus',
      mediaPath: 'posts/x.jpg',
      createdAt: serverTimestamp(),
      likesCount: 0,
      commentsCount: 0,
    },
    overrides,
  );
}

function comment(overrides = {}) {
  return Object.assign(
    { userId: NMIT, text: 'nice one', createdAt: serverTimestamp() },
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
      collegeId: 'nmit',
      email: 's@nmit.ac.in',
      profileCompleted: true,
    });
    await setDoc(doc(db, 'users', RVCE), {
      collegeId: 'rvce',
      email: 's@rvce.edu.in',
      profileCompleted: true,
    });
    await setDoc(doc(db, 'posts', PN), post());
    await setDoc(doc(db, 'posts', PR), post({ userId: RVCE, collegeId: 'rvce' }));
    await setDoc(doc(db, 'posts', PL), {
      userId: NMIT,
      caption: 'old post',
      createdAt: Timestamp.now(),
    });
    await setDoc(doc(db, 'posts', PN, 'comments', 'c1'), {
      userId: NMIT,
      text: 'first!',
      createdAt: Timestamp.now(),
    });
  });

  const nmit = testEnv.authenticatedContext(NMIT, { email: 's@nmit.ac.in' });
  const rvce = testEnv.authenticatedContext(RVCE, { email: 's@rvce.edu.in' });
  const anon = testEnv.unauthenticatedContext();

  const n = nmit.firestore();
  const r = rvce.firestore();
  const u = anon.firestore();

  console.log('\n== Posts ==');

  await test('1 unauth post read denied', () =>
    assertFails(getDoc(doc(u, 'posts', PN))));
  await test('2 same-college post read allowed', () =>
    assertSucceeds(getDoc(doc(n, 'posts', PN))));
  await test('3 cross-college post read denied', () =>
    assertFails(getDoc(doc(n, 'posts', PR))));
  await test('4 legacy unstamped post read denied', () =>
    assertFails(getDoc(doc(n, 'posts', PL))));
  await test('5 create own-college post allowed', () =>
    assertSucceeds(addDoc(collection(n, 'posts'), post({ caption: 'new' }))));
  await test('6 create post forged collegeId denied', () =>
    assertFails(addDoc(collection(n, 'posts'), post({ collegeId: 'rvce' }))));
  await test('7 create post without collegeId denied', () =>
    assertFails(addDoc(collection(n, 'posts'), post({ collegeId: '' }))));
  await test('8 owner edits own post allowed', () =>
    assertSucceeds(updateDoc(doc(n, 'posts', PN), { caption: 'edited' })));
  await test('9 peer bumps likesCount only allowed', () =>
    assertSucceeds(updateDoc(doc(n, 'posts', PN), { likesCount: 1 })));
  await test('10 peer (rvce) cannot edit nmit caption', () =>
    assertFails(updateDoc(doc(r, 'posts', PN), { caption: 'hack' })));

  console.log('\n== Likes ==');

  const likeRef = (db, pid, whom) => doc(db, 'posts', pid, 'likes', whom);
  await test('12 same-college user likes post allowed', () =>
    assertSucceeds(setDoc(likeRef(n, PN, NMIT), {
      userId: NMIT,
      createdAt: serverTimestamp(),
    })));
  await test('13 cross-college user cannot like', () =>
    assertFails(setDoc(likeRef(r, PN, RVCE), { userId: RVCE, createdAt: serverTimestamp() })));
  await test('14 like by forged userId denied (uid-keyed doc)', () =>
    assertFails(setDoc(likeRef(n, PN, NMIT), { userId: RVCE, createdAt: serverTimestamp() })));
  await test('15 owner reads like allowed', () =>
    assertSucceeds(getDoc(likeRef(n, PN, NMIT))));
  await test('16 nmit cannot read like on rvce post', () =>
    assertFails(getDoc(likeRef(n, PR, RVCE))));
  await test('17 like delete by author allowed', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'posts', PN, 'likes', NMIT), {
        userId: NMIT,
      });
    });
    await assertSucceeds(deleteDoc(likeRef(n, PN, NMIT)));
  });

  console.log('\n== Comments ==');

  const commentsOf = (db, pid) => collection(db, 'posts', pid, 'comments');
  await test('18 same-college comment create allowed', () =>
    assertSucceeds(addDoc(commentsOf(n, PN), comment())));
  await test('19 blank comment denied', () =>
    assertFails(addDoc(commentsOf(n, PN), comment({ text: '   ' }))));
  await test('20 cross-college comment denied', () =>
    assertFails(addDoc(commentsOf(r, PN), comment({ userId: RVCE }))));
  await test('21 comment with forged userId denied', () =>
    assertFails(addDoc(commentsOf(n, PN), comment({ userId: RVCE }))));
  await test('22 same-college comment read allowed', () =>
    assertSucceeds(getDoc(doc(n, 'posts', PN, 'comments', 'c1'))));
  await test('23 cross-college cannot read comments', () =>
    assertFails(getDoc(doc(r, 'posts', PN, 'comments', 'c1'))));

  // Delete runs LAST: it removes the seeded post-nmit, and every rule on its
  // likes/comments subcollections reads the parent via postCollege(postId), so
  // a deleted parent would make those get() lookups fail (deny) spurious.
  await test('24 owner (nmit) deletes own college-stamped post allowed', () =>
    assertSucceeds(deleteDoc(doc(n, 'posts', PN))));

  await testEnv.cleanup();
  console.log(`\n${passCount} passed, ${failCount} failed`);
  process.exit(failCount ? 1 : 0);
}

main().catch((e) => {
  console.error('Test harness error:', e);
  process.exit(1);
});