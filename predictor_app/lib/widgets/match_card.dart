import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/match.dart';
import '../models/prediction.dart';
import '../services/scoring_service.dart';
import '../theme/app_theme.dart';
import 'match_widgets.dart';

class MatchCard extends StatefulWidget {
  final Match match;
  final Prediction? prediction;
  final Future<void> Function(int home, int away, int? penHome, int? penAway)? onSubmit;

  const MatchCard({
    super.key,
    required this.match,
    this.prediction,
    this.onSubmit,
  });

  @override
  State<MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<MatchCard> {
  int _homeVal = 0;
  int _awayVal = 0;
  bool _saved = false;
  bool _submitting = false;

  // Penalty bonus prediction state (knockout only)
  int _penHomeVal = 1;
  int _penAwayVal = 0;
  bool _penModified = false; // true once user touches the pen stepper or has a saved pen pred

  @override
  void initState() {
    super.initState();
    final p = widget.prediction;
    if (p != null) {
      _homeVal = p.homeScore;
      _awayVal = p.awayScore;
      _saved = true;
      if (p.penHome != null && p.penAway != null) {
        _penHomeVal = p.penHome!;
        _penAwayVal = p.penAway!;
        _penModified = true; // existing pen prediction counts as intentional
      }
    }
  }

  @override
  void didUpdateWidget(covariant MatchCard old) {
    super.didUpdateWidget(old);
    if (old.prediction?.id != widget.prediction?.id) {
      final p = widget.prediction;
      _homeVal = p?.homeScore ?? 0;
      _awayVal = p?.awayScore ?? 0;
      _saved = p != null;
      _penModified = false;
      if (p?.penHome != null && p?.penAway != null) {
        _penHomeVal = p!.penHome!;
        _penAwayVal = p.penAway!;
        _penModified = true;
      }
    }
  }

  void _step(bool isHome, int delta) {
    setState(() {
      if (isHome) {
        _homeVal = (_homeVal + delta).clamp(0, 20);
      } else {
        _awayVal = (_awayVal + delta).clamp(0, 20);
      }
      _saved = false;
    });
  }

  void _stepPen(bool isHome, int delta) {
    setState(() {
      if (isHome) {
        _penHomeVal = (_penHomeVal + delta).clamp(0, 20);
      } else {
        _penAwayVal = (_penAwayVal + delta).clamp(0, 20);
      }
      _penModified = true; // user has intentionally set a pen prediction
      _saved = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final showScore = match.status != MatchStatus.upcoming;
    final canPredict = match.isPredictionOpen && widget.onSubmit != null;
    final hasPrediction = widget.prediction != null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _Header(match: match),
          _Body(
            match: match,
            showScore: showScore,
            predictHomeVal: canPredict ? _homeVal : null,
            predictAwayVal: canPredict ? _awayVal : null,
            penHomeVal: canPredict ? _penHomeVal : null,
            penAwayVal: canPredict ? _penAwayVal : null,
            onStep: canPredict ? _step : null,
            onPenStep: canPredict ? _stepPen : null,
          ),
          if (hasPrediction || canPredict || match.status != MatchStatus.upcoming)
            _Footer(
              match: match,
              prediction: widget.prediction,
              canPredict: canPredict,
              homeVal: _homeVal,
              awayVal: _awayVal,
              penHomeVal: _penHomeVal,
              penAwayVal: _penAwayVal,
              saved: _saved,
              submitting: _submitting,
              onSubmit: () async {
                setState(() => _submitting = true);
                try {
                  await widget.onSubmit!(
                    _homeVal, _awayVal,
                    // Only send pen prediction if user has actively set it
                    match.isKnockout && _penModified ? _penHomeVal : null,
                    match.isKnockout && _penModified ? _penAwayVal : null,
                  );
                  if (mounted) setState(() { _saved = true; _submitting = false; });
                } catch (_) {
                  if (mounted) {
                    setState(() => _submitting = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Color(0xFF7F1D1D),
                        content: Text('Failed to save pick. Check your connection.',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    );
                  }
                }
              },
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Match match;
  const _Header({required this.match});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(match.group,
            style: const TextStyle(
              color: AppColors.text3, fontSize: 10, fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            )),
          const SizedBox(width: 6),
          const Text('·', style: TextStyle(color: AppColors.text3, fontSize: 10)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(match.venue,
              style: const TextStyle(color: AppColors.text3, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          StatusBadge(
            status: match.status,
            clock: match.displayClock,
            kickoff: match.kickoff,
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Match match;
  final bool showScore;
  final int? predictHomeVal;
  final int? predictAwayVal;
  final int? penHomeVal;
  final int? penAwayVal;
  final Function(bool isHome, int delta)? onStep;
  final Function(bool isHome, int delta)? onPenStep;
  const _Body({
    required this.match,
    required this.showScore,
    this.predictHomeVal,
    this.predictAwayVal,
    this.penHomeVal,
    this.penAwayVal,
    this.onStep,
    this.onPenStep,
  });

  Widget _flagWithGlow(String logoUrl, Color? glow) {
    if (glow == null) return FlagImage(logoUrl: logoUrl, width: 52, height: 36);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: glow.withOpacity(0.5), blurRadius: 18, spreadRadius: 2)],
      ),
      child: FlagImage(logoUrl: logoUrl, width: 52, height: 36),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPredict = onStep != null;
    final showPenInput = canPredict && match.isKnockout && onPenStep != null;
    Color? homeGlow, awayGlow;

    if (predictHomeVal != null && predictAwayVal != null) {
      if (predictHomeVal! > predictAwayVal!) {
        homeGlow = AppColors.green;
      } else if (predictAwayVal! > predictHomeVal!) {
        awayGlow = AppColors.green;
      } else {
        homeGlow = awayGlow = AppColors.gold;
      }
    } else if (showScore && match.homeScore != null && match.awayScore != null) {
      final h = match.homeScore!;
      final a = match.awayScore!;
      if (match.wentToPenalties &&
          match.penaltyHomeScore != null && match.penaltyAwayScore != null) {
        if (match.penaltyHomeScore! > match.penaltyAwayScore!) {
          homeGlow = AppColors.green;
        } else {
          awayGlow = AppColors.green;
        }
      } else if (h > a) {
        homeGlow = AppColors.green;
      } else if (a > h) {
        awayGlow = AppColors.green;
      } else {
        homeGlow = awayGlow = AppColors.gold;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Column(
        children: [
          // Main score row: [home col] [center] [away col]
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Home team
              Expanded(
                child: Column(
                  children: [
                    _flagWithGlow(match.homeTeamLogo, homeGlow),
                    const SizedBox(height: 8),
                    Text(match.homeTeam,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    if (canPredict) ...[
                      const SizedBox(height: 10),
                      _SingleStepper(
                        value: predictHomeVal ?? 0,
                        onStep: (d) => onStep!(true, d),
                      ),
                    ],
                  ],
                ),
              ),
              // Center: VS or score dash
              SizedBox(
                width: 56,
                child: Column(
                  children: [
                    if (showScore) ...[
                      Text(
                        '${match.homeScore ?? 0} – ${match.awayScore ?? 0}',
                        style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: match.status == MatchStatus.live
                              ? AppColors.gold
                              : AppColors.text,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (match.status == MatchStatus.live && match.displayClock != null)
                        Text(match.displayClock!,
                          style: const TextStyle(
                            fontSize: 11, color: AppColors.red, fontWeight: FontWeight.w600,
                          )),
                      if (match.wentToPenalties)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0x1A7C3AED),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0x337C3AED)),
                              ),
                              child: Text(
                                '⚡ ${match.penaltyHomeScore}–${match.penaltyAwayScore}',
                                style: const TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700,
                                  color: Color(0xFFA78BFA),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ] else if (canPredict)
                      // Dash aligned to stepper row
                      Column(
                        children: [
                          // Spacer to push dash down to stepper level (flag 36 + gap 8 + name ~34 + gap 10 = ~88)
                          const SizedBox(height: 88),
                          const Text('–',
                            style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text3,
                            )),
                        ],
                      )
                    else
                      const Text('VS',
                        style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: AppColors.text3, letterSpacing: 1,
                        )),
                  ],
                ),
              ),
              // Away team
              Expanded(
                child: Column(
                  children: [
                    _flagWithGlow(match.awayTeamLogo, awayGlow),
                    const SizedBox(height: 8),
                    Text(match.awayTeam,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    if (canPredict) ...[
                      const SizedBox(height: 10),
                      _SingleStepper(
                        value: predictAwayVal ?? 0,
                        onStep: (d) => onStep!(false, d),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // Penalty section directly below, no flags
          if (showPenInput)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: BoxDecoration(
                  color: const Color(0x0F7C3AED),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x337C3AED)),
                ),
                child: Column(
                  children: [
                    const Text('⚡ PENALTY SHOOTOUT',
                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800,
                        letterSpacing: 0.8, color: Color(0xFFA78BFA))),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Center(
                            child: _SingleStepper(
                              value: penHomeVal ?? 0,
                              onStep: (d) => onPenStep!(true, d),
                              accentColor: const Color(0xFF7C3AED),
                              small: true,
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 56,
                          child: Center(
                            child: Text('–',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                                color: Color(0xFF7C6BAA))),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: _SingleStepper(
                              value: penAwayVal ?? 0,
                              onStep: (d) => onPenStep!(false, d),
                              accentColor: const Color(0xFF7C3AED),
                              small: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final Match match;
  final Prediction? prediction;
  final bool canPredict;
  final int homeVal;
  final int awayVal;
  final int penHomeVal;
  final int penAwayVal;
  final bool saved;
  final bool submitting;
  final VoidCallback onSubmit;

  const _Footer({
    required this.match,
    required this.prediction,
    required this.canPredict,
    required this.homeVal,
    required this.awayVal,
    required this.penHomeVal,
    required this.penAwayVal,
    required this.saved,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final hasPrediction = prediction != null;
    final isSettled = hasPrediction && prediction!.result != PredictionResult.pending;
    final isFinishedOrLive = match.status != MatchStatus.upcoming;
    final totalPoints = (prediction?.pointsEarned ?? 0) + (prediction?.penPointsEarned ?? 0);
    final hasPenBonus = prediction?.penResult != null && prediction!.penResult != PredictionResult.pending;

    // New predict layout: steppers are in _Body; footer only shows the CTA
    if (canPredict) {
      return _SubmitBarFull(saved: saved, submitting: submitting, onSubmit: onSubmit);
    }

    // Non-predict layout (result / settled / no prediction) — unchanged
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (hasPrediction)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your pick',
                  style: TextStyle(fontSize: 10, color: AppColors.text3,
                      fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                const SizedBox(height: 2),
                Text(
                  '${prediction!.homeScore} – ${prediction!.awayScore}',
                  style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text,
                  ),
                ),
                if (prediction!.penHome != null && prediction!.penAway != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.sports_soccer, size: 10, color: Color(0xFFA78BFA)),
                        const SizedBox(width: 3),
                        Text(
                          'Penalties: ${prediction!.penHome} – ${prediction!.penAway}',
                          style: const TextStyle(fontSize: 10, color: Color(0xFFA78BFA), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            )
          else if (isFinishedOrLive)
            const Text('No prediction',
              style: TextStyle(fontSize: 12, color: AppColors.text3,
                  fontStyle: FontStyle.italic)),

          const Spacer(),

          if (isSettled)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ResultChip(
                  result: prediction!.result,
                  points: prediction!.pointsEarned ?? 0,
                ),
                if (hasPenBonus) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x1A7C3AED),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0x337C3AED)),
                    ),
                    child: Text(
                      '⚡ +${prediction!.penPointsEarned ?? 0}',
                      style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: Color(0xFFA78BFA),
                      ),
                    ),
                  ),
                ],
              ],
            )
          else if (hasPrediction && isFinishedOrLive) ...[
            if (match.status == MatchStatus.live &&
                match.homeScore != null && match.awayScore != null)
              _LivePtsPreview(
                prediction: prediction!,
                liveHome: match.homeScore!,
                liveAway: match.awayScore!,
                wentToPenalties: match.wentToPenalties,
                livePenHome: match.penaltyHomeScore,
                livePenAway: match.penaltyAwayScore,
              )
            else
              ResultChip(result: PredictionResult.pending, points: 0),
          ]
          else if (!hasPrediction && isFinishedOrLive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.cardRaised,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text('+0 pts',
                style: TextStyle(color: AppColors.text3, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

/// Full-width gold submit bar — replaces the old side tall button and small submit btn.
class _SubmitBarFull extends StatelessWidget {
  final bool saved;
  final bool submitting;
  final VoidCallback onSubmit;
  const _SubmitBarFull({required this.saved, required this.submitting, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final disabled = saved || submitting;
    return GestureDetector(
      onTap: disabled ? null : onSubmit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.fromLTRB(14, 6, 14, 14),
        height: 48,
        decoration: BoxDecoration(
          gradient: (!saved && !submitting)
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF5C84B), Color(0xFFC9A84C)],
                )
              : null,
          color: saved ? AppColors.greenDim : (submitting ? AppColors.cardRaised : null),
          borderRadius: BorderRadius.circular(12),
          border: saved ? Border.all(color: AppColors.green.withOpacity(0.4)) : null,
          boxShadow: (!saved && !submitting)
              ? [BoxShadow(color: AppColors.gold.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 4))]
              : null,
        ),
        alignment: Alignment.center,
        child: submitting
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text2))
            : Text(
                saved ? '✓ Prediction saved' : 'Submit prediction',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: saved ? AppColors.green : const Color(0xFF1A1206),
                ),
              ),
      ),
    );
  }
}

class _SingleStepper extends StatelessWidget {
  final int value;
  final Function(int delta) onStep;
  final Color? accentColor;
  final bool small;

  const _SingleStepper({
    required this.value,
    required this.onStep,
    this.accentColor,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: accentColor != null ? accentColor!.withOpacity(0.08) : AppColors.cardRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accentColor != null ? accentColor!.withOpacity(0.3) : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepBtn(label: '−', onTap: () => onStep(-1)),
          SizedBox(
            width: small ? 24 : 28,
            child: Text('$value',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: small ? 14 : 16,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              )),
          ),
          _StepBtn(label: '+', onTap: () => onStep(1)),
        ],
      ),
    );
  }
}

class _ScoreStepper extends StatelessWidget {
  final int homeVal;
  final int awayVal;
  final Function(bool isHome, int delta) onStep;
  final Color? accentColor;

  const _ScoreStepper({
    required this.homeVal, required this.awayVal, required this.onStep,
    this.accentColor,
  });

  Widget _stepper(int value, bool isHome) {
    return Container(
      decoration: BoxDecoration(
        color: accentColor != null ? accentColor!.withOpacity(0.08) : AppColors.cardRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor != null ? accentColor!.withOpacity(0.3) : AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepBtn(label: '−', onTap: () => onStep(isHome, -1)),
          SizedBox(
            width: 28,
            child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text,
              )),
          ),
          _StepBtn(label: '+', onTap: () => onStep(isHome, 1)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _stepper(homeVal, true),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('–', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text3)),
        ),
        _stepper(awayVal, false),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _StepBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        alignment: Alignment.center,
        child: Text(label,
          style: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.w500, color: AppColors.text2,
          )),
      ),
    );
  }
}

class _SubmitBtn extends StatelessWidget {
  final bool saved;
  final bool submitting;
  final VoidCallback onSubmit;
  const _SubmitBtn({required this.saved, required this.submitting, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final disabled = saved || submitting;
    return GestureDetector(
      onTap: disabled ? null : onSubmit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: saved ? AppColors.greenDim : (submitting ? AppColors.cardRaised : const Color(0xFF2C1F06)),
          borderRadius: BorderRadius.circular(10),
          border: saved
              ? Border.all(color: AppColors.green.withOpacity(0.25))
              : submitting ? null : Border.all(color: AppColors.gold),
        ),
        child: submitting
          ? const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text2))
          : Text(
              saved ? '✓ Saved' : 'Submit',
              style: TextStyle(
                color: saved ? AppColors.green : AppColors.gold,
                fontSize: 12, fontWeight: FontWeight.w800,
              ),
            ),
      ),
    );
  }
}

/// Tall submit button — spans full height of the knockout prediction section.
class _SubmitBtnTall extends StatelessWidget {
  final bool saved;
  final bool submitting;
  final VoidCallback onSubmit;
  const _SubmitBtnTall({required this.saved, required this.submitting, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final disabled = saved || submitting;
    return GestureDetector(
      onTap: disabled ? null : onSubmit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
      width: 64,
        decoration: BoxDecoration(
          color: saved
              ? AppColors.greenDim
              : submitting
                  ? AppColors.cardRaised
                : const Color(0xFF2C1F06),
        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(15)),
        border: saved
            ? Border.all(color: AppColors.green.withOpacity(0.2))
            : submitting
                ? null
                : Border.all(color: AppColors.gold),
      ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (submitting)
              const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text2))
            else
              Icon(
                saved ? Icons.check_rounded : Icons.bookmark_rounded,
                size: 22,
                color: saved ? AppColors.green : AppColors.gold,
              ),
            const SizedBox(height: 5),
            Text(
              saved ? 'Saved' : 'Save',
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3,
                color: saved ? AppColors.green : AppColors.gold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a live pts preview — what the user would earn if the current live score is final.
class _LivePtsPreview extends StatelessWidget {
  final Prediction prediction;
  final int liveHome;
  final int liveAway;
  final bool wentToPenalties;
  final int? livePenHome;
  final int? livePenAway;

  const _LivePtsPreview({
    required this.prediction,
    required this.liveHome,
    required this.liveAway,
    this.wentToPenalties = false,
    this.livePenHome,
    this.livePenAway,
  });

  @override
  Widget build(BuildContext context) {
    final scored = ScoringService.calculate(
      predHome: prediction.homeScore,
      predAway: prediction.awayScore,
      actualHome: liveHome,
      actualAway: liveAway,
    );

    int penPts = 0;
    if (wentToPenalties && livePenHome != null && livePenAway != null
        && prediction.penHome != null && prediction.penAway != null) {
      penPts = ScoringService.calculate(
        predHome: prediction.penHome!,
        predAway: prediction.penAway!,
        actualHome: livePenHome!,
        actualAway: livePenAway!,
      ).points;
    }

    final pts = scored.points + penPts;
    final color = pts >= 80
        ? AppColors.green
        : pts >= 50
            ? AppColors.green
            : pts >= 20
                ? AppColors.gold
                : pts >= 10
                    ? AppColors.orange
                    : AppColors.text3;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            '+$pts pts${penPts > 0 ? ' (incl. pens)' : ''}',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Penalty bonus prediction section for knockout matches in upcoming tab.
class _PenaltyBonusSection extends StatelessWidget {
  final String homeTeam;
  final String awayTeam;
  final int penHomeVal;
  final int penAwayVal;
  final Function(bool isHome, int delta) onStep;

  const _PenaltyBonusSection({
    required this.homeTeam,
    required this.awayTeam,
    required this.penHomeVal,
    required this.penAwayVal,
    required this.onStep,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x0F7C3AED),
        border: const Border(top: BorderSide(color: Color(0x337C3AED))),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x1A7C3AED),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('⚡ PEN BONUS',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                      letterSpacing: 0.8, color: Color(0xFFA78BFA))),
              ),
              const SizedBox(width: 8),
              const Text('Penalty shootout prediction',
                style: TextStyle(fontSize: 12, color: AppColors.text2, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Text(homeTeam,
                style: const TextStyle(fontSize: 11, color: AppColors.text2, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis)),
              _ScoreStepper(homeVal: penHomeVal, awayVal: penAwayVal, onStep: onStep),
              Expanded(child: Text(awayTeam,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, color: AppColors.text2, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 6),
          const Text('If game goes to pens, same scoring rules apply.',
            style: TextStyle(fontSize: 10, color: AppColors.text3)),
        ],
      ),
    );
  }
}
