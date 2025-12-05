import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SentMessagesHistoryScreen extends StatelessWidget {
  const SentMessagesHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final adminId = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Historique des messages envoyés')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('sent_messages_history')
            .where('adminId', isEqualTo: adminId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Aucun message envoyé'));
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data();
              final type = data['type'] ?? 'text';
              final text = data['text'] ?? '';
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
              return ListTile(
                leading: Icon(type == 'audio' ? Icons.mic : Icons.message),
                title: Text(type == 'audio' ? 'Message vocal' : text,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: createdAt != null
                    ? Text('${createdAt.day}/${createdAt.month}/${createdAt.year} à ${createdAt.hour}h${createdAt.minute.toString().padLeft(2, '0')}')
                    : null,
                onTap: () => _showMessageDetail(context, data),
              );
            },
          );
        },
      ),
    );
  }

  void _showMessageDetail(BuildContext context, Map<String, dynamic> data) {
    final type = data['type'] ?? 'text';
    final text = data['text'] ?? '';
    final duration = data['durationSec'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(type == 'audio' ? 'Message vocal' : 'Message texte'),
        content: type == 'audio'
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mic, size: 40, color: Colors.blueAccent),
                  if (duration != null) Text('Durée : ${duration}s'),
                  const SizedBox(height: 12),
                  const Text('Lecture audio non implémentée ici.'),
                ],
              )
            : Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}
