import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'translation_config.dart';

class AppLanguageController extends ChangeNotifier {
  static const String _languagePrefKey = 'app_language';
  static const String _lugandaCacheKey = 'luganda_translation_cache';

  static const List<LanguageOption> supportedLanguages = [
    LanguageOption(code: 'en', label: 'English'),
    LanguageOption(code: 'lg', label: 'Luganda'),
  ];

  final Map<String, String> _lugandaCache = {};
  final Set<String> _pendingTexts = {};
  String _currentLanguageCode = 'en';

  String get currentLanguageCode => _currentLanguageCode;
  bool get isLuganda => _currentLanguageCode == 'lg';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _currentLanguageCode = prefs.getString(_languagePrefKey) ?? 'en';
    final cached = prefs.getString(_lugandaCacheKey);
    if (cached != null && cached.isNotEmpty) {
      final decoded = json.decode(cached);
      if (decoded is Map<String, dynamic>) {
        _lugandaCache
          ..clear()
          ..addAll(
              decoded.map((key, value) => MapEntry(key, value.toString())));
      }
    }
  }

  Future<void> setLanguage(String languageCode) async {
    if (_currentLanguageCode == languageCode) return;
    _currentLanguageCode = languageCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languagePrefKey, languageCode);
    notifyListeners();
  }

  String languageLabel(String languageCode) {
    return supportedLanguages
        .firstWhere(
          (option) => option.code == languageCode,
          orElse: () => supportedLanguages.first,
        )
        .label;
  }

  String text(String englishText) {
    if (!isLuganda || englishText.trim().isEmpty) {
      return englishText;
    }

    final builtIn = _lugandaDefaults[englishText];
    if (builtIn != null) {
      return builtIn;
    }

    final cached = _lugandaCache[englishText];
    if (cached != null) {
      return cached;
    }

    _translateInBackground(englishText);
    return englishText;
  }

  Future<String> translate(String englishText) async {
    if (!isLuganda || englishText.trim().isEmpty) {
      return englishText;
    }

    final builtIn = _lugandaDefaults[englishText];
    if (builtIn != null) {
      return builtIn;
    }

    final cached = _lugandaCache[englishText];
    if (cached != null) {
      return cached;
    }

    return _translateAndStore(englishText);
  }

  Future<void> preload(Iterable<String> englishTexts) async {
    if (!isLuganda) return;
    for (final text in englishTexts) {
      await translate(text);
    }
  }

  Future<void> _translateInBackground(String englishText) async {
    if (_pendingTexts.contains(englishText)) return;
    _pendingTexts.add(englishText);
    try {
      await _translateAndStore(englishText);
    } finally {
      _pendingTexts.remove(englishText);
    }
  }

  Future<String> _translateAndStore(String englishText) async {
    try {
      final response = await http.post(
        Uri.parse(rapidTranslateUrl),
        headers: const {
          'Content-Type': 'application/json',
          'x-rapidapi-host': rapidTranslateHost,
          'x-rapidapi-key': rapidTranslateApiKey,
        },
        body: json.encode({
          'q': englishText,
          'source': 'en',
          'target': 'lg',
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return englishText;
      }

      final decoded = json.decode(response.body);
      final translated = _extractTranslatedText(decoded);
      if (translated == null || translated.trim().isEmpty) {
        return englishText;
      }

      _lugandaCache[englishText] = translated;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lugandaCacheKey, json.encode(_lugandaCache));
      notifyListeners();
      return translated;
    } catch (_) {
      return englishText;
    }
  }

  String? _extractTranslatedText(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) {
        final translations = data['translations'];
        if (translations is Map<String, dynamic>) {
          final translatedText = translations['translatedText'];
          if (translatedText is String) {
            return translatedText;
          }
        }
        if (translations is List && translations.isNotEmpty) {
          final first = translations.first;
          if (first is Map<String, dynamic> &&
              first['translatedText'] is String) {
            return first['translatedText'] as String;
          }
        }
        if (data['translatedText'] is String) {
          return data['translatedText'] as String;
        }
      }
      if (decoded['translatedText'] is String) {
        return decoded['translatedText'] as String;
      }
    }
    return null;
  }
}

class LanguageOption {
  const LanguageOption({required this.code, required this.label});

  final String code;
  final String label;
}

class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    super.key,
    required AppLanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLanguageController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppLanguageScope>();
    assert(scope != null, 'AppLanguageScope not found in widget tree.');
    return scope!.notifier!;
  }
}

const Map<String, String> _lugandaDefaults = {
  'Welcome to\nYamba Ekimera': 'Tukwaniriza ku\nYamba Ekimera',
  'AI-powered tools for smarter farming in Uganda':
      'Ebikozesebwa bya AI okufulumya obulimi obusinga obugezi mu Uganda',
  'Get Started': 'Tandika',
  'Create Account': 'Ggulawo Akawunti',
  'Welcome Back': 'Tukwaniriza nate',
  'Join Yamba Ekimera and start smart farming':
      'Weegatte ku Yamba Ekimera otandike okulima mu ngeri eyamagezi',
  'Sign in to continue': 'Yingira okusobola okugenda mu maaso',
  'Full Name': 'Erinnya lyo lyonna',
  'Email': 'Email',
  'Password': 'Paasiwode',
  'Sign In': 'Yingira',
  'Already have an account? Sign in': 'Olina dda akawunti? Yingira',
  'No account? Create one': 'Tolina akawunti? Gikolere',
  'Preferred language': 'Olulimi lw’oyagala',
  'Choose app language': 'Londa olulimi lwa app',
  'English': 'Lungereza',
  'Luganda': 'Luganda',
  'Enter email and password.': 'Yingiza email ne paasiwode.',
  'Enter your full name.': 'Yingiza erinnya lyo lyonna.',
  'Authentication failed. Please try again.':
      'Okuyingira kulemye. Gezaako nate.',
  'My Profile': 'Pulafo yange',
  'Member since': 'Mmember okuva',
  'Edit details': 'Kyusa ebikwata ku ggwe',
  'Edit Profile': 'Kyusa Pulafo',
  'Name': 'Erinnya',
  'Phone Number': 'Namba y’essimu',
  'Cancel': 'Sazaamu',
  'Save': 'Tereka',
  'Profile updated': 'Pulafo ekyusiddwa',
  'Clear history?': 'Gyawo ebyafaayo?',
  'This will remove all diagnosis history.':
      'Kino kijja kugyawo ebyafaayo byonna eby’okukebera.',
  'Clear': 'Gyawo',
  'Logout failed. Please try again.':
      'Okuva mu akawunti kulemye. Gezaako nate.',
  'Total Scans': 'Ennamba y’okusima',
  'This Month': 'Omwezi guno',
  'Diagnosis History': 'Ebyafaayo by’okukebera',
  'No diagnosis history yet': 'Tewali byafaayo bya kukebera nate',
  'Scan Results': 'Ebivudde mu kusima',
  'Analyzing your crop...': 'Tuliko kwekenneenya ekirime kyo...',
  'Analysis Failed': 'Okwekenneenya kulemye',
  'Try Again': 'Gezaako Nate',
  'Forecast Overview': 'Okulaba embeera y’obudde',
  'Crop Planning Guidance': 'Obulagirizi bw’okutegeka ebirime',
  'Retry': 'Ddamu',
  'Hi': 'Gyebale ko',
  'Very High': 'Waggulu nnyo',
  'Good': 'Kirungi',
  'Confidence Level': 'Obwesige bw’ekivudde mu kukebera',
  'Understanding Accuracy': 'Okutegeera obutuufu',
  'Above 90%: Very reliable result\n70-90%: Good detection, consider retaking in better light\nBelow 70%: Low confidence, try a clearer photo':
      'Waggulu wa 90%: Ekyivuddeyo ky’esigika nnyo\n70-90%: Okuzuula kulungi, ddamu okukuba ekifaananyi awali ekitangaala ekirungi\nWansi wa 70%: Obwesige butono, gezaako ekifaananyi ekisinga obutangaavu',
  'Description': 'Ennyonnyola',
  'Recommendations': 'Ebisanyizo',
  'Treatments & Drugs': 'Obujjanjabi n’eddagala',
  'Scan Again': 'Ddamu okusima',
  'Home': 'Awaka',
  'Loading weather...': 'Tulinda obudde...',
  'Loading recommendations...': 'Tulinda amagezi...',
  'Loading forecast...': 'Tulinda okulagula obudde...',
  'Loading crop suggestions...': 'Tulinda amagezi ku birime...',
  'Your Location': 'Ekifo kyo',
  'Sunny Day': 'Olunaku olw’enjuba',
  'Offline mode - Unable to fetch weather':
      'Tuli offline - tetusobodde kufuna budde',
  'Offline - Last cached forecast:':
      'Tuli offline - eno ye forecast eyasembayo okuterekebwa:',
  'Unknown date': 'Ennaku terimanyiddwa',
  'Humidity': 'Obunnyogovu',
  'Temp': 'Ebbugumu',
  'Rain': 'Enkuba',
  'High': 'Wangi',
  'Low': 'Tono',
  'Rainy': 'Enkuba erimu',
  'Partly cloudy': 'Ekire kitono',
  'Current:': 'Kati:',
  'Weekly outlook:': 'Obudde bw’essaawa ezijja:',
  'Expected rainy days:': 'Ennaku z’enkuba ezisuubirwa:',
  'Farm insight': 'Amagezi ku nnimiro',
  'Check out': 'Laba',
  'Special Crop Care Tips': 'Amagezi ag’enjawulo ku kulabirira ebirime',
  'View forecast': 'Laba embeera y’obudde',
  'Great day for tomatoes, peppers and beans.':
      'Luno lunaku lulungi eri ennyaanya, bbiringanya n’ebijanjaalo.',
  'Cool conditions suit cabbage and carrots.':
      'Obunnyogovu buno busaanira sukuma wiiki ne kaloti.',
  'Heat-tolerant crops like okra are safer now.':
      'Ebirime ebigumira ebbugumu nga okra bisinga obukuumi kati.',
  'High moisture: watch for fungal disease early.':
      'Obunnyogovu bungi: weegendereze endwadde za fungus nga bukyali.',
  'Irrigate young plants more consistently.':
      'Fukirira ebimera ebito mu ngeri etasalako.',
  'Excellent window for tomatoes, peppers, and beans.':
      'Kino kiseera kirungi nnyo eri ennyaanya, bbiringanya n’ebijanjaalo.',
  'Suitable for potatoes, cabbage, and carrots.':
      'Kisaanira lumonde, sukuma wiiki ne kaloti.',
  'Use heat-tolerant crops such as okra and eggplant.':
      'Kozesa ebirime ebigumira ebbugumu nga okra ne nnakati.',
  'High moisture risk: monitor for fungal pressure.':
      'Waliwo akabi k’obunnyogovu bungi: kebera obulwadde bwa fungus.',
  'Plan irrigation support for young plants.':
      'Tegeka okufukirira okuyamba ebimera ebito.',
  'Increase spacing to improve field air circulation.':
      'Yongera ebbanga wakati w’ebimera empewo esobole okuyita obulungi.',
  'Scan Crop': 'Sima ekirime',
  'Weather': 'Obudde',
  'Profile': 'Pulafo',
  'History': 'Ebyafaayo',
  'History is in your profile page.':
      'Ebyafaayo biri ku lupapula lwa pulafo yo.',
  'Camera Permission Required': 'Olukusa lwa kamera lwetaagisa',
  'Enable camera access in settings to scan crop leaves.':
      'Ggulawo olukusa lwa kamera mu settings okusima ebikoola by’ebirime.',
  'Gallery Permission Required': 'Olukusa lwa gallery lwetaagisa',
  'Enable gallery access in settings to select a leaf image.':
      'Ggulawo olukusa lwa gallery mu settings okulonda ekifaananyi ky’ekikoola.',
  'Camera permission is required': 'Olukusa lwa kamera lwetaagisa',
  'Gallery permission is required': 'Olukusa lwa gallery lwetaagisa',
  'Preview': 'Laba okusooka',
  'Retake': 'Ddamu okukuba',
  'Analyze': 'Kenneenya',
  'Failed to capture image. Please try again.':
      'Okukwata ekifaananyi kulemye. Gezaako nate.',
  'Failed to pick image. Please try again.':
      'Okulonda ekifaananyi kulemye. Gezaako nate.',
  'Open Settings': 'Ggulawo Settings',
  'OK': 'Kale',
  'Scan crop leaf': 'Sima ekikoola ky’ekirime',
  'Center the affected part for best results.':
      'Teeka ekitundu ekirwadde mu makkati ofune ebisinga obulungi.',
  'Open Camera': 'Ggulawo Kamera',
  'Choose from Gallery': 'Londa okuva mu Gallery',
  'Location Permission Needed': 'Olukusa lw’ekifo lwe lwetaagisa',
  'Enable location to get weather specific to your farm area.':
      'Ggulawo ekifo ofune obudde obukwatagana n’ennimiro yo.',
  'Location Permission Required': 'Olukusa lw’ekifo lwetaagisa',
  'Location permission is permanently denied. Enable it in app settings.':
      'Olukusa lw’ekifo lwagaaniddwa ddala. Luggulawo mu settings za app.',
  'Location service is off. Using cached location.':
      'Enkola y’ekifo eggaddwa. Tugenda kukozesa ekifo ekiterekeddwa.',
  'Could not get current location. Using cached location.':
      'Tetufunye kifo kyo kati. Tugenda kukozesa ekifo ekiterekeddwa.',
  'Location permission is needed for local forecast.':
      'Olukusa lw’ekifo lwetaagisa okufunira obudde bw’ekitundu.',
};
