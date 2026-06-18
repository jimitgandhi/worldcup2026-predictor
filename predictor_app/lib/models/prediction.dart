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
  };
}
