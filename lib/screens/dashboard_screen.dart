import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:telephony/telephony.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class StatsCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const StatsCard({
    Key? key,
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const Icon(Icons.more_vert, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardScreenState extends State<DashboardScreen> {
  final List<String> _allCategories = const ['parent', 'eleve', 'enseignant'];
  final Set<String> _selected = {'parent'};
  final TextEditingController _textCtrl = TextEditingController();
  bool _sending = false;

  // Cloudinary (via config centralisée)

  // Audio state (record v6)
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isUploadingAudio = false;
  DateTime? _recordStart;
  String? _audioError;
  Stream<QuerySnapshot<Map<String, dynamic>>> get _recentMessagesStream =>
      FirebaseFirestore.instance
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots();

  Future<void> _sendSmsToSelectedUsers(String text) async {
    try {
      final telephony = Telephony.instance;
      final granted = await telephony.requestPhoneAndSmsPermissions ?? false;
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permission SMS refusée')),
          );
        }
        return;
      }
      final qs = await FirebaseFirestore.instance
          .collection('users')
          .where('category', whereIn: _selected.toList())
          .get();
      for (final d in qs.docs) {
        final data = d.data();
        final phone = (data['phone'] ?? '').toString().trim();
        if (phone.isEmpty) continue;
        try {
          await telephony.sendSms(
            to: phone,
            message: text,
            isMultipart: text.length > 160,
          );
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _sendTextMessage() async {
    if (_textCtrl.text.trim().isEmpty || _selected.isEmpty) return;
    final text = _textCtrl.text.trim();
    setState(() => _sending = true);
    try {
      await _sendSmsToSelectedUsers(text);
      await FirebaseFirestore.instance.collection('messages').add({
        'senderId': FirebaseAuth.instance.currentUser?.uid,
        'categories': _selected.toList(),
        'type': 'text',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _textCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Message envoyé')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<String?> _uploadToCloudinary(File file) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName}/upload',
    );
    final req = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = CloudinaryConfig.uploadPreset
      ..fields['folder'] = 'audio'
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          contentType: MediaType('audio', 'mp4'),
        ),
      );

    final res = await req.send();
    if (res.statusCode == 200) {
      final body = await res.stream.bytesToString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data['secure_url'] as String?;
    } else {
      final err = await res.stream.bytesToString();
      throw Exception('Cloudinary error ${res.statusCode}: $err');
    }
  }

  Future<void> _toggleRecord() async {
    if (_isRecording) {
      await _stopAndUploadAudio();
      return;
    }
    _audioError = null;
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      setState(() => _audioError = 'Permission micro refusée');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );
      setState(() {
        _isRecording = true;
        _recordStart = DateTime.now();
      });
    } catch (e) {
      setState(() => _audioError = 'Erreur enregistrement: $e');
    }
  }

  Future<void> _stopAndUploadAudio() async {
    try {
      final path = await _recorder.stop();
      setState(() => _isRecording = false);
      if (path == null) return;
      final file = File(path);
      if (!file.existsSync()) return;
      final secs = _recordStart != null
          ? DateTime.now().difference(_recordStart!).inSeconds
          : null;
      setState(() => _isUploadingAudio = true);

      // 1) Créer le message audio
      final msgRef = await FirebaseFirestore.instance
          .collection('messages')
          .add({
            'senderId': FirebaseAuth.instance.currentUser?.uid,
            'categories': _selected.toList(),
            'type': 'audio',
            'audioFormat': 'aac',
            'durationSec': secs,
            'createdAt': FieldValue.serverTimestamp(),
          });

      // 2) Upload Cloudinary
      final url = await _uploadToCloudinary(file);
      if (url == null || url.isEmpty) {
        throw Exception('URL Cloudinary vide');
      }

      // 3) Mise à jour du message
      await msgRef.update({'audioUrl': url});

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Vocal envoyé')));
      }
    } catch (e) {
      if (mounted) setState(() => _audioError = 'Erreur upload: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Échec de l\'upload audio: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploadingAudio = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Tableau de bord',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.notifications_none, size: 28),
                Positioned(
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 12,
                      minHeight: 12,
                    ),
                    child: const Text(
                      '3',
                      style: TextStyle(color: Colors.white, fontSize: 8),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
            onPressed: () {},
          ),
          const SizedBox(width: 10),
          const CircleAvatar(
            radius: 20,
            backgroundImage: NetworkImage(
              'https://randomuser.me/api/portraits/men/1.jpg',
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Colors.blue),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const CircleAvatar(
                      backgroundImage: NetworkImage(
                        'https://randomuser.me/api/portraits/men/1.jpg',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Admin User',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    '...........@example.com',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            _buildDrawerItem(
              icon: Icons.dashboard_outlined,
              title: 'Tableau de bord',
              isSelected: true,
              onTap: () {},
            ),
            _buildDrawerItem(
              icon: Icons.people_outline,
              title: 'Utilisateurs',
              onTap: () {},
            ),
            _buildDrawerItem(
              icon: Icons.message_outlined,
              title: 'Messages',
              onTap: () {},
            ),
            _buildDrawerItem(
              icon: Icons.settings_outlined,
              title: 'Paramètres',
              onTap: () {},
            ),
            const Divider(),
            _buildDrawerItem(
              icon: Icons.help_outline,
              title: 'Aide & Support',
              onTap: () {},
            ),
            _buildDrawerItem(
              icon: Icons.exit_to_app_outlined,
              title: 'Déconnexion',
              onTap: () => FirebaseAuth.instance.signOut(),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _buildDashboardContent(size),
      ),
    );
  }

  Widget _buildDashboardContent(Size size) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Aperçu des statistiques',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: size.width < 800 ? 2 : 4,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.5,
          children: const [
            StatsCard(
              title: 'Utilisateurs',
              value: '1,234',
              color: Colors.blue,
              icon: Icons.people_outline,
            ),
            StatsCard(
              title: 'Messages',
              value: '568',
              color: Colors.green,
              icon: Icons.message_outlined,
            ),
            StatsCard(
              title: 'Groupes',
              value: '24',
              color: Colors.orange,
              icon: Icons.group_outlined,
            ),
            StatsCard(
              title: 'Médias',
              value: '1.2 Go',
              color: Colors.purple,
              icon: Icons.photo_library_outlined,
            ),
          ],
        ),
        const SizedBox(height: 30),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (size.width > 800) ...[
              Expanded(
                flex: 2,
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Répartition des utilisateurs',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 200,
                          child: PieChart(
                            PieChartData(
                              sections: [
                                PieChartSectionData(
                                  color: Colors.blue,
                                  value: 40,
                                  title: '40%',
                                  radius: 80,
                                  titleStyle: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                PieChartSectionData(
                                  color: Colors.green,
                                  value: 30,
                                  title: '30%',
                                  radius: 80,
                                  titleStyle: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                PieChartSectionData(
                                  color: Colors.orange,
                                  value: 20,
                                  title: '20%',
                                  radius: 80,
                                  titleStyle: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                PieChartSectionData(
                                  color: Colors.purple,
                                  value: 10,
                                  title: '10%',
                                  radius: 80,
                                  titleStyle: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                              sectionsSpace: 0,
                              centerSpaceRadius: 50,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildLegendItem(Colors.blue, 'Élèves'),
                            _buildLegendItem(Colors.green, 'Enseignants'),
                            _buildLegendItem(Colors.orange, 'Parents'),
                            _buildLegendItem(Colors.purple, 'Admin'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
            ],
            Expanded(
              flex: 3,
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Messages récents',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton(
                            onPressed: () {},
                            child: const Text('Voir tout'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return StreamBuilder<
                            QuerySnapshot<Map<String, dynamic>>
                          >(
                            stream: _recentMessagesStream,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              if (snapshot.hasError) {
                                return Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: Colors.red.shade400,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Erreur lors du chargement: ${snapshot.error}',
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                );
                              }
                              final docs = snapshot.data?.docs ?? [];
                              if (docs.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'Aucun message envoyé pour le moment.',
                                    textAlign: TextAlign.center,
                                  ),
                                );
                              }

                              if (constraints.maxWidth < 600) {
                                return Column(
                                  children: docs
                                      .map(
                                        (doc) => _buildMobileMessageCard(doc),
                                      )
                                      .toList(),
                                );
                              }

                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Diffusion')),
                                    DataColumn(label: Text('Prévisualisation')),
                                    DataColumn(label: Text('Date')),
                                    DataColumn(label: Text('Type')),
                                    DataColumn(label: Text('Actions')),
                                  ],
                                  rows: docs
                                      .map((doc) => _buildDataRow(doc))
                                      .toList(),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        _buildRecentActivityCard(),
      ],
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    bool isSelected = false,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: isSelected ? Colors.blue : Colors.grey[700]),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.blue : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: Colors.blue.withOpacity(0.1),
      onTap: onTap,
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildRecentActivityCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Activité récente',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildActivityItem(
              Icons.message_outlined,
              'Nouveau message de Jean Dupont',
              'Il y a 2 minutes',
              Colors.blue,
            ),
            _buildActivityItem(
              Icons.person_add_alt_1_outlined,
              'Nouvel utilisateur enregistré',
              'Il y a 1 heure',
              Colors.green,
            ),
            _buildActivityItem(
              Icons.warning_amber_outlined,
              'Problème de connexion détecté',
              'Il y a 3 heures',
              Colors.orange,
            ),
            _buildActivityItem(
              Icons.update_outlined,
              'Mise à jour du système effectuée',
              'Hier',
              Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Date inconnue';
    return DateFormat('dd/MM/yy HH:mm').format(date);
  }

  Map<String, dynamic> _extractMessageInfo(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final type = (data['type'] as String?) ?? 'text';
    final isAudio = type == 'audio';
    final text = (data['text'] as String?)?.trim() ?? '';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final categories = (data['categories'] as List?)?.cast<String>() ?? [];
    final recipients =
        (data['recipientUserIds'] as List?)?.cast<String>() ?? [];

    final audience = recipients.isNotEmpty
        ? 'Destinataire direct'
        : (categories.isNotEmpty ? categories.join(', ') : 'Tous');

    final preview = isAudio
        ? 'Message vocal'
        : (text.isEmpty ? 'Message texte' : text);

    final icon = isAudio ? Icons.graphic_eq : Icons.message_outlined;
    final color = isAudio ? Colors.purple : Colors.blue;
    final label = isAudio ? 'Vocal' : 'Texte';

    return {
      'audience': audience,
      'preview': preview,
      'createdAt': createdAt,
      'icon': icon,
      'color': color,
      'label': label,
    };
  }

  Widget _buildMobileMessageCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final info = _extractMessageInfo(doc);
    final audience = info['audience'] as String;
    final preview = info['preview'] as String;
    final createdAt = info['createdAt'] as DateTime?;
    final icon = info['icon'] as IconData;
    final color = info['color'] as Color;
    final label = info['label'] as String;
    return GestureDetector(
      onLongPress: () {
        _showMobileActionSheet(context, doc.id, preview);
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      preview,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Bouton d'options plus visible
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () =>
                          _showMobileActionSheet(context, doc.id, preview),
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.more_vert,
                          size: 20,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      audience,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(createdAt),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Spacer(),
                  Icon(icon, color: color, size: 16),
                  const SizedBox(width: 4),
                  Text(label, style: TextStyle(fontSize: 12, color: color)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMobileActionSheet(BuildContext context, String id, String subject) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Poignée de la feuille modale
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Options
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text(
                    'Supprimer le message',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context); // Fermer le menu
                    _showDeleteDialog(id, subject);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cancel, color: Colors.grey),
                  title: const Text(
                    'Annuler',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // Vue pour les tablettes/desktop - Ligne de tableau
  DataRow _buildDataRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final info = _extractMessageInfo(doc);
    final audience = info['audience'] as String;
    final preview = info['preview'] as String;
    final createdAt = info['createdAt'] as DateTime?;
    final icon = info['icon'] as IconData;
    final color = info['color'] as Color;
    final label = info['label'] as String;
    return DataRow(
      key: ValueKey(doc.id),
      cells: [
        DataCell(Text(audience)),
        DataCell(Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis)),
        DataCell(Text(_formatDate(createdAt))),
        DataCell(
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Text(label),
            ],
          ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => _showDeleteDialog(doc.id, preview),
            tooltip: 'Supprimer le message',
          ),
        ),
      ],
    );
  }

  // Affiche une boîte de dialogue de confirmation avant la suppression
  Future<void> _showDeleteDialog(String messageId, String messageTitle) async {
    return showDialog<void>(
      context: context,
      barrierDismissible:
          false, // L'utilisateur doit appuyer sur un bouton pour fermer
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmer la suppression'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'Voulez-vous vraiment supprimer le message "$messageTitle" ?',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cette action est irréversible.',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Annuler'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text(
                'Supprimer',
                style: TextStyle(color: Colors.red),
              ),
              onPressed: () {
                _deleteMessage(messageId);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Message supprimé avec succès'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // Fonction pour supprimer un message
  Future<void> _deleteMessage(String messageId) async {
    try {
      // Suppression du message dans Firestore
      await FirebaseFirestore.instance
          .collection('messages')
          .doc(messageId)
          .delete();

      // Mettre à jour l'interface utilisateur si nécessaire
      if (mounted) {
        setState(() {
          // La liste des messages sera automatiquement mise à jour grâce au StreamBuilder
        });

        // Afficher un message de confirmation
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message supprimé avec succès'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la suppression: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildActivityItem(
    IconData icon,
    String title,
    String time,
    Color color,
  ) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        time,
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: Colors.grey,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
    );
  }
}
