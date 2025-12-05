import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/admin_prefs_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _regions = const ['cm', 'cg', 'cd', 'ci', 'ga'];
  String? _region;
  int? _mtnSimSlot; // 0 or 1
  int? _airtelSimSlot; // 0 or 1
  final _apiUrlCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await AdminPrefsService.loadCurrent();
    setState(() {
      _region = prefs.regionCode;
      _mtnSimSlot = prefs.mtnSimSlot;
      _airtelSimSlot = prefs.airtelSimSlot;
      _apiUrlCtrl.text = prefs.smsApiUrl ?? '';
    });
  }

  @override
  void dispose() {
    _apiUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AdminPrefsService.saveCurrent(AdminPrefs(
        regionCode: _region?.trim(),
        mtnSimSlot: _mtnSimSlot,
        airtelSimSlot: _airtelSimSlot,
        smsApiUrl: _apiUrlCtrl.text.trim().isEmpty ? null : _apiUrlCtrl.text.trim(),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Préférences enregistrées')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (user != null) Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: Text(user.email ?? 'Admin'),
              subtitle: Text('ID: ${user.uid}'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Région', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _region,
                    items: _regions
                        .map((r) => DropdownMenuItem(value: r, child: Text(r.toUpperCase())))
                        .toList(),
                    onChanged: (v) => setState(() => _region = v),
                    decoration: const InputDecoration(hintText: 'Sélectionnez la région'),
                  ),
                  const SizedBox(height: 16),
                  Text('Mapping SIM (Appareil Android)', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _mtnSimSlot,
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('SIM 1')),
                          DropdownMenuItem(value: 1, child: Text('SIM 2')),
                        ],
                        onChanged: (v) => setState(() => _mtnSimSlot = v),
                        decoration: const InputDecoration(labelText: 'MTN SIM'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _airtelSimSlot,
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('SIM 1')),
                          DropdownMenuItem(value: 1, child: Text('SIM 2')),
                        ],
                        onChanged: (v) => setState(() => _airtelSimSlot = v),
                        decoration: const InputDecoration(labelText: 'Airtel SIM'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Text('Passerelle SMS (optionnel, serveur)', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _apiUrlCtrl,
                    decoration: const InputDecoration(
                      hintText: 'https://votre-serveur/sms/send',
                      labelText: 'URL API',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Enregistrer'),
            ),
          ),
        ],
      ),
    );
  }
}


