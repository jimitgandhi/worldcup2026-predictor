import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      await _auth.signInWithGoogle();
    } catch (e) {
      setState(() { _error = 'Sign-in failed. Please try again.'; });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.6),
                radius: 1.2,
                colors: [Color(0x382563EB), AppColors.bg],
              ),
            ),
          ),
          // Background watermark logo
          Positioned(
            top: 80,
            left: 0, right: 0,
            child: Center(
              child: Image.asset(
                'assets/images/fifa_logo26.webp',
                width: 220,
                opacity: const AlwaysStoppedAnimation(0.07),
              ),
            ),
          ),
          // Main content
          SafeArea(
            child: Column(
              children: [
                // Top: logo
                Expanded(
                  child: Center(
                    child: Image.asset(
                      'assets/images/fifa_logo26.webp',
                      width: 130,
                    ).animate(onPlay: (c) => c.repeat(reverse: true))
                      .moveY(begin: 0, end: -12, duration: 3.seconds, curve: Curves.easeInOut),
                  ),
                ),
                // Bottom: content
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Eyebrow
                      const Text('FIFA WORLD CUP 2026™',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          letterSpacing: 3, color: AppColors.gold,
                        )),
                      const SizedBox(height: 10),
                      // Title
                      const Text('Predict.\nCompete. Win.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32, fontWeight: FontWeight.w900,
                          letterSpacing: -1, height: 1.1, color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Enter your score predictions before kick-off.\nEarn points. Climb the global leaderboard.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14, color: AppColors.text2, height: 1.65,
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Scoring rules
                      _ScoringPill(
                        color: AppColors.green,
                        label: 'Exact score',
                        pts: '+50 pts',
                      ),
                      const SizedBox(height: 8),
                      _ScoringPill(
                        color: AppColors.gold,
                        label: 'Almost correct (result + 1 score)',
                        pts: '+30 pts',
                      ),
                      const SizedBox(height: 8),
                      _ScoringPill(
                        color: AppColors.gold,
                        label: 'Correct result (W/D/L)',
                        pts: '+20 pts',
                      ),
                      const SizedBox(height: 8),
                      _ScoringPill(
                        color: AppColors.orange,
                        label: "One team's score right",
                        pts: '+10 pts',
                      ),
                      const SizedBox(height: 28),
                      // Google button
                      if (_error != null) ...[
                        Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.red, fontSize: 13)),
                        const SizedBox(height: 12),
                      ],
                      _GoogleButton(loading: _loading, onTap: _signIn),
                      const SizedBox(height: 16),
                      const Text(
                        'By continuing you agree to our Terms & Privacy Policy',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: AppColors.text3, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoringPill extends StatelessWidget {
  final Color color;
  final String label;
  final String pts;
  const _ScoringPill({required this.color, required this.label, required this.pts});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text2)),
          const Spacer(),
          Text(pts,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.text)),
        ],
      ),
    );
  }
}

class _GoogleGIcon extends StatelessWidget {
  const _GoogleGIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20, height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFDDDDDD), width: 1),
      ),
      child: const Center(
        child: Text('G',
          style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700,
            color: Color(0xFF4285F4),
          )),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _GoogleButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 4))],
        ),
        child: loading
          ? const Center(child: SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF333333))))
          : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.network(
                'https://www.google.com/images/branding/googleg/1x/googleg_standard_color_128dp.png',
                width: 20, height: 20,
                errorBuilder: (_, __, ___) => const _GoogleGIcon(),
              ),
              const SizedBox(width: 12),
              const Text('Continue with Google',
                style: TextStyle(
                  color: Color(0xFF1a1a1a),
                  fontSize: 15, fontWeight: FontWeight.w700,
                )),
            ],
          ),
      ),
    );
  }
}
