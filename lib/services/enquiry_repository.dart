import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/enquiry.dart';

/// Platform-admin access to website submissions. Reads and the "handled" flag
/// go straight to Firestore; firestore.rules limit both to the platform admin
/// and restrict updates to the status/handling fields.
class EnquiryRepository {
  final CollectionReference<Map<String, dynamic>> _collection;

  EnquiryRepository({FirebaseFirestore? firestore})
      : _collection = (firestore ?? FirebaseFirestore.instance).collection('public_enquiries');

  Stream<List<Enquiry>> watchRecent({int limit = 100}) {
    return _collection
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Enquiry.fromMap(d.id, d.data())).toList());
  }

  Future<void> setHandled(String id, bool handled, {String? note}) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return _collection.doc(id).update({
      'status': handled ? 'handled' : 'new',
      'handledBy': uid,
      'handledAt': FieldValue.serverTimestamp(),
      if (note != null) 'note': note,
    });
  }
}
