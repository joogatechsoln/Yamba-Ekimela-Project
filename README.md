# CropAid Uganda

CropAid Uganda is a Flutter app for crop disease diagnosis, weather guidance,
farmer support, and dealer messaging.

## Features

- Plant disease detection from captured or selected images
- Disease descriptions, recommendations, and treatment guidance
- Weather forecast and crop suggestions
- Farmer and dealer authentication with Supabase
- Dealer directory and in-app messaging
- Profile image upload and diagnosis image sharing through Supabase Storage

## Tech Stack

- Flutter
- Supabase Auth, Database, and Storage
- TensorFlow Lite
- OpenWeather API

## Project Structure

- `lib/` application code
- `assets/` ML model, labels, disease data, and dealer seed data
- `supabase/` SQL setup scripts for database and storage

## Local Setup

1. Install Flutter and project dependencies.
2. Create your Supabase project.
3. Run `supabase/full_supabase_setup.sql` in the Supabase SQL Editor.
4. Start the app with runtime configuration using `--dart-define`.

Example:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=your_supabase_url `
  --dart-define=SUPABASE_ANON_KEY=your_supabase_anon_key `
  --dart-define=OPENWEATHER_API_KEY=your_openweather_api_key `
  --dart-define=RAPID_TRANSLATE_API_KEY=your_rapidapi_key
```

Optional translation settings:

```powershell
flutter run `
  --dart-define=RAPID_TRANSLATE_URL=https://deep-translate1.p.rapidapi.com/language/translate/v2 `
  --dart-define=RAPID_TRANSLATE_HOST=deep-translate1.p.rapidapi.com
```

## Security Notes

- Do not commit live API keys or Supabase keys.
- `lib/supabase_config.dart` is intentionally blank for GitHub-safe versioning.
- Prefer `--dart-define` or CI/CD secrets for all runtime credentials.

## Recommended GitHub Commit Scope

- Keep source code, assets, and SQL scripts
- Ignore `build/`, `.dart_tool/`, IDE files, local logs, and crash dumps
- Avoid committing generated secrets or machine-specific configuration
