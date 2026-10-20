import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/platform_config_repository.dart';

final platformConfigRepositoryProvider = Provider((ref) => PlatformConfigRepository());

final drawCeilingProvider = StreamProvider<double>((ref) {
  return ref.watch(platformConfigRepositoryProvider).watchDrawCeiling();
});

final websiteIndustriesProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(platformConfigRepositoryProvider).watchIndustries();
});
