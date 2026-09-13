const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

// 🔥 Runs every 1 minute
exports.cleanupExpiredAnonMessages = functions.pubsub
  .schedule("every 1 minutes")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    const chatsSnap = await db.collection("anon_chats").get();

    let deleteCount = 0;

    for (const chat of chatsSnap.docs) {
      const messagesRef = chat.ref.collection("messages");

      const expiredSnap = await messagesRef
        .where("expiresAt", "<=", now)
        .limit(500)
        .get();

      if (expiredSnap.empty) continue;

      const batch = db.batch();

      expiredSnap.docs.forEach((doc) => {
        batch.delete(doc.ref);
        deleteCount++;
      });

      await batch.commit();
    }

    console.log(`🔥 Deleted ${deleteCount} expired anon messages`);
    return null;
  });

// ⭐ Bumps friendsCount on both members when a friendship is created.
// The client accept batch cannot write a peer's users doc (owner-only rule),
// so the authoritative counter update happens server-side.
exports.friendCreated = functions.firestore
  .document("friends/{friendId}")
  .onCreate(async (snap) => {
    const data = snap.data() || {};
    const members = data.members || [];
    const inc = admin.firestore.FieldValue.increment(1);

    const batch = db.batch();
    for (const uid of members) {
      if (typeof uid !== "string" || uid.length === 0) continue;
      batch.update(db.collection("users").doc(uid), {
        friendsCount: inc,
      });
    }

    await batch.commit();
    console.log(`⭐ friends++ for [${members.join(", ")}]`);
    return null;
  });