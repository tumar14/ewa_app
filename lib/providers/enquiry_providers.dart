import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/enquiry.dart';
import '../services/enquiry_repository.dart';

final enquiryRepositoryProvider = Provider((ref) => EnquiryRepository());

final enquiriesProvider = StreamProvider<List<Enquiry>>((ref) {
  return ref.watch(enquiryRepositoryProvider).watchRecent();
});

final newEnquiryCountProvider = Provider<int>((ref) {
  final list = ref.watch(enquiriesProvider).valueOrNull ?? const <Enquiry>[];
  return list.where((e) => !e.handled).length;
});
