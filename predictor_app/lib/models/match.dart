import 'package:cloud_firestore/cloud_firestore.dart';

enum MatchStatus { upcoming, live, finished }

class Match {
  final String id;
  final String homeTeam;
  final String awayTeam;
  final String homeTeamCode; // e.g. 'us', 'br' for flagcdn
  final String awayTeamCode;
  final String homeTeamLogo;
  final String awayTeamLogo;
  final String group;
  final String venue;
  final DateTime kickoff;
  final MatchStatus status;
  final int? homeScore;
  final int? awayScore;
  final String? displayClock; // e.g. "67'"
  final bool isKnockout;
  final int? penaltyHomeScore; // penalty shootout score (e.g. 5)
  final int? penaltyAwayScore;

  bool get wentToPenalties => penaltyHomeScore != null && penaltyAwayScore != null;

  /// True when a live knockout match hasn't gone to penalties yet — pen predictions can still be updated.
  bool get isPenPredictionOpen => status == MatchStatus.live && isKnockout && !wentToPenalties;

  const Match({
    required this.id,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeTeamCode,
    required this.awayTeamCode,
    required this.homeTeamLogo,
    required this.awayTeamLogo,
    required this.group,
    required this.venue,
    required this.kickoff,
    required this.status,
    this.homeScore,
    this.awayScore,
    this.displayClock,
    this.isKnockout = false,
    this.penaltyHomeScore,
    this.penaltyAwayScore,
  });

  bool get isPredictionOpen =>
      status == MatchStatus.upcoming &&
      DateTime.now().isBefore(kickoff);

  factory Match.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    MatchStatus status;
    switch (d['status'] as String? ?? 'upcoming') {
      case 'live':   status = MatchStatus.live;     break;
      case 'finished': status = MatchStatus.finished; break;
      default:       status = MatchStatus.upcoming;
    }
    return Match(
      id: doc.id,
      homeTeam: d['homeTeam'] ?? '',
      awayTeam: d['awayTeam'] ?? '',
      homeTeamCode: d['homeTeamCode'] ?? '',
      awayTeamCode: d['awayTeamCode'] ?? '',
      homeTeamLogo: d['homeTeamLogo'] ?? '',
      awayTeamLogo: d['awayTeamLogo'] ?? '',
      group: d['group'] ?? '',
      venue: d['venue'] ?? '',
      kickoff: (d['kickoff'] as Timestamp).toDate(),
      status: status,
      homeScore: d['homeScore'] as int?,
      awayScore: d['awayScore'] as int?,
      displayClock: d['displayClock'] as String?,
      isKnockout: d['isKnockout'] as bool? ?? false,
      penaltyHomeScore: d['penaltyHomeScore'] as int?,
      penaltyAwayScore: d['penaltyAwayScore'] as int?,
    );
  }

  factory Match.fromEspn(Map<String, dynamic> event) {
    final competition = (event['competitions'] as List).first as Map<String, dynamic>;
    final competitors = competition['competitors'] as List;
    final home = competitors.firstWhere((c) => c['homeAway'] == 'home');
    final away = competitors.firstWhere((c) => c['homeAway'] == 'away');
    final statusObj = competition['status'] as Map<String, dynamic>;
    final statusType = statusObj['type'] as Map<String, dynamic>;

    MatchStatus status;
    final state = statusType['state'] as String? ?? 'pre';
    if (state == 'in') status = MatchStatus.live;
    else if (state == 'post') status = MatchStatus.finished;
    else status = MatchStatus.upcoming;

    return Match(
      id: event['id'].toString(),
      homeTeam: home['team']['displayName'] ?? '',
      awayTeam: away['team']['displayName'] ?? '',
      homeTeamCode: (home['team']['abbreviation'] as String? ?? '').toLowerCase(),
      awayTeamCode: (away['team']['abbreviation'] as String? ?? '').toLowerCase(),
      homeTeamLogo: home['team']['logo'] ?? '',
      awayTeamLogo: away['team']['logo'] ?? '',
      group: competition['altGameNote'] ?? '',
      venue: competition['venue']?['fullName'] ?? '',
      kickoff: DateTime.parse(event['date'] as String).toLocal(),
      status: status,
      homeScore: int.tryParse(home['score']?.toString() ?? ''),
      awayScore: int.tryParse(away['score']?.toString() ?? ''),
      displayClock: statusObj['displayClock'] as String?,
      // Knockout only if ESPN explicitly marks it as a knockout round
      isKnockout: () {
        final note = (competition['altGameNote'] as String? ?? '').toLowerCase();
        return note.contains('round of') || note.contains('quarterfinal') ||
               note.contains('semifinal') || note.contains('final') ||
               note.contains('3rd place') || note.contains('third place');
      }(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'homeTeam': homeTeam,
    'awayTeam': awayTeam,
    'homeTeamCode': homeTeamCode,
    'awayTeamCode': awayTeamCode,
    'homeTeamLogo': homeTeamLogo,
    'awayTeamLogo': awayTeamLogo,
    'group': group,
    'venue': venue,
    'kickoff': Timestamp.fromDate(kickoff),
    'status': status.name,
    'isKnockout': isKnockout,
    if (homeScore != null) 'homeScore': homeScore,
    if (awayScore != null) 'awayScore': awayScore,
    if (displayClock != null) 'displayClock': displayClock,
    if (penaltyHomeScore != null) 'penaltyHomeScore': penaltyHomeScore,
    if (penaltyAwayScore != null) 'penaltyAwayScore': penaltyAwayScore,
  };
}
