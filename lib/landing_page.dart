import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_services.dart';
import 'app_images.dart';
import 'app_language.dart';
import 'authentication_page.dart';
import 'home_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade =
        CurvedAnimation(parent: _animationController, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _navigateToNextPage() async {
    setState(() => _isLoading = true);

    bool isAuthenticated;
    if (AppServices.supabaseReady) {
      isAuthenticated = Supabase.instance.client.auth.currentSession != null;
    } else {
      final prefs = await SharedPreferences.getInstance();
      isAuthenticated = prefs.getBool('authenticated') ?? false;
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => isAuthenticated ? HomePage() : AuthenticationPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageScope.of(context);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF234D2C), Color(0xFF112E18)],
              ),
            ),
          ),
          Positioned(
            top: -40,
            right: -50,
            child: Opacity(
              opacity: 0.2,
              child: Image.asset(
                AppImages.landingBgTop,
                width: 220,
                height: 220,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            left: -60,
            bottom: -40,
            child: Opacity(
              opacity: 0.2,
              child: Image.asset(
                AppImages.landingBgBottom,
                width: 240,
                height: 240,
                fit: BoxFit.cover,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          AppImages.landingHero,
                          width: 84,
                          height: 84,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        language.text('Welcome to\nYamba Ekimera'),
                        style: const TextStyle(
                          fontSize: 42,
                          height: 1.02,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        language.text(
                          'AI-powered tools for smarter farming in Uganda',
                        ),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 17,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _navigateToNextPage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8CE45E),
                            foregroundColor: const Color(0xFF183A1E),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  language.text('Get Started'),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
