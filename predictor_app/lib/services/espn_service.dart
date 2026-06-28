import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/match.dart';

class EspnService {
  static const _baseUrl =
      'https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world';

  // WC2026: group stage Jun 11 – Jul 3, knockout rounds through Final Jul 23
  static const _groupStageStart = '20260611';
  static const _groupStageEnd   = '20260723';

  /// Fetch today's live/upcoming matches for the live poll
  Future<List<Match>> fetchToday() async {
    try {
      final uri = Uri.parse('$_baseUrl/scoreboard');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final events = (data['events'] as List?) ?? [];
      return events.map((e) => Match.fromEspn(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch ALL group-stage matches across the full tournament window
  Future<List<Match>> fetchAllMatches() async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/scoreboard?dates=$_groupStageStart-$_groupStageEnd&limit=200',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return fetchToday();
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final events = (data['events'] as List?) ?? [];
      if (events.isEmpty) return fetchToday();
      return events.map((e) => Match.fromEspn(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return fetchToday();
    }
  }

  /// Legacy alias used by admin screen
  Future<List<Match>> fetchGroupStage() => fetchAllMatches();

  /// Legacy alias — keep schedule screen working
  Future<List<Match>> fetchMatches() => fetchAllMatches();
}
