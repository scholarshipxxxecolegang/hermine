import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String title;

  const ChatScreen({super.key, required this.conversationId, required this.title});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('conversations')
            .doc(widget.conversationId)
            .collection('messages')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erreur: ${snapshot.error}'));
          }

          final messages = snapshot.data?.docs ?? [];
          if (messages.isEmpty) {
            return const Center(child: Text('Aucun message'));
          }

          return ListView.builder(
            reverse: true, // Pour afficher les messages du plus récent au plus ancien
            padding: const EdgeInsets.all(12),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index].data();
              final senderId = message['senderId'] ?? '';
              final text = message['text'] ?? '';
              final createdAt = (message['createdAt'] as Timestamp?)?.toDate();

              return MessageBubble(
                senderId: senderId,
                text: text,
                createdAt: createdAt,
                isAdmin: senderId == 'admin',
              );
            },
          );
        },
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final String senderId;
  final String text;
  final DateTime? createdAt;
  final bool isAdmin;

  const MessageBubble({
    super.key,
    required this.senderId,
    required this.text,
    required this.createdAt,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isAdmin ? Colors.blue : Colors.grey[300],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: TextStyle(
                  color: isAdmin ? Colors.white : Colors.black,
                ),
              ),
              if (createdAt != null)
                Text(
                  '${createdAt!.hour}:${createdAt!.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isAdmin ? Colors.white70 : Colors.black54,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}