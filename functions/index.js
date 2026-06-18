/**
 * Auto-settle Cloud Function for WC2026 Predictor
 *
 * Runs every 2 minutes. Fetches ESPN scoreboard, finds matches that ESPN
 * marks as finished but Firestore hasn't settled yet, and settles them
 * server-side using the Admin SDK.
 *
 * This is the ONLY safe way to auto-settle without the admin opening the app:
 *  - Runs on Google's infrastructure (no app needed)
 *  - Uses Admin SDK (bypasses all Firestore security rules)
 *  - No user data is ever exposed or accepted as input
 *  - The settle logic is identical to the client-side version
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const fetch = require('node-fetch');

admin.initializeApp();
const db = admin.firestore();

const ESPN_URL = 'https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard';

// Scoring constants — must match scoring_service.dart
const POINTS = {
  exact: 50,
  correctPlusOne: 30,
  correctResult: 20,
  oneScore: 10,
  wrong: 0,
};

function calcResult(predHome, predAway, actualHome, actualAway) {
  if (predHome === actualHome && predAway === actualAway) {
    return { result: 'exact', points: POINTS.exact };
  }
  const oneScoreRight = predHome === actualHome || predAway === actualAway;
  const predWin = predHome > predAway ? 'home' : predHome < predAway ? 'away' : 'draw';
  const actualWin = actualHome > actualAway ? 'home' : actualHome < actualAway ? 'away' : 'draw';
  const correctResult = predWin === actualWin;

  if (correctResult && oneScoreRight) return { result: 'correctPlusOne', points: POINTS.correctPlusOne };
  if (correctResult) return { result: 'correctResult', points: POINTS.correctResult };
  if (oneScoreRight) return { result: 'oneScore', points: POINTS.oneScore };
  return { result: 'wrong', points: POINTS.wrong };
}

async function settleMatch(matchId, homeScore, awayScore) {
  // Guard: check if already settled in Firestore
  const matchRef = db.collection('matches').doc(matchId);
  const matchDoc = await matchRef.get();
  if (matchDoc.exists && matchDoc.data().status === 'finished') {
    return false; // already settled
  }

  // Fetch all predictions for this match
  const preds = await db.collection('predictions')
    .where('matchId', '==', matchId)
    .get();

  if (preds.empty) {
    // No predictions — just mark match as finished
    await matchRef.set({ status: 'finished', homeScore, awayScore }, { merge: true });
    return true;
  }

  // Batch all writes (≤10 users = ≤21 ops — well under 500 limit)
  const batch = db.batch();

  for (const doc of preds.docs) {
    const d = doc.data();
    const { result, points } = calcResult(
      d.homeScore, d.awayScore, homeScore, awayScore
    );

    batch.update(doc.ref, { pointsEarned: points, result });

    const userRef = db.collection('users').doc(d.userId);
    const userUpdate = {
      totalPoints: admin.firestore.FieldValue.increment(points),
      predictionsCount: admin.firestore.FieldValue.increment(1),
    };
    if (result === 'exact')          userUpdate.exactCount          = admin.firestore.FieldValue.increment(1);
    if (result === 'correctPlusOne') userUpdate.correctPlusOneCount = admin.firestore.FieldValue.increment(1);
    if (result === 'correctResult')  userUpdate.correctResultCount  = admin.firestore.FieldValue.increment(1);
    if (result === 'oneScore')       userUpdate.oneScoreCount       = admin.firestore.FieldValue.increment(1);
    batch.update(userRef, userUpdate);
  }

  // Mark match settled
  batch.set(matchRef, { status: 'finished', homeScore, awayScore }, { merge: true });
  await batch.commit();

  // Write post-match notifications (non-critical, separate batch)
  try {
    const notifBatch = db.batch();
    for (const doc of preds.docs) {
      const d = doc.data();
      const { result, points } = calcResult(d.homeScore, d.awayScore, homeScore, awayScore);
      notifBatch.set(db.collection('notifications').doc(`${d.userId}_${matchId}`), {
        userId: d.userId,
        matchId,
        homeTeam: d.homeTeam || '',
        awayTeam: d.awayTeam || '',
        actualHome: homeScore,
        actualAway: awayScore,
        predHome: d.homeScore,
        predAway: d.awayScore,
        result,
        pointsEarned: points,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await notifBatch.commit();
  } catch (e) {
    console.error('Non-critical: failed to write notifications for', matchId, e);
  }

  return true;
}

async function refreshRanks() {
  const users = await db.collection('users').orderBy('totalPoints', 'desc').get();
  const batch = db.batch();
  users.docs.forEach((doc, i) => {
    batch.update(doc.ref, { rank: i + 1 });
  });
  await batch.commit();
}

// Runs every 2 minutes
exports.autoSettleMatches = functions
  .runWith({ timeoutSeconds: 60, memory: '256MB' })
  .pubsub
  .schedule('every 2 minutes')
  .onRun(async () => {
    try {
      const res = await fetch(ESPN_URL, { timeout: 10000 });
      if (!res.ok) { console.log('ESPN fetch failed:', res.status); return; }

      const data = await res.json();
      const events = data.events || [];

      let settled = 0;
      for (const event of events) {
        const comp = event.competitions[0];
        const statusType = comp.status.type;
        if (statusType.state !== 'post') continue; // only finished matches

        const matchId = event.id.toString();
        const home = comp.competitors.find(c => c.homeAway === 'home');
        const away = comp.competitors.find(c => c.homeAway === 'away');
        const homeScore = parseInt(home.score, 10);
        const awayScore = parseInt(away.score, 10);

        if (isNaN(homeScore) || isNaN(awayScore)) continue;

        const didSettle = await settleMatch(matchId, homeScore, awayScore);
        if (didSettle) settled++;
      }

      if (settled > 0) {
        console.log(`Settled ${settled} match(es). Refreshing ranks...`);
        await refreshRanks();
      }
    } catch (e) {
      console.error('autoSettleMatches error:', e);
    }
  });
