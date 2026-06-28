import 'package:cloud_firestore/cloud_firestore.dart';

enum PredictionResult { exact, correctPlusOne, correctResult, oneScore, wrong, pending }

class Prediction {
  final String id; // {userId}_{matchId}
  final String userId;
  final String matchId;
  final int homeScore;
  final int awayScore;
  final int? pointsEarned;
  final PredictionResult result;
  final DateTime createdAt;
  final DateTime? kickoffTime; // match kickoff — used to filter upcoming vs past

  final String homeTeam;  // e.g. "USA"
  final String awayTeam;  // e.g. "Mexico"

  // Penalty bonus prediction (knockout matches only, optional)
  final int? penHome;         // user's predicted penalty score for home team
  final int? penAway;
  final int? penPointsEarned;
  final PredictionResult? penResult;

  const Prediction({
    required this.id,
    required this.userId,
    required this.matchId,
    required this.homeScore,
    required this.awayScore,
    this.pointsEarned,
    required this.result,
    required this.createdAt,
    this.kickoffTime,
    this.homeTeam = '',
    this.awayTeam = '',
    this.penHome,
    this.penAway,
    this.penPointsEarned,
    this.penResult,
  });

  static String makeId(String userId, String matchId) => '${userId}_$matchId';

  factory Prediction.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    PredictionResult result;
    switch (d['result'] as String? ?? 'pending') {
      case 'exact':           result = PredictionResult.exact;           break;
      case 'correctPlusOne':  result = PredictionResult.correctPlusOne;  break;
      case 'correctResult':   result = PredictionResult.correctResult;   break;
      case 'oneScore':        result = PredictionResult.oneScore;        break;
      case 'wrong':           result = PredictionResult.wrong;           break;
      default:                result = PredictionResult.pending;
    }
    PredictionResult? penResult;
    switch (d['penResult'] as String? ?? '') {
      case 'exact':           penResult = PredictionResult.exact;           break;
      case 'correctPlusOne':  penResult = PredictionResult.correctPlusOne;  break;
      case 'correctResult':   penResult = PredictionResult.correctResult;   break;
      case 'oneScore':        penResult = PredictionResult.oneScore;        break;
      case 'wrong':           penResult = PredictionResult.wrong;           break;
      default:                penResult = null;
    }
    return Prediction(
      id: doc.id,
      userId: d['userId'] ?? '',
      matchId: d['matchId'] ?? '',
      homeScore: d['homeScore'] as int? ?? 0,
      awayScore: d['awayScore'] as int? ?? 0,
      pointsEarned: d['pointsEarned'] as int?,
      result: result,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      kickoffTime: (d['kickoffTime'] as Timestamp?)?.toDate(),
      homeTeam: d['homeTeam'] as String? ?? '',
      awayTeam: d['awayTeam'] as String? ?? '',
      penHome: d['penHome'] as int?,
      penAway: d['penAway'] as int?,
      penPointsEarned: d['penPointsEarned'] as int?,
      penResult: penResult,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'userId': userId,
    'matchId': matchId,
    'homeScore': homeScore,
    'awayScore': awayScore,
    if (pointsEarned != null) 'pointsEarned': pointsEarned,
    'result': result.name,
    'createdAt': Timestamp.fromDate(createdAt),
    if (kickoffTime != null) 'kickoffTime': Timestamp.fromDate(kickoffTime!),
    'homeTeam': homeTeam,
    'awayTeam': awayTeam,
    if (penHome != null) 'penHome': penHome,
    if (penAway != null) 'penAway': penAway,
    if (penPointsEarned != null) 'penPointsEarned': penPointsEarned,
    if (penResult != null) 'penResult': penResult!.name,
  };
}
