import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Get App ID from environment variables
/// This is loaded from .env file
String get appId {
  return dotenv.env['AGORA_APP_ID'] ?? '';
}

/// Placeholder token - actual tokens come from server
/// This should never be used in production
String get token {
  return '';
}

/// Placeholder channel ID - actual channel IDs come from matchmaking
String get channelId {
  return '';
}

/// Screen sharing UID if needed
const int screenSharingUid = 10;

/// Default role for users
const String defaultRole = 'publisher';

/// Music Center App ID if needed (optional)
String get musicCenterAppId {
  return dotenv.env['MUSIC_CENTER_APPID'] ?? '';
}
