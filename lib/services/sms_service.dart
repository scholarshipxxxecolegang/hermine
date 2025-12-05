import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:telephony/telephony.dart';
import 'admin_prefs_service.dart';

class SmsService {
  static final Telephony _telephony = Telephony.instance;

  // Best-effort: try to guess carrier by phone prefix when possible
  static String? _guessCarrier(String phone, String? regionCode) {
    final normalized = phone.replaceAll(RegExp(r"[^0-9+]"), '');
    final rc = (regionCode ?? '').toLowerCase();
    // Minimal stubs; can be expanded per country
    if (rc == 'cm') {
      // Cameroon common prefixes (not exhaustive)
      if (RegExp(r"^(\+237)?6(5|7|8)").hasMatch(normalized)) return 'mtn';
      if (RegExp(r"^(\+237)?6(9)").hasMatch(normalized)) return 'airtel';
    }
    return null;
  }

  static Future<int> sendBatchSms({
    required List<String> phones,
    required String message,
  }) async {
    if (phones.isEmpty || message.trim().isEmpty) return 0;

    final prefs = await AdminPrefsService.loadCurrent();

    // If API endpoint is configured, prefer server-side SMS to ensure delivery
    if ((prefs.smsApiUrl ?? '').isNotEmpty) {
      final uri = Uri.parse(prefs.smsApiUrl!.trim());
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phones': phones,
          'message': message,
          'regionCode': prefs.regionCode,
          'source': 'hermine_admin',
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        return (data['sent'] as num?)?.toInt() ?? phones.length;
      } else {
        // Fall back to device SMS if server fails
      }
    }

    // Device SMS fallback with SIM slot routing (MTN/Airtel)
    final granted = await _telephony.requestPhoneAndSmsPermissions ?? false;
    if (!granted) return 0;

    int sent = 0;
    for (final p in phones) {
      // Attempt to detect carrier (future use)
      _guessCarrier(p, prefs.regionCode);

      try {
        await _telephony.sendSms(
          to: p,
          message: message,
          isMultipart: message.length > 160,
          // Note: current telephony version may not expose simSlot; uses default SIM
        );
        sent += 1;
        await Future.delayed(const Duration(milliseconds: 600));
      } catch (_) {}
    }
    return sent;
  }
}


