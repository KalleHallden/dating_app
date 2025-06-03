import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseClient {
  static SupabaseClient? _instance;

  static SupabaseClient get instance {
    _instance ??= SupabaseClient._();
    return _instance!;
  }

  SupabaseClient._();

  static Future<void> initialize() async {
    await dotenv.load(fileName: ".env");
    await supabase.Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
  }

  supabase.SupabaseClient get client => supabase.Supabase.instance.client;
}
