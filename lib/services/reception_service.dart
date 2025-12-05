import 'package:cloud_firestore/cloud_firestore.dart';

/// Service helper to send a message from a client app to admin reception collection.
class ReceptionService {
  ReceptionService._();
  static final instance = ReceptionService._();

  /// Send a user message to the `reception` collection.
  /// `senderId` and `senderName` are optional (null for anonymous).
  Future<DocumentReference<Map<String, dynamic>>> sendUserMessage({
    String? senderId,
    String? senderName,
    String? phone,
    required String text,
    Map<String, dynamic>? metadata,
  }) async {
    final doc = await FirebaseFirestore.instance.collection('reception').add({
      'senderId': senderId,
      'senderName': senderName,
      'phone': phone,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'handled': false,
      'metadata': metadata ?? {},
    });

    return doc;
  }
}
