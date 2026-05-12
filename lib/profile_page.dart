import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'app_services.dart';
import 'app_images.dart';
import 'app_language.dart';
import 'landing_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  List<String> _history = [];
  String _userName = 'Farmer';
  String _userEmail = '';
  String _userPhone = '';
  String _joinDate = '';
  int _totalScans = 0;
  String _selectedLanguageCode = 'en';
  String _avatarUrl = '';
  String _avatarPath = '';
  bool _isUploadingAvatar = false;

  final ImagePicker _imagePicker = ImagePicker();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadProfileData();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    _animationController.forward();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('diagnosis_history') ?? [];
    String userName = prefs.getString('user_name') ?? 'Farmer';
    String userPhone = prefs.getString('user_phone') ?? '';
    String userEmail = prefs.getString('user_email') ?? '';
    String avatarUrl = prefs.getString('user_avatar_url') ?? '';
    String avatarPath = prefs.getString('user_avatar_path') ?? '';
    String joinDate = prefs.getString('join_date') ??
        DateFormat('MMMM yyyy').format(DateTime.now());

    await prefs.setString('join_date', joinDate);
    _selectedLanguageCode = prefs.getString('app_language') ?? 'en';

    if (AppServices.supabaseReady) {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user != null) {
        try {
          final profile = await supabase
              .from('profiles')
              .select('full_name,phone_number,email,created_at,avatar_url')
              .eq('id', user.id)
              .maybeSingle();

          userEmail = user.email ?? profile?['email'] ?? userEmail;
          userName = profile?['full_name'] ??
              user.userMetadata?['full_name'] ??
              userName;
          userPhone = profile?['phone_number'] ?? userPhone;
          avatarUrl = profile?['avatar_url'] ??
              user.userMetadata?['avatar_url'] ??
              avatarUrl;
          avatarPath = user.userMetadata?['avatar_path'] ?? avatarPath;

          final createdAt = profile?['created_at'];
          if (createdAt is String && createdAt.isNotEmpty) {
            joinDate =
                DateFormat('MMMM yyyy').format(DateTime.parse(createdAt));
          }

          await prefs.setString('user_name', userName);
          await prefs.setString('user_phone', userPhone);
          await prefs.setString('user_email', userEmail);
          if (avatarUrl.isNotEmpty) {
            await prefs.setString('user_avatar_url', avatarUrl);
          }
          if (avatarPath.isNotEmpty) {
            await prefs.setString('user_avatar_path', avatarPath);
          }
        } catch (_) {
          userName = user.userMetadata?['full_name'] ?? userName;
          userEmail = user.email ?? userEmail;
          avatarUrl = user.userMetadata?['avatar_url'] ?? avatarUrl;
          avatarPath = user.userMetadata?['avatar_path'] ?? avatarPath;
        }
      }
    }

    final extractedPath = _extractStoragePathFromUrl(avatarUrl);
    if (extractedPath.isNotEmpty) {
      avatarPath = extractedPath;
    }
    avatarUrl = await _resolveAvatarDisplayUrl(avatarUrl, avatarPath);

    if (!mounted) return;
    setState(() {
      _history = history;
      _totalScans = history.length;
      _userName = userName;
      _userPhone = userPhone;
      _userEmail = userEmail;
      _joinDate = joinDate;
      _avatarUrl = avatarUrl;
      _avatarPath = avatarPath;
    });
  }

  Future<void> _pickAndUploadAvatar() async {
    final language = AppLanguageScope.of(context);
    if (!AppServices.supabaseReady) {
      _showSnackBar(
        language.text(
          'Profile image upload needs Supabase storage to be configured.',
        ),
      );
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showSnackBar(language.text('Sign in again to update your profile image.'));
      return;
    }

    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (picked == null) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final file = File(picked.path);
      final extension = picked.path.split('.').last.toLowerCase();
      final safeExtension = extension.isEmpty ? 'jpg' : extension;
      final avatarPath =
          '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$safeExtension';

      await Supabase.instance.client.storage
          .from(AppServices.profileImageBucket)
          .upload(
            avatarPath,
            file,
            fileOptions: const FileOptions(upsert: true),
          );

      final signedUrl = await Supabase.instance.client.storage
          .from(AppServices.profileImageBucket)
          .createSignedUrl(avatarPath, 60 * 60 * 24 * 7);

      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        'full_name': _userName,
        'email': user.email,
        'phone_number': _userPhone,
        'avatar_url': signedUrl,
        'updated_at': DateTime.now().toIso8601String(),
      });

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': _userName,
            'avatar_url': signedUrl,
            'avatar_path': avatarPath,
          },
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_avatar_url', signedUrl);
      await prefs.setString('user_avatar_path', avatarPath);

      final resolvedUrl = await _resolveAvatarDisplayUrl(signedUrl, avatarPath);
      if (!mounted) return;
      setState(() {
        _avatarUrl = resolvedUrl;
        _avatarPath = avatarPath;
      });
      _showSnackBar(language.text('Profile image updated.'));
    } catch (e) {
      _showSnackBar('${language.text('Failed to upload image.')}: $e');
    } finally {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  Future<void> _showEditProfileDialog() async {
    final language = AppLanguageScope.of(context);
    final nameController = TextEditingController(text: _userName);
    final phoneController = TextEditingController(text: _userPhone);

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(language.text('Edit Profile')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: language.text('Name'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: language.text('Phone Number'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(language.text('Cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('user_name', nameController.text.trim());
                await prefs.setString(
                    'user_phone', phoneController.text.trim());

                if (AppServices.supabaseReady) {
                  final supabase = Supabase.instance.client;
                  final user = supabase.auth.currentUser;
                  if (user != null) {
                    await supabase.from('profiles').upsert({
                      'id': user.id,
                      'full_name': nameController.text.trim(),
                      'phone_number': phoneController.text.trim(),
                      'email': user.email,
                      'avatar_url': _avatarUrl,
                      'updated_at': DateTime.now().toIso8601String(),
                    });
                    await supabase.auth.updateUser(
                      UserAttributes(data: {
                        'full_name': nameController.text.trim(),
                        'avatar_url': _avatarUrl,
                        'avatar_path': _avatarPath,
                      }),
                    );
                  }
                }

                if (!mounted) return;
                setState(() {
                  _userName = nameController.text.trim();
                  _userPhone = phoneController.text.trim();
                });
                if (!context.mounted) return;
                Navigator.pop(context);
                _showSnackBar(language.text('Profile updated'));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
              ),
              child: Text(language.text('Save')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateLanguage(String languageCode) async {
    final language = AppLanguageScope.of(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', languageCode);
    await language.setLanguage(languageCode);

    if (AppServices.supabaseReady) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(data: {'preferred_language': languageCode}),
        );
      }
    }

    if (!mounted) return;
    setState(() => _selectedLanguageCode = languageCode);
  }

  Future<void> _clearHistory() async {
    final language = AppLanguageScope.of(context);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(language.text('Clear history?')),
          content: Text(
            language.text('This will remove all diagnosis history.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(language.text('Cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('diagnosis_history');
                if (!mounted) return;
                setState(() {
                  _history = [];
                  _totalScans = 0;
                });
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: Text(language.text('Clear')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() async {
    try {
      if (AppServices.supabaseReady) {
        await Supabase.instance.client.auth.signOut();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('authenticated', false);

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => LandingPage()),
        (route) => false,
      );
    } catch (_) {
      _showSnackBar(
        AppLanguageScope.of(context).text('Logout failed. Please try again.'),
      );
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<String> _resolveAvatarDisplayUrl(
    String avatarUrl,
    String avatarPath,
  ) async {
    if (!AppServices.supabaseReady) return avatarUrl;
    if (avatarUrl.contains('/storage/v1/object/sign/')) {
      return '$avatarUrl&t=${DateTime.now().millisecondsSinceEpoch}';
    }
    if (avatarPath.isNotEmpty) {
      try {
        final signed = await Supabase.instance.client.storage
            .from(AppServices.profileImageBucket)
            .createSignedUrl(avatarPath, 60 * 60 * 24 * 7);
        return '$signed?t=${DateTime.now().millisecondsSinceEpoch}';
      } catch (_) {}
    }
    return avatarUrl;
  }

  String _extractStoragePathFromUrl(String avatarUrl) {
    if (avatarUrl.isEmpty) return '';
    final publicSegment =
        '/storage/v1/object/public/${AppServices.profileImageBucket}/';
    final authenticatedSegment =
        '/storage/v1/object/authenticated/${AppServices.profileImageBucket}/';
    final signedSegment =
        '/storage/v1/object/sign/${AppServices.profileImageBucket}/';
    if (avatarUrl.contains(publicSegment)) {
      return avatarUrl.split(publicSegment).last.split('?').first;
    }
    if (avatarUrl.contains(authenticatedSegment)) {
      return avatarUrl.split(authenticatedSegment).last.split('?').first;
    }
    if (avatarUrl.contains(signedSegment)) {
      return avatarUrl.split(signedSegment).last.split('?').first;
    }
    return '';
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageScope.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF62B76C), Color(0xFFF6FAF6)],
            stops: [0.25, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        language.text('My Profile'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout, color: Colors.white),
                    ),
                  ],
                ),
              ),
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.95, end: 1.05),
                        duration: const Duration(milliseconds: 1700),
                        curve: Curves.easeInOut,
                        builder: (context, value, child) {
                          return Transform.scale(scale: value, child: child);
                        },
                        onEnd: () {
                          if (mounted) {
                            setState(() {});
                          }
                        },
                        child: Stack(
                          children: [
                            Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(60),
                                border: Border.all(color: Colors.white, width: 3),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _avatarUrl.isNotEmpty
                                  ? Image.network(
                                      _avatarUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Image.asset(
                                        AppImages.profileHero,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : Image.asset(
                                      AppImages.profileHero,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const ColoredBox(
                                        color: Colors.white,
                                        child: Icon(
                                          Icons.animation_rounded,
                                          size: 56,
                                          color: Color(0xFF2E7D32),
                                        ),
                                      ),
                                    ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: InkWell(
                                onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(19),
                                    border: Border.all(
                                      color: const Color(0xFF2E7D32),
                                      width: 2,
                                    ),
                                  ),
                                  child: _isUploadingAvatar
                                      ? const Padding(
                                          padding: EdgeInsets.all(8),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF2E7D32),
                                          ),
                                        )
                                      : const Icon(
                                          Icons.camera_alt_rounded,
                                          size: 18,
                                          color: Color(0xFF2E7D32),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _userName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 24,
                        ),
                      ),
                      if (_userEmail.isNotEmpty)
                        Text(
                          _userEmail,
                          style:
                              TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        '${language.text('Member since')} $_joinDate',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _showEditProfileDialog,
                        icon: const Icon(Icons.edit_rounded),
                        label: Text(language.text('Edit details')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side:
                              BorderSide(
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedLanguageCode,
                            isExpanded: true,
                            dropdownColor: const Color(0xFF2E7D32),
                            iconEnabledColor: Colors.white,
                            style: const TextStyle(color: Colors.white),
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
                              _updateLanguage(value);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        language.text('Total Scans'),
                        _totalScans.toString(),
                        Icons.qr_code_scanner_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildStatCard(
                        language.text('This Month'),
                        _getMonthlyScans().toString(),
                        Icons.calendar_month_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              language.text('Diagnosis History'),
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                            if (_history.isNotEmpty)
                              TextButton.icon(
                                onPressed: _clearHistory,
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: Text(language.text('Clear')),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red.shade400,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _history.isEmpty
                            ? Center(
                                child: Text(
                                  language.text('No diagnosis history yet'),
                                  style: TextStyle(color: Colors.grey.shade500),
                                ),
                              )
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: _history.length,
                                itemBuilder: (context, index) {
                                  return _buildHistoryItem(
                                    _history[_history.length - 1 - index],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF2E7D32)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 24,
              color: Color(0xFF1F5D28),
            ),
          ),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(String item) {
    final language = AppLanguageScope.of(context);
    final parts = item.split(' - ');
    final date = parts.isNotEmpty ? parts[0] : language.text('Unknown date');
    final diagnosis = parts.length > 1 ? parts[1] : item;
    final crop = parts.length > 2 ? parts[2] : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading:
            const Icon(Icons.local_florist_rounded, color: Color(0xFF2E7D32)),
        title: Text(
          language.text(diagnosis),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(crop.isEmpty ? date : '$crop • $date'),
      ),
    );
  }

  int _getMonthlyScans() {
    final currentMonth = DateFormat('MM/yyyy').format(DateTime.now());
    return _history.where((item) => item.contains(currentMonth)).length;
  }
}
