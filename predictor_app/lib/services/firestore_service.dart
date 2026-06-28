import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/match.dart';
import '../models/prediction.dart';
import '../models/user_model.dart';
import 'scoring_service.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  // ─── Matches ────────────────────────────────────────────
  Stream<List<Match>> matchesStream() {
    return _db
        .collection('matches')
        .orderBy('kickoff')
        .snapshots()
        .map((s) => s.docs.map(Match.fromFirestore).toList());
  }

  Future<void> upsertMatch(Match match) async {
    await _db.collection('matches').doc(match.id).set(match.toFirestore(), SetOptions(merge: true));
  }

  // ─── Predictions ────────────────────────────────────────
  Stream<List<Prediction>> userPredictionsStream(String userId) {
    return _db
        .collection('predictions')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((s) => s.docs.map(Prediction.fromFirestore).toList());
  }

  /// Fetch another user's settled/live predictions for the leaderboard popup.
  /// Returns predictions where kickoffTime is in the past (match already started).
  Future<List<Prediction>> fetchUserPastPredictions(String userId) async {
    final snap = await _db
        .collection('predictions')
        .where('userId', isEqualTo: userId)
        .get();
    final now = DateTime.now();
    final allPreds = snap.docs.map(Prediction.fromFirestore).toList();
    final filtered = allPreds
        .where((p) => p.kickoffTime != null && !p.kickoffTime!.isAfter(now))
        .toList();
    filtered.sort((a, b) {
      // Sort by kickoffTime descending (most recent first)
      // Nulls go to the end
      if (a.kickoffTime == null && b.kickoffTime == null) return 0;
      if (a.kickoffTime == null) return 1;
      if (b.kickoffTime == null) return -1;
      return b.kickoffTime!.compareTo(a.kickoffTime!);
    });
    return filtered;
  }

  Future<Prediction?> getPrediction(String userId, String matchId) async {
    final id = Prediction.makeId(userId, matchId);
    final doc = await _db.collection('predictions').doc(id).get();
    if (!doc.exists) return null;
    return Prediction.fromFirestore(doc);
  }

  Future<void> submitPrediction({
    required String userId,
    required String matchId,
    required int homeScore,
    required int awayScore,
    String homeTeam = '',
    String awayTeam = '',
    DateTime? kickoff,
    int? penHome,
    int? penAway,
  }) async {
    final id = Prediction.makeId(userId, matchId);
    await _db.collection('predictions').doc(id).set({
      'userId': userId,
      'matchId': matchId,
      'homeScore': homeScore,
      'awayScore': awayScore,
      'homeTeam': homeTeam,
      'awayTeam': awayTeam,
      'result': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      if (kickoff != null) 'kickoffTime': Timestamp.fromDate(kickoff),
      if (penHome != null) 'penHome': penHome,
      if (penAway != null) 'penAway': penAway,
    }, SetOptions(merge: true));
  }

  // ─── Score settling (called after match finishes) ────────
  Future<void> settleMatch({
    required String matchId,
    required int actualHome,
    required int actualAway,
    int? penaltyHome,
    int? penaltyAway,
  }) async {
    // Guard: skip if already settled to prevent double-settling
    final matchDoc = await _db.collection('matches').doc(matchId).get();
    if (matchDoc.exists && matchDoc.data()?['status'] == 'finished') return;
    // Get all predictions for this match
    final preds = await _db
        .collection('predictions')
        .where('matchId', isEqualTo: matchId)
        .get();

    final batch = _db.batch();

    for (final doc in preds.docs) {
      final predHome = doc['homeScore'] as int;
      final predAway = doc['awayScore'] as int;
      final userId = doc['userId'] as String;

      final scored = ScoringService.calculate(
        predHome: predHome, predAway: predAway,
        actualHome: actualHome, actualAway: actualAway,
      );

      // Penalty bonus — only if match went to penalties AND user made a penalty prediction
      int penPts = 0;
      PredictionResult? penResult;
      if (penaltyHome != null && penaltyAway != null) {
        final userPenHome = doc.data()['penHome'] as int?;
        final userPenAway = doc.data()['penAway'] as int?;
        if (userPenHome != null && userPenAway != null) {
          final penScored = ScoringService.calculate(
            predHome: userPenHome, predAway: userPenAway,
            actualHome: penaltyHome, actualAway: penaltyAway,
          );
          penPts = penScored.points;
          penResult = penScored.result;
        }
      }

      final totalPts = scored.points + penPts;

      // Update prediction
      batch.update(doc.reference, {
        'pointsEarned': scored.points,
        'result': scored.result.name,
        if (penResult != null) 'penPointsEarned': penPts,
        if (penResult != null) 'penResult': penResult.name,
      });

      // Update user totals
      final userRef = _db.collection('users').doc(userId);
      batch.update(userRef, {
        'totalPoints': FieldValue.increment(totalPts),
        'predictionsCount': FieldValue.increment(1),
        if (scored.result == PredictionResult.exact)
          'exactCount': FieldValue.increment(1),
        if (scored.result == PredictionResult.correctPlusOne)
          'correctPlusOneCount': FieldValue.increment(1),
        if (scored.result == PredictionResult.correctResult)
          'correctResultCount': FieldValue.increment(1),
        if (scored.result == PredictionResult.oneScore)
          'oneScoreCount': FieldValue.increment(1),
        if (penPts > 0)  // only count when user actually scored pen bonus points
          'penBonusCount': FieldValue.increment(1),
      });
    }

    // Update match status — use set+merge so it works even if the doc doesn't exist in Firestore yet
    batch.set(_db.collection('matches').doc(matchId), {
      'status': 'finished',
      'homeScore': actualHome,
      'awayScore': actualAway,
      if (penaltyHome != null) 'penaltyHomeScore': penaltyHome,
      if (penaltyAway != null) 'penaltyAwayScore': penaltyAway,
    }, SetOptions(merge: true));

    await batch.commit();
    await refreshRanks();

    // Write post-match notifications for each participant (non-critical)
    try {
      final notifBatch = _db.batch();
      for (final doc in preds.docs) {
        final userId = doc['userId'] as String;
        final scored = ScoringService.calculate(
          predHome: doc['homeScore'] as int,
          predAway: doc['awayScore'] as int,
          actualHome: actualHome,
          actualAway: actualAway,
        );
        int penPts = 0;
        if (penaltyHome != null && penaltyAway != null) {
          final uPH = doc.data()['penHome'] as int?;
          final uPA = doc.data()['penAway'] as int?;
          if (uPH != null && uPA != null) {
            penPts = ScoringService.calculate(
              predHome: uPH, predAway: uPA,
              actualHome: penaltyHome, actualAway: penaltyAway,
            ).points;
          }
        }
        final notifRef = _db.collection('notifications').doc('${userId}_$matchId');
        notifBatch.set(notifRef, {
          'userId': userId,
          'matchId': matchId,
          'homeTeam': doc.data()['homeTeam'] ?? '',
          'awayTeam': doc.data()['awayTeam'] ?? '',
          'actualHome': actualHome,
          'actualAway': actualAway,
          'predHome': doc['homeScore'],
          'predAway': doc['awayScore'],
          'result': scored.result.name,
          'pointsEarned': scored.points + penPts,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await notifBatch.commit();
    } catch (_) {
      // Non-critical — notifications failing should not break settle
    }
  }

  Future<void> refreshRanks() async {
    final users = await _db
        .collection('users')
        .orderBy('totalPoints', descending: true)
        .get();
    final batch = _db.batch();
    for (int i = 0; i < users.docs.length; i++) {
      batch.update(users.docs[i].reference, {'rank': i + 1});
    }
    await batch.commit();
  }

  /// Re-settle a match with corrected scores (admin path only).
  /// Handles both first-time settlement and correcting a previously settled match.
  /// Calculates deltas from old → new scores to keep user totals consistent.
  Future<void> resettleMatch({
    required String matchId,
    required int actualHome,
    required int actualAway,
    int? penaltyHome,
    int? penaltyAway,
  }) async {
    final preds = await _db
        .collection('predictions')
        .where('matchId', isEqualTo: matchId)
        .get();

    final Map<String, int> pointDeltas = {};
    final Map<String, Map<String, int>> countDeltas = {};
    final List<MapEntry<DocumentReference, Map<String, dynamic>>> predUpdates = [];

    for (final doc in preds.docs) {
      final userId = doc['userId'] as String;
      final predHome = doc['homeScore'] as int;
      final predAway = doc['awayScore'] as int;
      final oldResultStr = doc.data()['result'] as String? ?? 'pending';
      final oldPoints = (doc.data()['pointsEarned'] as int? ?? 0)
          + (doc.data()['penPointsEarned'] as int? ?? 0);

      final scored = ScoringService.calculate(
        predHome: predHome, predAway: predAway,
        actualHome: actualHome, actualAway: actualAway,
      );

      // Penalty bonus
      int penPts = 0;
      PredictionResult? penResult;
      if (penaltyHome != null && penaltyAway != null) {
        final uPH = doc.data()['penHome'] as int?;
        final uPA = doc.data()['penAway'] as int?;
        if (uPH != null && uPA != null) {
          final ps = ScoringService.calculate(
            predHome: uPH, predAway: uPA,
            actualHome: penaltyHome, actualAway: penaltyAway,
          );
          penPts = ps.points;
          penResult = ps.result;
        }
      }

      final totalPts = scored.points + penPts;

      predUpdates.add(MapEntry(doc.reference, {
        'pointsEarned': scored.points,
        'result': scored.result.name,
        if (penResult != null) 'penPointsEarned': penPts,
        if (penResult != null) 'penResult': penResult.name,
        // Explicitly clear stale pen fields when match is not penalty
        if (penResult == null) 'penPointsEarned': FieldValue.delete(),
        if (penResult == null) 'penResult': FieldValue.delete(),
      }));

      pointDeltas[userId] = (pointDeltas[userId] ?? 0) + totalPts - oldPoints;

      final counts = countDeltas.putIfAbsent(userId, () => {
        'exactCount': 0, 'correctPlusOneCount': 0,
        'correctResultCount': 0, 'oneScoreCount': 0, 'predictionsCount': 0,
        'penBonusCount': 0,
      });

      // Reverse old result count
      switch (oldResultStr) {
        case 'exact':          counts['exactCount'] = counts['exactCount']! - 1; break;
        case 'correctPlusOne': counts['correctPlusOneCount'] = counts['correctPlusOneCount']! - 1; break;
        case 'correctResult':  counts['correctResultCount'] = counts['correctResultCount']! - 1; break;
        case 'oneScore':       counts['oneScoreCount'] = counts['oneScoreCount']! - 1; break;
        case 'pending':        counts['predictionsCount'] = counts['predictionsCount']! + 1; break;
      }

      // Reverse old penBonusCount contribution
      final oldPenPts = doc.data()['penPointsEarned'] as int? ?? 0;
      if (oldPenPts > 0) counts['penBonusCount'] = counts['penBonusCount']! - 1;

      // Apply new result count
      if (scored.result == PredictionResult.exact)
        counts['exactCount'] = counts['exactCount']! + 1;
      else if (scored.result == PredictionResult.correctPlusOne)
        counts['correctPlusOneCount'] = counts['correctPlusOneCount']! + 1;
      else if (scored.result == PredictionResult.correctResult)
        counts['correctResultCount'] = counts['correctResultCount']! + 1;
      else if (scored.result == PredictionResult.oneScore)
        counts['oneScoreCount'] = counts['oneScoreCount']! + 1;

      // Apply new penBonusCount contribution
      if (penPts > 0) counts['penBonusCount'] = counts['penBonusCount']! + 1;
    }

    final batch = _db.batch();
    for (final entry in predUpdates) {
      batch.update(entry.key, entry.value);
    }

    for (final userId in pointDeltas.keys) {
      final userRef = _db.collection('users').doc(userId);
      final counts = countDeltas[userId]!;
      batch.update(userRef, {
        'totalPoints': FieldValue.increment(pointDeltas[userId]!),
        if (counts['exactCount'] != 0)
          'exactCount': FieldValue.increment(counts['exactCount']!),
        if (counts['correctPlusOneCount'] != 0)
          'correctPlusOneCount': FieldValue.increment(counts['correctPlusOneCount']!),
        if (counts['correctResultCount'] != 0)
          'correctResultCount': FieldValue.increment(counts['correctResultCount']!),
        if (counts['oneScoreCount'] != 0)
          'oneScoreCount': FieldValue.increment(counts['oneScoreCount']!),
        if (counts['predictionsCount'] != 0)
          'predictionsCount': FieldValue.increment(counts['predictionsCount']!),
        if (counts['penBonusCount'] != 0)
          'penBonusCount': FieldValue.increment(counts['penBonusCount']!),
      });
    }

    // Update match scores — explicitly delete penalty fields if not a penalty match
    batch.set(_db.collection('matches').doc(matchId), {
      'status': 'finished',
      'homeScore': actualHome,
      'awayScore': actualAway,
      if (penaltyHome != null) 'penaltyHomeScore': penaltyHome
        else 'penaltyHomeScore': FieldValue.delete(),
      if (penaltyAway != null) 'penaltyAwayScore': penaltyAway
        else 'penaltyAwayScore': FieldValue.delete(),
    }, SetOptions(merge: true));

    await batch.commit();
    await refreshRanks();
  }


  /// Re-runs ScoringService.calculate() on every settled prediction, updates
  /// pointsEarned, resets all user point totals from scratch, and refreshes ranks.
  Future<int> recalcAllScores() async {
    // 1. Fetch all settled predictions (excluding only pending)
    final preds = await _db
        .collection('predictions')
        .where('result', isNotEqualTo: 'pending')
        .get();

    if (preds.docs.isEmpty) return 0;

    // 2. Fetch all match docs to get actual scores (including penalty scores)
    final matchDocs = await _db.collection('matches').get();
    final matchScores = <String, Map<String, int?>>{};
    for (final doc in matchDocs.docs) {
      final d = doc.data();
      if (d['homeScore'] != null && d['awayScore'] != null) {
        matchScores[doc.id] = {
          'home': d['homeScore'] as int,
          'away': d['awayScore'] as int,
          'penaltyHome': d['penaltyHomeScore'] as int?,
          'penaltyAway': d['penaltyAwayScore'] as int?,
        };
      }
    }

    // 3. Recalculate each prediction, accumulate user totals
    final Map<String, int> userPointDeltas = {};
    final Map<String, Map<String, int>> userCountReset = {};
    final List<MapEntry<DocumentReference, Map<String, dynamic>>> predUpdates = [];

    for (final doc in preds.docs) {
      final d = doc.data();
      final matchId = d['matchId'] as String? ?? '';
      final scores = matchScores[matchId];
      if (scores == null) continue;

      final scored = ScoringService.calculate(
        predHome: d['homeScore'] as int,
        predAway: d['awayScore'] as int,
        actualHome: scores['home']!,
        actualAway: scores['away']!,
      );

      // Penalty bonus
      int penPts = 0;
      PredictionResult? penResult;
      final penaltyHome = scores['penaltyHome'];
      final penaltyAway = scores['penaltyAway'];
      if (penaltyHome != null && penaltyAway != null) {
        final uPH = d['penHome'] as int?;
        final uPA = d['penAway'] as int?;
        if (uPH != null && uPA != null) {
          final ps = ScoringService.calculate(
            predHome: uPH, predAway: uPA,
            actualHome: penaltyHome, actualAway: penaltyAway,
          );
          penPts = ps.points;
          penResult = ps.result;
        }
      }

      predUpdates.add(MapEntry(doc.reference, {
        'pointsEarned': scored.points,
        'result': scored.result.name,
        if (penResult != null) 'penPointsEarned': penPts,
        if (penResult != null) 'penResult': penResult.name,
        if (penResult == null) 'penPointsEarned': FieldValue.delete(),
        if (penResult == null) 'penResult': FieldValue.delete(),
      }));

      final userId = d['userId'] as String? ?? '';
      userPointDeltas[userId] = (userPointDeltas[userId] ?? 0) + scored.points + penPts;

      final counts = userCountReset.putIfAbsent(userId, () => {
        'exactCount': 0, 'correctPlusOneCount': 0,
        'correctResultCount': 0, 'oneScoreCount': 0, 'predictionsCount': 0,
        'penBonusCount': 0,
      });
      counts['predictionsCount'] = counts['predictionsCount']! + 1;
      if (penPts > 0) counts['penBonusCount'] = counts['penBonusCount']! + 1;
      if (scored.result == PredictionResult.exact)          counts['exactCount'] = counts['exactCount']! + 1;
      if (scored.result == PredictionResult.correctPlusOne) counts['correctPlusOneCount'] = counts['correctPlusOneCount']! + 1;
      if (scored.result == PredictionResult.correctResult)  counts['correctResultCount'] = counts['correctResultCount']! + 1;
      if (scored.result == PredictionResult.oneScore)       counts['oneScoreCount'] = counts['oneScoreCount']! + 1;
    }

    // Commit prediction updates in chunks of 450 (stay under 500-op batch limit)
    const chunkSize = 450;
    for (int i = 0; i < predUpdates.length; i += chunkSize) {
      final chunk = predUpdates.sublist(i, (i + chunkSize).clamp(0, predUpdates.length));
      final batch = _db.batch();
      for (final entry in chunk) {
        batch.update(entry.key, entry.value);
      }
      await batch.commit();
    }

    // 4. Reset all user point totals (≤10 users — one batch is fine)
    final userBatch = _db.batch();
    final allUsers = await _db.collection('users').get();
    for (final uDoc in allUsers.docs) {
      final uid = uDoc.id;
      final counts = userCountReset[uid];
      userBatch.update(uDoc.reference, {
        'totalPoints': userPointDeltas[uid] ?? 0,
        'predictionsCount': counts?['predictionsCount'] ?? 0,
        'exactCount': counts?['exactCount'] ?? 0,
        'correctPlusOneCount': counts?['correctPlusOneCount'] ?? 0,
        'correctResultCount': counts?['correctResultCount'] ?? 0,
        'oneScoreCount': counts?['oneScoreCount'] ?? 0,
        'penBonusCount': counts?['penBonusCount'] ?? 0,
      });
    }
    await userBatch.commit();
    await refreshRanks();
    return preds.docs.length;
  }

  // ─── Delete predictions ─────────────────────────────────
  /// Delete all predictions for a specific match
  Future<void> deletePredictionsForMatch(String matchId) async {
    final preds = await _db
        .collection('predictions')
        .where('matchId', isEqualTo: matchId)
        .get();
    final batch = _db.batch();
    for (final doc in preds.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Fetch all predictions for a specific match (for match predictions view)
  Future<List<Prediction>> fetchMatchPredictions(String matchId) async {
    final snap = await _db
        .collection('predictions')
        .where('matchId', isEqualTo: matchId)
        .get();
    return snap.docs.map(Prediction.fromFirestore).toList();
  }

  /// Fetch ALL predictions across all users (for analytics score history)
  Future<List<Prediction>> fetchAllPredictions() async {
    final snap = await _db.collection('predictions').get();
    return snap.docs.map(Prediction.fromFirestore).toList();
  }

  /// Fetch all finished matches ordered by kickoff (for analytics timeline)
  Future<List<Match>> fetchFinishedMatches() async {
    final snap = await _db
        .collection('matches')
        .orderBy('kickoff')
        .get();
    return snap.docs
        .map(Match.fromFirestore)
        .where((m) => m.status == MatchStatus.finished)
        .toList();
  }

  /// Backfill kickoffTime for all predictions that don't have it
  Future<int> backfillKickoffTimes() async {
    // Get all predictions without kickoffTime
    final allPreds = await _db.collection('predictions').get();
    
    // Get all matches
    final matches = await _db.collection('matches').get();
    final matchMap = <String, DateTime>{};
    for (final doc in matches.docs) {
      final data = doc.data();
      final kickoff = (data['kickoff'] as Timestamp?)?.toDate();
      if (kickoff != null) {
        matchMap[doc.id] = kickoff;
      }
    }
    
    // Update predictions in batches
    int updated = 0;
    final batch = _db.batch();
    for (final doc in allPreds.docs) {
      final data = doc.data();
      // Skip if already has kickoffTime
      if (data['kickoffTime'] != null) continue;
      
      final matchId = data['matchId'] as String?;
      if (matchId != null && matchMap.containsKey(matchId)) {
        batch.update(doc.reference, {
          'kickoffTime': Timestamp.fromDate(matchMap[matchId]!),
        });
        updated++;
      }
    }
    
    if (updated > 0) {
      await batch.commit();
    }
    return updated;
  }

  /// Delete ALL predictions (for clearing test data)
  Future<int> deleteAllPredictions() async {
    int total = 0;
    QuerySnapshot snap;
    do {
      snap = await _db.collection('predictions').limit(400).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      total += snap.docs.length;
    } while (snap.docs.length == 400);
    // Also reset all user point totals
    final users = await _db.collection('users').get();
    final userBatch = _db.batch();
    for (final doc in users.docs) {
      userBatch.update(doc.reference, {
        'totalPoints': 0,
        'predictionsCount': 0,
        'exactCount': 0,
        'correctPlusOneCount': 0,
        'correctResultCount': 0,
        'oneScoreCount': 0,
        'rank': 0,
      });
    }
    await userBatch.commit();
    return total;
  }


  Stream<List<UserModel>> leaderboardStream({int limit = 50}) {
    return _db
        .collection('users')
        .orderBy('totalPoints', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(UserModel.fromFirestore).toList());
  }

  // ─── Current user ────────────────────────────────────────
  Stream<UserModel?> currentUserStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists ? UserModel.fromFirestore(doc) : null);
  }

  // ─── Delete user ─────────────────────────────────────────
  Future<void> deleteUser(String userId) async {
    // Delete all their predictions
    QuerySnapshot snap;
    do {
      snap = await _db.collection('predictions').where('userId', isEqualTo: userId).limit(400).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) batch.delete(doc.reference);
      await batch.commit();
    } while (snap.docs.length == 400);

    // Delete their notifications
    final notifs = await _db.collection('notifications').where('userId', isEqualTo: userId).get();
    if (notifs.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in notifs.docs) batch.delete(doc.reference);
      await batch.commit();
    }

    // Delete user doc
    await _db.collection('users').doc(userId).delete();
    await refreshRanks();
  }

  // ─── Notifications stream ────────────────────────────────
  Stream<QuerySnapshot> unreadNotificationsStream(String userId) {
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .snapshots();
  }

  Future<void> markNotificationRead(String notifId) async {
    await _db.collection('notifications').doc(notifId).update({'read': true});
  }

  // ─── Demo / mock match ───────────────────────────────────
  Future<void> upsertDemoMatch(Match match) async {
    await _db.collection('matches').doc(match.id).set(match.toFirestore());
  }

  Future<void> updateDemoScore(String matchId, int homeScore, int awayScore) async {
    await _db.collection('matches').doc(matchId).update({
      'homeScore': homeScore,
      'awayScore': awayScore,
      'status': 'live',
      'displayClock': '${((homeScore + awayScore) * 8 + 1).clamp(1, 90)}\'',
    });
  }

  Future<void> deleteDemoMatch(String matchId) async {
    await _db.collection('matches').doc(matchId).delete();
  }
}
