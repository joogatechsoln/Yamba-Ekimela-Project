import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_services.dart';
import 'app_images.dart';
import 'app_language.dart';
import 'weather_config.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  String weatherSummary = 'Loading weather...';
  String plantingRec = 'Loading recommendations...';
  String currentTemp = '--';
  String weatherCondition = 'loading';
  String locationName = 'Your Location';
  bool _isLoading = true;

  String _userName = 'Farmer';
  String _avatarUrl = '';
  String _userRole = AppServices.farmerRole;

  double _latitude = 0.3476;
  double _longitude = 32.5825;
  final String _apiKey = openWeatherApiKey;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadUserProfile();
    await _loadLocation();
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    String name = prefs.getString('user_name') ?? 'Farmer';
    String avatar = prefs.getString('user_avatar_url') ?? '';
    String avatarPath = prefs.getString('user_avatar_path') ?? '';
    String role =
        prefs.getString(AppServices.userRoleKey) ?? AppServices.farmerRole;

    if (AppServices.supabaseReady) {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null) {
        try {
          final profile = await supabase
              .from('profiles')
              .select('full_name,avatar_url,role')
              .eq('id', user.id)
              .maybeSingle();

          name = profile?['full_name'] ??
              user.userMetadata?['full_name'] ??
              user.email?.split('@').first ??
              name;
          avatar = profile?['avatar_url'] ??
              user.userMetadata?['avatar_url'] ??
              avatar;
          role = profile?['role']?.toString() ??
              user.userMetadata?['role']?.toString() ??
              role;
          avatarPath = user.userMetadata?['avatar_path'] ?? avatarPath;

          await prefs.setString('user_name', name);
          if (avatar.isNotEmpty) {
            await prefs.setString('user_avatar_url', avatar);
          }
          if (avatarPath.isNotEmpty) {
            await prefs.setString('user_avatar_path', avatarPath);
          }
          await prefs.setString(AppServices.userRoleKey, role);
        } catch (_) {
          name = user.userMetadata?['full_name'] ?? name;
          avatar = user.userMetadata?['avatar_url'] ?? avatar;
          avatarPath = user.userMetadata?['avatar_path'] ?? avatarPath;
          role = user.userMetadata?['role']?.toString() ?? role;
        }
      }
    }

    final extractedPath = _extractStoragePathFromUrl(avatar);
    if (extractedPath.isNotEmpty) {
      avatarPath = extractedPath;
    }
    avatar = await _resolveAvatarDisplayUrl(avatar, avatarPath);

    if (!mounted) return;
    setState(() {
      _userName = name.trim().isEmpty ? 'Farmer' : name;
      _avatarUrl = avatar;
      _userRole = role;
    });
  }

  Future<void> _loadLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedLat = prefs.getDouble('cached_latitude');
    final cachedLon = prefs.getDouble('cached_longitude');

    if (cachedLat != null && cachedLon != null) {
      _latitude = cachedLat;
      _longitude = cachedLon;
    }

    await _loadWeather();
  }

  Future<void> _loadWeather() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastFetchTime = prefs.getInt('home_last_fetch_time');
      final currentTime = DateTime.now().millisecondsSinceEpoch;

      if (lastFetchTime != null &&
          (currentTime - lastFetchTime) < 30 * 60 * 1000) {
        final cached = prefs.getString('home_cached_weather');
        if (cached != null) {
          setState(() {
            weatherSummary = cached;
            plantingRec = prefs.getString('home_cached_rec') ?? plantingRec;
            currentTemp = prefs.getString('home_cached_temp') ?? currentTemp;
            weatherCondition =
                prefs.getString('home_cached_condition') ?? weatherCondition;
            locationName =
                prefs.getString('home_cached_location') ?? locationName;
            _isLoading = false;
          });
          return;
        }
      }

      final weatherUrl = Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather?'
        'lat=$_latitude&lon=$_longitude&units=metric&appid=$_apiKey',
      );

      final weatherResponse = await http.get(weatherUrl);
      if (weatherResponse.statusCode != 200) {
        throw Exception('Failed to load weather');
      }

      final data = json.decode(weatherResponse.body);
      final temp = data['main']['temp'].toDouble();
      final condition = data['weather'][0]['description'] as String;
      final humidity = data['main']['humidity'].toDouble();
      final location = data['name'] as String;
      final summary = '${temp.toStringAsFixed(1)}C, ${_capitalize(condition)}';
      final recommendations =
          _generateRecommendations(temp, humidity, condition);

      await prefs.setString('home_cached_weather', summary);
      await prefs.setString('home_cached_rec', recommendations);
      await prefs.setString('home_cached_temp', temp.toStringAsFixed(0));
      await prefs.setString('home_cached_condition', condition);
      await prefs.setString('home_cached_location', location);
      await prefs.setInt('home_last_fetch_time', currentTime);

      if (!mounted) return;
      setState(() {
        weatherSummary = summary;
        plantingRec = recommendations;
        currentTemp = temp.toStringAsFixed(0);
        weatherCondition = condition;
        locationName = location;
        _isLoading = false;
      });
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('home_cached_weather');

      if (!mounted) return;
      setState(() {
        if (cached != null) {
          weatherSummary = 'Offline - $cached';
          plantingRec = prefs.getString('home_cached_rec') ?? plantingRec;
          currentTemp = prefs.getString('home_cached_temp') ?? '--';
          weatherCondition =
              prefs.getString('home_cached_condition') ?? 'offline';
          locationName =
              prefs.getString('home_cached_location') ?? locationName;
        } else {
          weatherSummary = 'Offline mode - Unable to fetch weather';
          plantingRec =
              'Connect to the internet for personalized recommendations';
        }
        _isLoading = false;
      });
    }
  }

  String _capitalize(String text) {
    return text
        .split(' ')
        .map((word) =>
            word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  String _generateRecommendations(
    double temp,
    double humidity,
    String condition,
  ) {
    final recommendations = <String>[];

    if (temp >= 20 && temp <= 30) {
      recommendations.add('Great day for tomatoes, peppers and beans.');
    } else if (temp < 20) {
      recommendations.add('Cool conditions suit cabbage and carrots.');
    } else {
      recommendations.add('Heat-tolerant crops like okra are safer now.');
    }

    if (condition.contains('rain') || humidity > 80) {
      recommendations.add('High moisture: watch for fungal disease early.');
    } else if (humidity < 50) {
      recommendations.add('Irrigate young plants more consistently.');
    }

    return recommendations.join('\n');
  }

  String _localizedMultiline(
    AppLanguageController language,
    String text,
  ) {
    return text
        .split('\n')
        .map((line) => language.text(line))
        .join('\n');
  }

  Color _getBackgroundTint() {
    if (weatherCondition.contains('clear') ||
        weatherCondition.contains('sun')) {
      return const Color(0xFF6FBF73);
    } else if (weatherCondition.contains('cloud')) {
      return const Color(0xFF7A9E9F);
    } else if (weatherCondition.contains('rain')) {
      return const Color(0xFF5F93C2);
    }
    return const Color(0xFF5D9B6C);
  }

  IconData _getWeatherIconData() {
    if (weatherCondition.contains('clear') ||
        weatherCondition.contains('sun')) {
      return Icons.wb_sunny_rounded;
    } else if (weatherCondition.contains('cloud')) {
      return Icons.cloud_rounded;
    } else if (weatherCondition.contains('rain')) {
      return Icons.umbrella_rounded;
    } else if (weatherCondition.contains('storm')) {
      return Icons.thunderstorm_rounded;
    }
    return Icons.wb_cloudy_rounded;
  }

  Widget _buildAvatar() {
    if (_avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: Colors.white,
        backgroundImage: NetworkImage(_avatarUrl),
        onBackgroundImageError: (_, __) {},
      );
    }

    return const CircleAvatar(
      radius: 20,
      backgroundColor: Colors.white,
      child: Icon(Icons.person, color: Color(0xFF2E7D32)),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
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
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final tint = _getBackgroundTint();
    final language = AppLanguageScope.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              tint.withValues(alpha: 0.9),
              const Color(0xFFF4F7F4),
            ],
            stops: const [0.35, 1],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _initialize,
            color: const Color(0xFF2E7D32),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                children: [
                  Row(
                    children: [
                      _buildAvatar(),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${language.text('Hi')}, $_userName',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              locationName,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                language.text(
                                  _userRole == AppServices.dealerRole
                                      ? 'Agro Medic'
                                      : 'Farmer',
                                ),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _initialize,
                        icon: const Icon(Icons.refresh_rounded,
                            color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.17),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: _isLoading
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                  color: Colors.white),
                            ),
                          )
                        : Row(
                            children: [
                              Text(
                                '$currentTemp°',
                                style: const TextStyle(
                                  fontSize: 54,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  language.text(_capitalize(weatherCondition)),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Icon(
                                _getWeatherIconData(),
                                color: Colors.white,
                                size: 40,
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          language.text('Farm insight'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _localizedMultiline(language, plantingRec),
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: screenHeight * 0.21,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF31B35B), Color(0xFF1D8F45)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -10,
                          bottom: -10,
                          child: Opacity(
                            opacity: 0.25,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Image.asset(
                                AppImages.homeOffer,
                                width: 150,
                                height: 140,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                language.text('Check out'),
                                style: const TextStyle(color: Colors.white70),
                              ),
                              Text(
                                language.text('Special Crop Care Tips'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 22,
                                ),
                              ),
                              const Spacer(),
                              ElevatedButton.icon(
                                onPressed: () =>
                                    Navigator.pushNamed(context, '/weather'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF1D8F45),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                icon: const Icon(Icons.arrow_forward_rounded),
                                label: Text(language.text('View forecast')),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.28,
                    children: [
                      _buildActionCard(
                        title: language.text(
                          _userRole == AppServices.dealerRole
                              ? 'Dealer Inbox'
                              : 'Scan Crop',
                        ),
                        icon: _userRole == AppServices.dealerRole
                            ? Icons.inbox_rounded
                            : Icons.qr_code_scanner_rounded,
                        color: const Color(0xFF56B879),
                        onTap: () => Navigator.pushNamed(
                          context,
                          _userRole == AppServices.dealerRole
                              ? '/dealer-inbox'
                              : '/scan',
                        ),
                      ),
                      _buildActionCard(
                        title: language.text('Weather'),
                        icon: Icons.cloud_rounded,
                        color: const Color(0xFF7CB6E8),
                        onTap: () => Navigator.pushNamed(context, '/weather'),
                      ),
                      _buildActionCard(
                        title: language.text(
                          _userRole == AppServices.dealerRole
                              ? 'Profile'
                              : 'Agro Medics',
                        ),
                        icon: _userRole == AppServices.dealerRole
                            ? Icons.person_rounded
                            : Icons.storefront_rounded,
                        color: const Color(0xFF9ACF73),
                        onTap: () async {
                          await Navigator.pushNamed(
                            context,
                            _userRole == AppServices.dealerRole
                                ? '/profile'
                                : '/dealers',
                          );
                          await _initialize();
                        },
                      ),
                      _buildActionCard(
                        title: language.text(
                          _userRole == AppServices.dealerRole
                              ? 'Messages'
                              : 'Profile',
                        ),
                        icon: _userRole == AppServices.dealerRole
                            ? Icons.chat_bubble_outline_rounded
                            : Icons.person_rounded,
                        color: const Color(0xFF8FC2A6),
                        onTap: () async {
                          if (_userRole == AppServices.dealerRole) {
                            Navigator.pushNamed(context, '/dealer-inbox');
                            return;
                          }
                          await Navigator.pushNamed(context, '/profile');
                          await _initialize();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF215033),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
