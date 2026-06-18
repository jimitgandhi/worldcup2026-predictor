import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/match.dart';
import '../models/prediction.dart';
import '../theme/app_theme.dart';
import 'match_widgets.dart';

class MatchCard extends StatefulWidget {
  final Match match;
  final Prediction? prediction;
  final Future<void> Function(int home, int away)? onSubmit;

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

  @override
  void initState() {
    super.initState();
    if (widget.prediction != null) {
      _homeVal = widget.prediction!.homeScore;
      _awayVal = widget.prediction!.awayScore;
      _saved = true;
    }
  }

  @override
  void didUpdateWidget(covariant MatchCard old) {
    super.didUpdateWidget(old);
    // Reset saved state when prediction is deleted or replaced
    if (old.prediction?.id != widget.prediction?.id) {
      _homeVal = widget.prediction?.homeScore ?? 0;
      _awayVal = widget.prediction?.awayScore ?? 0;
      _saved = widget.prediction != null;
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
          // Header
          _Header(match: match),
          // Body
          _Body(
            match: match,
            showScore: showScore,
          ),
          // Footer — always show for live/finished; show for upcoming only if participating/can predict
          if (hasPrediction || canPredict || match.status != MatchStatus.upcoming)
            _Footer(
              match: match,
              prediction: widget.prediction,
              canPredict: canPredict,
              homeVal: _homeVal,
              awayVal: _awayVal,
              saved: _saved,
              submitting: _submitting,
              onStep: _step,
              onSubmit: () async {
                setState(() => _submitting = true);
                try {
                  await widget.onSubmit!(_homeVal, _awayVal);
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
  const _Body({required this.match, required this.showScore});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Row(
        children: [
          // Home team
          Expanded(
            child: Column(
              children: [
                FlagImage(logoUrl: match.homeTeamLogo),
                const SizedBox(height: 8),
                Text(match.homeTeam,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          // Score or VS
          SizedBox(
            width: 70,
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
                  ),
                  if (match.status == MatchStatus.live && match.displayClock != null)
                    Text(match.displayClock!,
                      style: const TextStyle(
                        fontSize: 11, color: AppColors.red, fontWeight: FontWeight.w600,
                      )),
                ] else
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
                FlagImage(logoUrl: match.awayTeamLogo),
                const SizedBox(height: 8),
                Text(match.awayTeam,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
              ],
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
  final bool saved;
  final bool submitting;
  final Function(bool isHome, int delta) onStep;
  final VoidCallback onSubmit;

  const _Footer({
    required this.match,
    required this.prediction,
    required this.canPredict,
    required this.homeVal,
    required this.awayVal,
    required this.saved,
    required this.submitting,
    required this.onStep,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final hasPrediction = prediction != null;
    final isSettled = hasPrediction && prediction!.result != PredictionResult.pending;
    final isFinishedOrLive = match.status != MatchStatus.upcoming;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Left: your prediction score (or "No prediction" label)
          if (canPredict)
            _ScoreStepper(homeVal: homeVal, awayVal: awayVal, onStep: onStep)
          else if (hasPrediction)
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
              ],
            )
          else if (isFinishedOrLive)
            const Text('No prediction',
              style: TextStyle(fontSize: 12, color: AppColors.text3,
                  fontStyle: FontStyle.italic)),

          const Spacer(),

          // Right: result chip, pending chip, submit btn, or +0 pts
          if (isSettled)
            ResultChip(result: prediction!.result, points: prediction!.pointsEarned)
          else if (hasPrediction && isFinishedOrLive)
            // Match finished but not settled yet — pending
            ResultChip(result: PredictionResult.pending, points: 0)
          else if (hasPrediction && canPredict)
            _SubmitBtn(saved: saved, submitting: submitting, onSubmit: onSubmit)
          else if (!hasPrediction && canPredict)
            _SubmitBtn(saved: saved, submitting: submitting, onSubmit: onSubmit)
          else if (!hasPrediction && isFinishedOrLive)
            // Didn't participate — show +0
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.cardRaised,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text('+0 pts',
                style: TextStyle(
                  color: AppColors.text3, fontSize: 11, fontWeight: FontWeight.w700,
                )),
            ),
        ],
      ),
    );
  }
}

class _ScoreStepper extends StatelessWidget {
  final int homeVal;
  final int awayVal;
  final Function(bool isHome, int delta) onStep;

  const _ScoreStepper({
    required this.homeVal, required this.awayVal, required this.onStep,
  });

  Widget _stepper(int value, bool isHome) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
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
        width: 30, height: 36,
        alignment: Alignment.center,
        child: Text(label,
          style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.text2,
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
          color: saved ? AppColors.greenDim : (submitting ? AppColors.cardRaised : AppColors.gold),
          borderRadius: BorderRadius.circular(10),
          border: saved ? Border.all(color: AppColors.green.withOpacity(0.25)) : null,
        ),
        child: submitting
          ? const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text2))
          : Text(
              saved ? '✓ Saved' : 'Submit',
              style: TextStyle(
                color: saved ? AppColors.green : AppColors.bg,
                fontSize: 12, fontWeight: FontWeight.w800,
              ),
            ),
      ),
    );
  }
}
