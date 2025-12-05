import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:telephony/telephony.dart';
import '../services/sms_service.dart';
import '../config.dart';

class ComposeMessageScreen extends StatefulWidget {
  // initialRecipient: {id, name, phone}
  final Map<String, dynamic>? initialRecipient;

  const ComposeMessageScreen({super.key, this.initialRecipient});

  @override
  State<ComposeMessageScreen> createState() => _ComposeMessageScreenState();
}

class _ComposeMessageScreenState extends State<ComposeMessageScreen> {
  final List<String> _allCategories = const ['parent', 'eleve', 'enseignant'];
  final Set<String> _selected = {'parent'};
  final TextEditingController _textCtrl = TextEditingController();
  final TextEditingController _classCtrl = TextEditingController();
  bool _sending = false;
  bool _sendAlsoSms = false;
  bool _individualMode = false;
  Map<String, dynamic>? _singleRecipient; // {id, name, phone}
  final Set<String> _deletingMessageIds = {};

  // Audio state
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isUploadingAudio = false;
  DateTime? _recordStart;
  String? _audioError;
  int _elapsedSec = 0;
  Timer? _recordTimer;

  final telephony = Telephony.instance;

  @override
  void initState() {
    super.initState();
    _ensureSmsPermissions();
    // If opened with an initial recipient, set individual mode
    if (widget.initialRecipient != null) {
      _individualMode = true;
      _singleRecipient = widget.initialRecipient;
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _textCtrl.dispose();
    _classCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<bool> _ensureSmsPermissions() async {
    final smsStatus = await Permission.sms.status;
    final phoneStatus = await Permission.phone.status;
    if (smsStatus.isGranted && phoneStatus.isGranted) return true;
    final results = await [Permission.sms, Permission.phone].request();
    final granted = (results[Permission.sms]?.isGranted ?? false) &&
        (results[Permission.phone]?.isGranted ?? false);
    if (!granted) {
      _showSnackBar("Erreur : autorisez l'accès SMS et téléphone pour envoyer des messages par SMS.");
    }
    return granted;
  }

  Future<void> _sendTextMessage() async {
    if (!_individualMode && _selected.isEmpty) {
      _showSnackBar('Sélectionnez au moins une catégorie');
      return;
    }
    if (_individualMode && _singleRecipient == null) {
      _showSnackBar('Choisissez un destinataire');
      return;
    }
    if (_textCtrl.text.trim().isEmpty) {
      _showSnackBar('Le message ne peut pas être vide');
      return;
    }

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer l\'envoi'),
        content: Text(
          'Envoyer ce message à ${_selected.length} catégorie(s) ?\n\n${_selected.join(", ")}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _sending = true);
    try {
      final data = <String, dynamic>{
        'senderId': FirebaseAuth.instance.currentUser?.uid,
        'type': 'text',
        'text': _textCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (_individualMode && _singleRecipient != null) {
        data['recipientUserIds'] = [_singleRecipient!['id']];
      } else {
        data['categories'] = _selected.toList();

        // Ciblage optionnel des parents d'une classe donnée
        final targetClass = _classCtrl.text.trim();
        final bool targetParentsByClass =
            targetClass.isNotEmpty && _selected.contains('parent');

        if (targetParentsByClass) {
          final qs = await FirebaseFirestore.instance
              .collection('users')
              .where('category', isEqualTo: 'parent')
              .where('studentClass', isEqualTo: targetClass)
              .get();

          final ids = qs.docs.map((d) => d.id).toList();
          if (ids.isNotEmpty) {
            data['recipientUserIds'] = ids;
            data['targetClass'] = targetClass;
          }
        }
      }

      final msgRef = await FirebaseFirestore.instance.collection('messages').add(data);
      // Historique d'envoi pour l'admin
      await FirebaseFirestore.instance.collection('sent_messages_history').add({
        'adminId': FirebaseAuth.instance.currentUser?.uid,
        'messageId': msgRef.id,
        'type': 'text',
        'text': _textCtrl.text.trim(),
        'categories': _individualMode ? null : _selected.toList(),
        'recipientUserIds': data['recipientUserIds'],
        'targetClass': data['targetClass'],
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (_sendAlsoSms) {
        await _sendSmsBatch(_textCtrl.text.trim());
      }

      _textCtrl.clear();
      _classCtrl.clear();
      _showSnackBar('Message envoyé avec succès', isError: false);

      // If we were opened from a reception doc (reply flow), try to mark it handled.
      try {
        final recId = _singleRecipient != null ? _singleRecipient!['id'] as String? : null;
        if (recId != null) {
          await FirebaseFirestore.instance.collection('reception').doc(recId).update({
            'handled': true,
            'handledBy': FirebaseAuth.instance.currentUser?.uid,
            'handledAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        // ignore errors - it's optional and not critical if the id is not a reception doc
      }
    } on FirebaseException catch (e) {
      String message;
      switch (e.code) {
        case 'unavailable':
        case 'network-error':
          message = "Erreur : connectez-vous à internet pour envoyer un message.";
          break;
        case 'permission-denied':
          message = "Vous n'avez pas la permission d'envoyer ce message.";
          break;
        default:
          message = e.message ?? "Erreur inconnue lors de l'envoi du message.";
      }
      _showSnackBar(message);
    } on SocketException {
      _showSnackBar("Erreur : connectez-vous à internet pour envoyer un message.");
    } catch (e) {
      _showSnackBar('Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendSmsBatch(String message) async {
    // Individual mode: send to one phone only
    if (_individualMode && _singleRecipient != null) {
      final phone = (_singleRecipient!['phone'] as String?)?.trim();
      if (phone == null || phone.isEmpty) {
        _showSnackBar('Le destinataire n\'a pas de numéro');
        return;
      }
      final sent = await SmsService.sendBatchSms(
        phones: [phone],
        message: message,
      );
      _showSnackBar('SMS envoyé au destinataire', isError: sent == 0);
      return;
    }

    // Categories mode: build phones list from selection
    final qs = await FirebaseFirestore.instance
        .collection('users')
        .where('category', whereIn: _selected.toList())
        .get();

    final phones = <String>[];
    for (final d in qs.docs) {
      final m = d.data();
      final phone = (m['phone'] as String?)?.trim();
      final optIn = (m['smsOptIn'] as bool?) ?? true;
      if (optIn && phone != null && phone.isNotEmpty) {
        phones.add(phone);
      }
    }

    if (phones.isEmpty) return;

    final sent = await SmsService.sendBatchSms(
      phones: phones,
      message: message,
    );

    _showSnackBar(
      'SMS envoyés à $sent/${phones.length} destinataires',
      isError: sent == 0,
    );
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
      setState(() => _audioError = 'Erreur : autorisez l\'accès au micro pour enregistrer un message vocal.');
      _showSnackBar("Erreur : autorisez l'accès au micro pour enregistrer un message vocal.");
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
        _elapsedSec = 0;
      });

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
        if (!mounted) return;
        final secs = DateTime.now().difference(_recordStart!).inSeconds;
        setState(() => _elapsedSec = secs);
        if (secs >= 120) {
          await _stopAndUploadAudio();
        }
      });
    } catch (e) {
      setState(() => _audioError = 'Erreur enregistrement: $e');
    }
  }

  Future<void> _stopAndUploadAudio() async {
    try {
      _recordTimer?.cancel();
      final path = await _recorder.stop();
      setState(() => _isRecording = false);
      if (path == null) return;

      final file = File(path);
      if (!file.existsSync()) return;

      final secs = _recordStart != null
          ? DateTime.now().difference(_recordStart!).inSeconds
          : null;
      setState(() => _isUploadingAudio = true);

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
      // Historique d'envoi pour l'admin (audio)
      await FirebaseFirestore.instance.collection('sent_messages_history').add({
        'adminId': FirebaseAuth.instance.currentUser?.uid,
        'messageId': msgRef.id,
        'type': 'audio',
        'categories': _selected.toList(),
        'durationSec': secs,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final url = await _uploadToCloudinary(file);
      await msgRef.update({'audioUrl': url});

      // If replying to a reception doc, mark it handled
      try {
        final recId = _singleRecipient != null ? _singleRecipient!['id'] as String? : null;
        if (recId != null) {
          await FirebaseFirestore.instance.collection('reception').doc(recId).update({
            'handled': true,
            'handledBy': FirebaseAuth.instance.currentUser?.uid,
            'handledAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        // ignore
      }

      _showSnackBar('Vocal envoyé avec succès', isError: false);
    } catch (e) {
      if (mounted) setState(() => _audioError = 'Erreur upload: $e');
      _showSnackBar('Erreur upload: $e');
    } finally {
      if (mounted) setState(() => _isUploadingAudio = false);
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openRecipientPicker() async {
    String query = '';
    QuerySnapshot<Map<String, dynamic>>? result;
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredDocs = [];
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateBS) {
            Future<void> _search() async {
              try {
                // Essayer d'abord avec les keywords (optimisé)
                try {
                  final snap = await FirebaseFirestore.instance
                      .collection('users')
                      .where('keywords', arrayContains: query.toLowerCase())
                      .limit(25)
                      .get();
                  setStateBS(() {
                    result = snap;
                    filteredDocs = snap.docs;
                  });
                  return;
                } catch (e) {
                  // Si l'index n'existe pas, faire une recherche simple
                  debugPrint('Recherche avec keywords échouée, utilisation de la recherche textuelle');
                }
                
                // Fallback: récupérer tous les utilisateurs et filtrer localement
                final snap = await FirebaseFirestore.instance
                    .collection('users')
                    .limit(100)
                    .get();
                
                final queryLower = query.toLowerCase();
                final filtered = snap.docs.where((doc) {
                  final data = doc.data();
                  final firstName = (data['firstName'] ?? '').toString().toLowerCase();
                  final lastName = (data['lastName'] ?? '').toString().toLowerCase();
                  final username = (data['username'] ?? '').toString().toLowerCase();
                  final displayName = (data['displayName'] ?? '').toString().toLowerCase();
                  final phone = (data['phone'] ?? '').toString();
                  
                  return firstName.contains(queryLower) ||
                      lastName.contains(queryLower) ||
                      username.contains(queryLower) ||
                      displayName.contains(queryLower) ||
                      phone.contains(queryLower);
                }).toList();
                
                setStateBS(() {
                  result = snap;
                  filteredDocs = filtered;
                });
              } catch (e) {
                debugPrint('Erreur de recherche: $e');
                setStateBS(() {
                  result = null;
                  filteredDocs = [];
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Nom, téléphone…',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) {
                          query = v.trim();
                          if (query.length >= 2) {
                            _search();
                          } else {
                            setStateBS(() {
                              result = null;
                              filteredDocs = [];
                            });
                          }
                        },
                      ),
                    ),
                    if (result == null)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Tapez au moins 2 caractères…'),
                      )
                    else if (filteredDocs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucun utilisateur trouvé'),
                      )
                    else
                      SizedBox(
                        height: 360,
                        child: ListView(
                          children: filteredDocs.map((d) {
                            final m = d.data();
                            final firstName = (m['firstName'] ?? '').toString();
                            final lastName = (m['lastName'] ?? '').toString();
                            final username = (m['username'] ?? '').toString();
                            final displayName = (m['displayName'] ?? '')
                                .toString();
                            final phone = (m['phone'] ?? '').toString();
                            String name = displayName.isNotEmpty
                                ? displayName
                                : (username.isNotEmpty
                                      ? username
                                      : [
                                          firstName,
                                          lastName,
                                        ].where((e) => e.isNotEmpty).join(' '));
                            if (name.isEmpty)
                              name = phone.isNotEmpty ? phone : 'Utilisateur';
                            return ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.person),
                              ),
                              title: Text(name),
                              subtitle: phone.isNotEmpty ? Text(phone) : null,
                              onTap: () {
                                _singleRecipient = {
                                  'id': d.id,
                                  'name': name,
                                  'phone': phone,
                                };
                                Navigator.of(context).pop();
                                setState(() {});
                              },
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteMessage(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final type = (data['type'] as String?) ?? 'text';
    final preview = type == 'text'
        ? ((data['text'] as String?) ?? '').trim()
        : 'Message vocal';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le message ?'),
        content: Text(
          preview.isEmpty
              ? 'Cette action supprimera définitivement le message.'
              : 'Cette action supprimera définitivement le message :\n\n$preview',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Supprimer'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
      setState(() => _deletingMessageIds.add(doc.id));
    }

    try {
      await FirebaseFirestore.instance
          .collection('messages')
          .doc(doc.id)
          .delete();
      _showSnackBar('Message supprimé', isError: false);
    } catch (e) {
      _showSnackBar('Erreur suppression: $e');
    } finally {
      if (mounted) {
        setState(() => _deletingMessageIds.remove(doc.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {});
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode d'envoi
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Type d\'envoi',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Switch(
                          value: _individualMode,
                          onChanged: (v) {
                            setState(() {
                              _individualMode = v;
                              if (!v) _singleRecipient = null;
                            });
                          },
                        ),
                        Text(_individualMode ? 'Individuel' : 'Par catégories'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_individualMode) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_search),
                        title: Text(
                          _singleRecipient == null
                              ? 'Choisir un destinataire'
                              : (_singleRecipient!['name'] as String? ??
                                    'Utilisateur'),
                        ),
                        subtitle: Text(
                          _singleRecipient == null
                              ? 'Recherche par nom, téléphone...'
                              : (_singleRecipient!['phone'] as String? ?? ''),
                        ),
                        trailing: OutlinedButton.icon(
                          onPressed: _openRecipientPicker,
                          icon: const Icon(Icons.search),
                          label: const Text('Rechercher'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Catégories
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Diffusion par catégories',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _allCategories.map((c) {
                        final selected = _selected.contains(c);
                        return FilterChip(
                          label: Text(c),
                          selected: selected,
                          onSelected: _individualMode
                              ? null
                              : (v) {
                                  setState(() {
                                    if (v) {
                                      _selected.add(c);
                                    } else {
                                      _selected.remove(c);
                                    }
                                  });
                                },
                          // FilterChip has no 'enabled' named param in some versions
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    if (!_individualMode && _selected.contains('parent'))
                      TextField(
                        controller: _classCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Classe (parents uniquement)',
                          hintText: 'Ex: 3e A',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Message texte
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Message texte',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _textCtrl,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        hintText: 'Votre message...',
                        prefixIcon: Icon(Icons.message_outlined),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Envoyer aussi par SMS'),
                      subtitle: const Text(
                        'Routage MTN/Airtel selon vos préférences',
                      ),
                      value: _sendAlsoSms,
                      onChanged: (v) => setState(() => _sendAlsoSms = v),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            !_sending &&
                                _textCtrl.text.trim().isNotEmpty &&
                                ((!_individualMode && _selected.isNotEmpty) ||
                                    (_individualMode &&
                                        _singleRecipient != null))
                            ? _sendTextMessage
                            : null,
                        icon: _sending
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                        label: const Text('Envoyer'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Message vocal
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Message vocal (120s max)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_audioError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _audioError!,
                                style: TextStyle(color: Colors.red.shade700),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _isUploadingAudio ? null : _toggleRecord,
                          icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                          label: Text(
                            _isRecording ? 'Arrêter et envoyer' : 'Enregistrer',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _isRecording ? Colors.red : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (_isRecording)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.mic,
                                  size: 16,
                                  color: Colors.red.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$_elapsedSec / 120 s',
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_isUploadingAudio) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          const Text('Upload...'),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Derniers messages
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Derniers messages envoyés',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () => setState(() {}),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 240,
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('messages')
                            .orderBy('createdAt', descending: true)
                            .limit(10)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final docs = snapshot.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return const Center(
                              child: Text('Aucun message pour le moment'),
                            );
                          }
                          return ListView.separated(
                            itemCount: docs.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final m = docs[index].data();
                              final type = m['type'] as String? ?? 'text';
                              final cats = (m['categories'] as List?)?.join(
                                ', ',
                              );
                              final createdAt = (m['createdAt'] as Timestamp?)
                                  ?.toDate();
                              final subtitle = type == 'text'
                                  ? (m['text'] as String? ?? '')
                                  : 'Audio';
                              final docId = docs[index].id;
                              final isDeleting = _deletingMessageIds.contains(
                                docId,
                              );
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: type == 'text'
                                      ? Colors.blue.shade100
                                      : Colors.purple.shade100,
                                  child: Icon(
                                    type == 'text'
                                        ? Icons.message
                                        : Icons.graphic_eq,
                                    color: type == 'text'
                                        ? Colors.blue.shade700
                                        : Colors.purple.shade700,
                                  ),
                                ),
                                title: Text(cats ?? ''),
                                subtitle: Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: SizedBox(
                                  width: 112,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              createdAt != null
                                                  ? TimeOfDay.fromDateTime(
                                                      createdAt,
                                                    ).format(context)
                                                  : '',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                            if (createdAt != null)
                                              Text(
                                                '${createdAt.day}/${createdAt.month}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: Colors.grey,
                                                      fontSize: 10,
                                                    ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      if (isDeleting)
                                        const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      else
                                        PopupMenuButton<String>(
                                          tooltip: 'Actions',
                                          icon: const Icon(Icons.more_vert),
                                          onSelected: (value) {
                                            if (value == 'delete') {
                                              _confirmDeleteMessage(
                                                docs[index],
                                              );
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: const [
                                                  Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.red,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text('Supprimer'),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
