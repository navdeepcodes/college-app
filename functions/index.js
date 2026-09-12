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