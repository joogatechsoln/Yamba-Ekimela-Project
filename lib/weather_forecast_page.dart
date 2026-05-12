import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_language.dart';
import 'weather_config.dart';

class WeatherForecastPage extends StatefulWidget {
  const WeatherForecastPage({super.key});

  @override
  State<WeatherForecastPage> createState() => _WeatherForecastPageState();
}

class _WeatherForecastPageState extends State<WeatherForecastPage> {
  String _forecast = 'Loading forecast...';
  String _cropSuggestions = 'Loading crop suggestions...';
  String _locationName = 'Your Location';
  String _temp = '--';
  String _condition = 'Sunny Day';
  int _humidity = 0;
  bool _isLoading = true;
  String? _error;

  double _latitude = 0.3476;
  double _longitude = 32.5825;
  final String _apiKey = openWeatherApiKey;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final hasRequestedPermission = prefs.getBool('has_requested_location');

    if (hasRequestedPermission != true) {
      await _requestLocationPermission();
      await prefs.setBool('has_requested_location', true);
    } else {
      final hasPermission = await _checkLocationPermission();
      if (hasPermission) {
        await _getCurrentLocation();
      } else {
        await _loadCachedLocation();
      }
    }

    await _loadForecast();
  }

  Future<bool> _checkLocationPermission() async {
    final status = await Permission.location.status;
    return status.isGranted;
  }

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();

    if (status.isGranted) {
      await _getCurrentLocation();
    } else if (status.isDenied) {
      _showPermissionDialog(
        'Location Permission Needed',
        'Enable location to get weather specific to your farm area.',
      );
      await _loadCachedLocation();
    } else if (status.isPermanentlyDenied) {
      _showPermissionDialog(
        'Location Permission Required',
        'Location permission is permanently denied. Enable it in app settings.',
        showSettings: true,
      );
      await _loadCachedLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackBar('Location service is off. Using cached location.');
        await _loadCachedLocation();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );

      _latitude = position.latitude;
      _longitude = position.longitude;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('cached_latitude', _latitude);
      await prefs.setDouble('cached_longitude', _longitude);
      await _getLocationName();
    } catch (_) {
      _showSnackBar('Could not get current location. Using cached location.');
      await _loadCachedLocation();
    }
  }

  Future<void> _loadCachedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedLat = prefs.getDouble('cached_latitude');
    final cachedLon = prefs.getDouble('cached_longitude');

    if (cachedLat != null && cachedLon != null) {
      _latitude = cachedLat;
      _longitude = cachedLon;
      await _getLocationName();
    } else {
      _locationName = 'Kampala (Default)';
    }
  }

  Future<void> _getLocationName() async {
    try {
      final url = Uri.parse(
        'https://api.openweathermap.org/geo/1.0/reverse?lat=$_latitude&lon=$_longitude&limit=1&appid=$_apiKey',
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data.isNotEmpty) {
          _locationName = data[0]['name'] ?? 'Current Location';
        }
      }
    } catch (_) {
      _locationName = 'Current Location';
    }
  }

  Future<void> _loadForecast() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastFetchTime = prefs.getInt('last_fetch_time');
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      final cachedLat = prefs.getDouble('last_fetch_lat');
      final cachedLon = prefs.getDouble('last_fetch_lon');
      final locationChanged = cachedLat == null ||
          cachedLon == null ||
          ((_latitude - cachedLat).abs() > 0.1 ||
              (_longitude - cachedLon).abs() > 0.1);

      if (!locationChanged &&
          lastFetchTime != null &&
          (currentTime - lastFetchTime) < 3 * 60 * 60 * 1000) {
        final cachedForecast = prefs.getString('cached_forecast');
        final cachedSuggestions = prefs.getString('cached_suggestions');
        final cachedTemp = prefs.getString('weather_temp');
        final cachedCondition = prefs.getString('weather_condition');
        final cachedHumidity = prefs.getInt('weather_humidity');

        if (cachedForecast != null && cachedSuggestions != null) {
          setState(() {
            _forecast = cachedForecast;
            _cropSuggestions = cachedSuggestions;
            _temp = cachedTemp ?? _temp;
            _condition = cachedCondition ?? _condition;
            _humidity = cachedHumidity ?? _humidity;
            _isLoading = false;
          });
          return;
        }
      }

      final url = Uri.parse(
        'https://api.openweathermap.org/data/3.0/onecall?lat=$_latitude&lon=$_longitude&exclude=minutely,alerts&units=metric&appid=$_apiKey',
      );
      final response = await http.get(url);

      if (response.statusCode != 200) {
        if (response.statusCode == 401) {
          throw Exception('Invalid weather API key.');
        }
        throw Exception('Weather service error (${response.statusCode}).');
      }

      final data = json.decode(response.body);
      final forecastText = _processForecastData(data);
      final suggestions = _generateCropSuggestions(data);
      final current = data['current'];

      final currentTemp = (current['temp'] as num).toDouble();
      final currentCondition = current['weather'][0]['description'] as String;
      final currentHumidity = (current['humidity'] as num).toInt();

      await prefs.setString('cached_forecast', forecastText);
      await prefs.setString('cached_suggestions', suggestions);
      await prefs.setString('weather_temp', currentTemp.toStringAsFixed(0));
      await prefs.setString('weather_condition', _capitalize(currentCondition));
      await prefs.setInt('weather_humidity', currentHumidity);
      await prefs.setInt('last_fetch_time', currentTime);
      await prefs.setDouble('last_fetch_lat', _latitude);
      await prefs.setDouble('last_fetch_lon', _longitude);

      setState(() {
        _forecast = forecastText;
        _cropSuggestions = suggestions;
        _temp = currentTemp.toStringAsFixed(0);
        _condition = _capitalize(currentCondition);
        _humidity = currentHumidity;
        _isLoading = false;
      });
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final cachedForecast = prefs.getString('cached_forecast');
      final cachedSuggestions = prefs.getString('cached_suggestions');
      final cachedTemp = prefs.getString('weather_temp');
      final cachedCondition = prefs.getString('weather_condition');
      final cachedHumidity = prefs.getInt('weather_humidity');

      setState(() {
        if (cachedForecast != null && cachedSuggestions != null) {
          _forecast = 'Offline - Last cached forecast:\n$cachedForecast';
          _cropSuggestions = cachedSuggestions;
          _temp = cachedTemp ?? _temp;
          _condition = cachedCondition ?? _condition;
          _humidity = cachedHumidity ?? _humidity;
        } else {
          _error = 'Unable to load forecast. Check internet and try again.';
        }
        _isLoading = false;
      });
    }
  }

  String _processForecastData(Map<String, dynamic> data) {
    final current = data['current'];
    final currentTemp = (current['temp'] as num).toDouble();
    final currentDesc = current['weather'][0]['description'] as String;
    final humidity = (current['humidity'] as num).toDouble();
    final List dailyData = data['daily'];

    double weeklyTempSum = 0;
    int rainyDays = 0;
    for (int i = 0; i < 7 && i < dailyData.length; i++) {
      final day = dailyData[i];
      weeklyTempSum += (day['temp']['day'] as num).toDouble();
      if (day.containsKey('rain')) rainyDays++;
    }
    final avgTemp = weeklyTempSum / 7;

    return 'Current: ${_capitalize(currentDesc)}, ${currentTemp.toStringAsFixed(1)}C\n'
        'Weekly outlook: ${rainyDays > 3 ? 'Rainy' : 'Partly cloudy'} (${avgTemp.toStringAsFixed(1)}C avg)\n'
        'Expected rainy days: $rainyDays\n'
        'Humidity: ${humidity.toStringAsFixed(0)}%';
  }

  String _generateCropSuggestions(Map<String, dynamic> data) {
    final List dailyData = data['daily'];
    final current = data['current'];
    double avgTemp = 0;
    int rainyDays = 0;

    for (int i = 0; i < 7 && i < dailyData.length; i++) {
      final day = dailyData[i];
      avgTemp += (day['temp']['day'] as num).toDouble();
      if (day.containsKey('rain')) rainyDays++;
    }
    avgTemp = avgTemp / 7;

    final humidity = (current['humidity'] as num).toDouble();
    final suggestions = <String>[];

    if (avgTemp >= 20 && avgTemp <= 30) {
      suggestions.add('Excellent window for tomatoes, peppers, and beans.');
    } else if (avgTemp < 20) {
      suggestions.add('Suitable for potatoes, cabbage, and carrots.');
    } else {
      suggestions.add('Use heat-tolerant crops such as okra and eggplant.');
    }

    if (rainyDays > 4) {
      suggestions.add('High moisture risk: monitor for fungal pressure.');
    } else if (rainyDays < 2) {
      suggestions.add('Plan irrigation support for young plants.');
    }

    if (humidity > 80) {
      suggestions.add('Increase spacing to improve field air circulation.');
    }

    return suggestions.join('\n');
  }

  String _capitalize(String text) {
    return text
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  String _localizedMultiline(
    AppLanguageController language,
    String text,
  ) {
    return text
        .split('\n')
        .map((line) => _localizeForecastLine(language, line))
        .join('\n');
  }

  String _localizeForecastLine(
    AppLanguageController language,
    String line,
  ) {
    if (line.startsWith('Current: ')) {
      final details = line.substring('Current: '.length);
      final separatorIndex = details.lastIndexOf(', ');
      if (separatorIndex != -1) {
        final condition = details.substring(0, separatorIndex);
        final temperature = details.substring(separatorIndex + 2);
        return '${language.text('Current:')} ${language.text(condition)}, $temperature';
      }
    }

    if (line.startsWith('Weekly outlook: ')) {
      final details = line.substring('Weekly outlook: '.length);
      final match = RegExp(r'^(.*) \((.*)\)$').firstMatch(details);
      if (match != null) {
        final summary = match.group(1) ?? '';
        final metrics = match.group(2) ?? '';
        return '${language.text('Weekly outlook:')} ${language.text(summary)} ($metrics)';
      }
    }

    if (line.startsWith('Expected rainy days: ')) {
      final rainyDays = line.substring('Expected rainy days: '.length);
      return '${language.text('Expected rainy days:')} $rainyDays';
    }

    if (line.startsWith('Humidity: ')) {
      final humidity = line.substring('Humidity: '.length);
      return '${language.text('Humidity')}: $humidity';
    }

    if (line == 'Offline - Last cached forecast:') {
      return language.text(line);
    }

    return language.text(line);
  }

  Future<void> _refreshLocation() async {
    final language = AppLanguageScope.of(context);
    final hasPermission = await _checkLocationPermission();
    if (hasPermission) {
      await _getCurrentLocation();
      await _loadForecast();
    } else {
      _showSnackBar(
        language.text('Location permission is needed for local forecast.'),
      );
    }
  }

  void _showPermissionDialog(
    String title,
    String message, {
    bool showSettings = false,
  }) {
    final language = AppLanguageScope.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          if (showSettings)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: Text(language.text('Open Settings')),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(language.text('OK')),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _metricTile(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({
    required String title,
    required String content,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2E7D32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(content,
              style: TextStyle(color: Colors.grey.shade800, height: 1.35)),
        ],
      ),
    );
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
            colors: [Color(0xFF73B471), Color(0xFFE9F5E8)],
            stops: [0.28, 1],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 44),
                            const SizedBox(height: 10),
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: _loadForecast,
                              child: Text(language.text('Retry')),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadForecast,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.arrow_back_rounded,
                                    color: Colors.white),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: _refreshLocation,
                                icon: const Icon(Icons.my_location_rounded,
                                    color: Colors.white),
                              ),
                              IconButton(
                                onPressed: _loadForecast,
                                icon: const Icon(Icons.refresh_rounded,
                                    color: Colors.white),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _locationName,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$_temp°C',
                                style: const TextStyle(
                                  fontSize: 52,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  language.text(_condition),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _metricTile(
                                  language.text('Humidity'), '$_humidity%'),
                              const SizedBox(width: 8),
                              _metricTile(
                                language.text('Temp'),
                                '$_temp°C',
                              ),
                              const SizedBox(width: 8),
                              _metricTile(
                                language.text('Rain'),
                                language.text(
                                  _forecast.contains('Rainy') ? 'High' : 'Low',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _infoCard(
                            title: language.text('Forecast Overview'),
                            content: _localizedMultiline(language, _forecast),
                            icon: Icons.cloud_rounded,
                          ),
                          _infoCard(
                            title: language.text('Crop Planning Guidance'),
                            content: _localizedMultiline(
                              language,
                              _cropSuggestions,
                            ),
                            icon: Icons.agriculture_rounded,
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}
