import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminPrefs {
  final String? regionCode; // e.g. cm, cg, ci
  final int? mtnSimSlot; // 0 or 1
  final int? airtelSimSlot; // 0 or 1
  final String? smsApiUrl; // Optional server endpoint for SMS batch

  const AdminPrefs({
    this.regionCode,
    this.mtnSimSlot,
    this.airtelSimSlot,
    this.smsApiUrl,
  });

  AdminPrefs copyWith({
    String? regionCode,
    int? mtnSimSlot,
    int? airtelSimSlot,
    String? smsApiUrl,
  }) {
    return AdminPrefs(
      regionCode: regionCode ?? this.regionCode,
      mtnSimSlot: mtnSimSlot ?? this.mtnSimSlot,
      airtelSimSlot: airtelSimSlot ?? this.airtelSimSlot,
      smsApiUrl: smsApiUrl ?? this.smsApiUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'regionCode': regionCode,
      'mtnSimSlot': mtnSimSlot,
      'airtelSimSlot': airtelSimSlot,
      'smsApiUrl': smsApiUrl,
    }..removeWhere((key, value) => value == null);
  }

  static AdminPrefs fromMap(Map<String, dynamic>? data) {
    if (data == null) return const AdminPrefs();
    return AdminPrefs(
      regionCode: (data['regionCode'] as String?)?.trim(),
      mtnSimSlot: (data['mtnSimSlot'] as num?)?.toInt(),
      airtelSimSlot: (data['airtelSimSlot'] as num?)?.toInt(),
      smsApiUrl: (data['smsApiUrl'] as String?)?.trim(),
    );
  }
}

class AdminPrefsService {
  static DocumentReference<Map<String, dynamic>> _docRef(String uid) {
    // Store under admins/{uid}
    return FirebaseFirestore.instance.collection('admins').doc(uid);
  }

  static Future<AdminPrefs> loadCurrent() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const AdminPrefs();
    final snap = await _docRef(uid).get();
    return AdminPrefs.fromMap(snap.data());
  }

  static Future<void> saveCurrent(AdminPrefs prefs) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _docRef(uid).set(prefs.toMap(), SetOptions(merge: true));
  }
}


