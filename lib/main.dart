import 'package:cropaid_uganda/home_page.dart';
import 'package:cropaid_uganda/dealer_directory_page.dart';
import 'package:cropaid_uganda/dealer_inbox_page.dart';
import 'package:cropaid_uganda/profile_page.dart';
import 'package:cropaid_uganda/results_page.dart';
import 'package:cropaid_uganda/scan_page.dart';
import 'package:cropaid_uganda/weather_forecast_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_services.dart';
import 'app_language.dart';
import 'landing_page.dart';
import 'supabase_config.dart' as local_config;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const envSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const envSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  final resolvedSupabaseUrl =
      envSupabaseUrl.isNotEmpty ? envSupabaseUrl : local_config.supabaseUrl;
  final resolvedSupabaseAnonKey = envSupabaseAnonKey.isNotEmpty
      ? envSupabaseAnonKey
      : local_config.supabaseAnonKey;

  if (resolvedSupabaseUrl.isNotEmpty && resolvedSupabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: resolvedSupabaseUrl,
      anonKey: resolvedSupabaseAnonKey,
    );
    AppServices.supabaseReady = true;
  }

  final languageController = AppLanguageController();
  await languageController.load();

  runApp(CropAIDApp(languageController: languageController));
}

class CropAIDApp extends StatelessWidget {
  const CropAIDApp({super.key, required this.languageController});

  final AppLanguageController languageController;

  @override
  Widget build(BuildContext context) {
    return AppLanguageScope(
      controller: languageController,
      child: MaterialApp(
        title: 'Yamba Ekimera',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
          useMaterial3: true,
        ),
        home: LandingPage(),
        routes: {
          '/home': (context) => HomePage(),
          '/scan': (context) => ScanPage(),
          '/results': (context) => ResultsPage(),
          '/weather': (context) => WeatherForecastPage(),
          '/profile': (context) => ProfilePage(),
          '/dealers': (context) => const DealerDirectoryPage(),
          '/dealer-inbox': (context) => const DealerInboxPage(),
        },
      ),
    );
  }
}
