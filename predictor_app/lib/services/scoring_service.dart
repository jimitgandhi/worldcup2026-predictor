import '../models/prediction.dart';

class ScoringService {
  // Main match scoring
  static const int exactPoints          = 50;
  static const int correctPlusOnePoints = 30;
  static const int correctResultPoints  = 20;
  static const int oneScorePoints       = 10;
  static const int wrongPoints          = 0;

  // Penalty bonus scoring (half of main)
  static const int penExactPoints          = 25;
  static const int penCorrectPlusOnePoints = 15;
  static const int penCorrectResultPoints  = 10;
  static const int penOneScorePoints       = 5;

  /// Calculate points and result for a prediction vs actual match result.
  ///
  /// Scoring: Exact score (50), Correct+OneScore stacked (30), Correct result (20),
  /// One score right (10), Wrong (0).
  static ({int points, PredictionResult result}) calculate({
    required int predHome, required int predAway,
    required int actualHome, required int actualAway,
  }) {
    // Exact score — both numbers match
    if (predHome == actualHome && predAway == actualAway) {
      return (points: exactPoints, result: PredictionResult.exact);
    }

    final oneScoreRight = predHome == actualHome || predAway == actualAway;
    final predResult = _result(predHome, predAway);
    final actualResult = _result(actualHome, actualAway);
    final correctResult = predResult == actualResult;

    // Stacked: correct result + one score right = 30 pts
    if (correctResult && oneScoreRight) {
      return (points: correctPlusOnePoints, result: PredictionResult.correctPlusOne);
    }
    // Correct result only = 20 pts
    if (correctResult) {
      return (points: correctResultPoints, result: PredictionResult.correctResult);
    }
    // One score right only (wrong result) = 10 pts
    if (oneScoreRight) {
      return (points: oneScorePoints, result: PredictionResult.oneScore);
    }
    return (points: wrongPoints, result: PredictionResult.wrong);
  }

  /// Calculate penalty bonus points (half of main scoring).
  static ({int points, PredictionResult result}) calculatePen({
    required int predHome, required int predAway,
    required int actualHome, required int actualAway,
  }) {
    if (predHome == actualHome && predAway == actualAway) {
      return (points: penExactPoints, result: PredictionResult.exact);
    }

    final oneScoreRight = predHome == actualHome || predAway == actualAway;
    final predResult = _result(predHome, predAway);
    final actualResult = _result(actualHome, actualAway);
    final correctResult = predResult == actualResult;

    if (correctResult && oneScoreRight) {
      return (points: penCorrectPlusOnePoints, result: PredictionResult.correctPlusOne);
    }
    if (correctResult) {
      return (points: penCorrectResultPoints, result: PredictionResult.correctResult);
    }
    if (oneScoreRight) {
      return (points: penOneScorePoints, result: PredictionResult.oneScore);
    }
    return (points: 0, result: PredictionResult.wrong);
  }

  static _MatchResult _result(int home, int away) {
    if (home > away) return _MatchResult.homeWin;
    if (away > home) return _MatchResult.awayWin;
    return _MatchResult.draw;
  }

  static String resultLabel(PredictionResult result) {
    switch (result) {
      case PredictionResult.exact:          return 'Exact Score';
      case PredictionResult.correctPlusOne: return 'Almost Correct';
      case PredictionResult.correctResult:  return 'Correct Result';
      case PredictionResult.oneScore:       return 'One Score Right';
      case PredictionResult.wrong:          return 'Wrong';
      case PredictionResult.pending:        return 'Pending';
    }
  }

  static int pointsFor(PredictionResult result) {
    switch (result) {
      case PredictionResult.exact:          return exactPoints;
      case PredictionResult.correctPlusOne: return correctPlusOnePoints;
      case PredictionResult.correctResult:  return correctResultPoints;
      case PredictionResult.oneScore:       return oneScorePoints;
      default:                              return 0;
    }
  }
}

enum _MatchResult { homeWin, awayWin, draw }
