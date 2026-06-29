import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String displayName;
  final String email;
  final String? photoUrl;
  final int totalPoints;
  final int predictionsCount;
  final int exactCount;
  final int correctPlusOneCount;
  final int correctResultCount;
  final int oneScoreCount;
  final int penBonusCount;
  final int rank;
  final bool isAdmin;
  final String? doubleDownMatchId;

  const UserModel({
    required this.id,
    required this.displayName,
    required this.email,
    this.photoUrl,
    required this.totalPoints,
    required this.predictionsCount,
    required this.exactCount,
    required this.correctPlusOneCount,
    required this.correctResultCount,
    required this.oneScoreCount,
    this.penBonusCount = 0,
    required this.rank,
    this.isAdmin = false,
    this.doubleDownMatchId,
  });

  /// Result Hit Rate: % of predictions where the match outcome (W/D/L) was correct.
  /// Counts exact, correctPlusOne, and correctResult — all cases where result was right.
  /// Distinct from points: tells you how often your football knowledge was right,
  /// independent of whether you also guessed the scoreline.
  double get accuracy {
    if (predictionsCount == 0) return 0;
    return (exactCount + correctPlusOneCount + correctResultCount) / predictionsCount;
  }

  String get initials {
    final parts = displayName.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
  }

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      displayName: d['displayName'] ?? 'Player',
      email: d['email'] ?? '',
      photoUrl: d['photoUrl'] as String?,
      totalPoints: d['totalPoints'] as int? ?? 0,
      predictionsCount: d['predictionsCount'] as int? ?? 0,
      exactCount: d['exactCount'] as int? ?? 0,
      correctPlusOneCount: d['correctPlusOneCount'] as int? ?? 0,
      correctResultCount: d['correctResultCount'] as int? ?? 0,
      oneScoreCount: d['oneScoreCount'] as int? ?? 0,
      penBonusCount: d['penBonusCount'] as int? ?? 0,
      rank: d['rank'] as int? ?? 0,
      isAdmin: d['isAdmin'] as bool? ?? false,
      doubleDownMatchId: d['doubleDownMatchId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'displayName': displayName,
    'email': email,
    if (photoUrl != null) 'photoUrl': photoUrl,
    'totalPoints': totalPoints,
    'predictionsCount': predictionsCount,
    'exactCount': exactCount,
    'correctPlusOneCount': correctPlusOneCount,
    'correctResultCount': correctResultCount,
    'oneScoreCount': oneScoreCount,
    'penBonusCount': penBonusCount,
    'rank': rank,
  };
}
