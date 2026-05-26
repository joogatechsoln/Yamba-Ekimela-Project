import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_services.dart';
import 'app_images.dart';
import 'app_language.dart';
import 'home_page.dart';

class AuthenticationPage extends StatefulWidget {
  const AuthenticationPage({super.key});

  @override
  State<AuthenticationPage> createState() => _AuthenticationPageState();
}

class _AuthenticationPageState extends State<AuthenticationPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _districtController = TextEditingController();
  final TextEditingController _availableDrugsController = TextEditingController();

  bool _isSignUp = false;
  bool _isLoading = false;
  bool _hidePassword = true;
  String _selectedLanguageCode = 'en';
  String _selectedRole = AppServices.farmerRole;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selectedLanguageCode = AppLanguageScope.of(context).currentLanguageCode;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _districtController.dispose();
    _availableDrugsController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    final language = AppLanguageScope.of(context);

    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      _showSnackBar(language.text('Enter email and password.'));
      return;
    }

    if (_isSignUp && _fullNameController.text.trim().isEmpty) {
      _showSnackBar(language.text('Enter your full name.'));
      return;
    }

    if (_isSignUp &&
        _selectedRole == AppServices.dealerRole &&
        _phoneController.text.trim().isEmpty) {
      _showSnackBar(language.text('Enter the dealer phone number.'));
      return;
    }

    if (!AppServices.supabaseReady) {
      _showSnackBar(
        'Supabase is not configured. Add keys in lib/supabase_config.dart or via --dart-define.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      final fullName = _fullNameController.text.trim();
      final phoneNumber = _phoneController.text.trim();
      final district = _districtController.text.trim();
      final availableDrugs = _availableDrugsController.text
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      User? user;

      if (_isSignUp) {
          final result = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': fullName,
            'preferred_language': _selectedLanguageCode,
            'role': _selectedRole,
            'phone_number': phoneNumber,
            'district': district,
          },
        );
        user = result.user;

        if (user != null) {
          await supabase.from('profiles').upsert({
            'id': user.id,
            'full_name': fullName,
            'email': email,
            'role': _selectedRole,
            'phone_number': phoneNumber,
            'district': district,
            'available_drugs': availableDrugs,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      } else {
        final result = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
        user = result.user;
      }

      user ??= supabase.auth.currentUser;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('authenticated', true);
      await prefs.setString('user_email', user?.email ?? email);
      String resolvedRole =
          user?.userMetadata?['role']?.toString() ?? _selectedRole;
      if (AppServices.supabaseReady && user != null) {
        try {
          final profile = await supabase
              .from('profiles')
              .select('role')
              .eq('id', user.id)
              .maybeSingle();
          resolvedRole = profile?['role']?.toString() ?? resolvedRole;
        } catch (_) {}
      }
      final preferredLanguage =
          user?.userMetadata?['preferred_language']?.toString() ??
              _selectedLanguageCode;
      await prefs.setString('app_language', preferredLanguage);
      await prefs.setString(AppServices.userRoleKey, resolvedRole);
      await language.setLanguage(preferredLanguage);

      final resolvedName =
          user?.userMetadata?['full_name'] ?? (_isSignUp ? fullName : '');
      if (resolvedName.isNotEmpty) {
        await prefs.setString('user_name', resolvedName);
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomePage()),
      );
    } on AuthException catch (e) {
      _showSnackBar(e.message);
    } catch (_) {
      _showSnackBar(language.text('Authentication failed. Please try again.'));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF2E7D32)),
      filled: true,
      fillColor: const Color(0xFFF7FBF8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageScope.of(context);

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2B7A38), Color(0xFF1E5D2A)],
              ),
            ),
          ),
          Positioned(
            top: -40,
            right: -20,
            child: Opacity(
              opacity: 0.22,
              child: Image.asset(
                AppImages.authBackground,
                width: 180,
                height: 180,
                fit: BoxFit.cover,
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          AppImages.authHero,
                          width: 62,
                          height: 62,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        language.text(
                          _isSignUp ? 'Create Account' : 'Welcome Back',
                        ),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        language.text(
                          _isSignUp
                              ? 'Join Yamba Ekimera and start smart farming'
                              : 'Sign in to continue',
                        ),
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      if (_isSignUp) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _fullNameController,
                          decoration: _fieldDecoration(
                            language.text('Full Name'),
                            Icons.person_rounded,
                          ),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedRole,
                          decoration: _fieldDecoration(
                            language.text('I am joining as'),
                            Icons.badge_rounded,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: AppServices.farmerRole,
                              child: Text(language.text('Farmer')),
                            ),
                            DropdownMenuItem(
                              value: AppServices.dealerRole,
                              child: Text(language.text('Agro medic')),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _selectedRole = value);
                          },
                        ),
                        if (_selectedRole == AppServices.dealerRole) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: _fieldDecoration(
                              language.text('Phone Number'),
                              Icons.phone_rounded,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _districtController,
                            decoration: _fieldDecoration(
                              language.text('District'),
                              Icons.location_on_outlined,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _availableDrugsController,
                            decoration: _fieldDecoration(
                              language.text('Available Drugs (comma separated)'),
                              Icons.medical_services_outlined,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedLanguageCode,
                          decoration: _fieldDecoration(
                            language.text('Preferred language'),
                            Icons.language_rounded,
                          ),
                          items: AppLanguageController.supportedLanguages
                              .map(
                                (option) => DropdownMenuItem(
                                  value: option.code,
                                  child: Text(language.text(option.label)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _selectedLanguageCode = value);
                          },
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _fieldDecoration(
                          language.text('Email'),
                          Icons.email_rounded,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _passwordController,
                        obscureText: _hidePassword,
                        decoration: _fieldDecoration(
                          language.text('Password'),
                          Icons.lock_rounded,
                        ).copyWith(
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _hidePassword = !_hidePassword),
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleAuth,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF62B76C),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  language.text(
                                    _isSignUp ? 'Create Account' : 'Sign In',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => setState(() => _isSignUp = !_isSignUp),
                        child: Text(
                          language.text(
                            _isSignUp
                                ? 'Already have an account? Sign in'
                                : 'No account? Create one',
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
