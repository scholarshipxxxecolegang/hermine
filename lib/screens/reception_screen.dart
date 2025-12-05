import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hermine_admin/screens/ChatScreen.dart';
import 'compose_message_screen.dart';

class ReceptionScreen extends StatefulWidget {
  final String? conversationId;

  const ReceptionScreen({super.key, this.conversationId});

  @override
  State<ReceptionScreen> createState() => _ReceptionScreenState();
}

class _ReceptionScreenState extends State<ReceptionScreen> {
  String _getOtherParticipant(Map<String, dynamic> conversationData) {
    final participants = List<String>.from(conversationData['participants'] ?? []);
    return participants.firstWhere((p) => p != 'admin', orElse: () => 'Inconnu');
  }

  Future<String> _getUserName(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        return userData['displayName'] as String? ?? 
               userData['username'] as String? ?? 
               userData['email'] as String? ?? 
               'Utilisateur $userId';
      }
      return 'Utilisateur $userId';
    } catch (e) {
      debugPrint('Erreur lors de la récupération du nom utilisateur: $e');
      return 'Utilisateur $userId';
    }
  }

  Widget _buildConversationCard(String conversationId, Map<String, dynamic> conversationData) {
    final participants = List<String>.from(conversationData['participants'] ?? []);
    final otherUserId = participants.firstWhere((p) => p != 'admin', orElse: () => 'Inconnu');
    final lastMessage = conversationData['lastMessage'] ?? '';
    final lastUpdated = (conversationData['lastUpdated'] as Timestamp?)?.toDate();

    return FutureBuilder<String>(
      future: _getUserName(otherUserId),
      builder: (context, snapshot) {
        final userName = snapshot.data ?? 'Chargement...';

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              child: Text(userName.isNotEmpty ? userName[0].toUpperCase() : 'U'),
            ),
            title: Text('Conversation avec $userName'),
            subtitle: Text(
              lastMessage.isNotEmpty ? lastMessage : 'Aucun message',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: lastUpdated != null
                ? Text(
                    '${lastUpdated.hour}:${lastUpdated.minute.toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : null,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    conversationId: conversationId,
                    title: 'Conversation avec $userName',
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Réception'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('conversations')
          .where('participants', arrayContains: 'admin')
          .orderBy('lastUpdated', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          debugPrint('Erreur StreamBuilder: ${snapshot.error}');
          return Center(child: Text('Erreur: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];
        debugPrint('Nombre de conversations: ${docs.length}');

        if (docs.isEmpty) {
          return const Center(child: Text('Aucune conversation trouvée'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final conversationDoc = docs[index];
            final conversationData = conversationDoc.data();
            final conversationId = conversationDoc.id;
            
            return _buildConversationCard(conversationId, conversationData);
          },
        );
      },
    ),
    );
  }
}


