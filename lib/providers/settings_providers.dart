import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settings.dart';
import 'firebase_providers.dart';

final appSettingsProvider = StreamProvider<AppSettings>((ref) {
  return ref.watch(settingsRepositoryProvider).watch();
});
