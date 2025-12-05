import 'package:flutter/material.dart';

/// Widget générique non utilisé, laissé vide pour éviter les erreurs de compilation.
class ConversationCard extends StatelessWidget {
  final Widget child;

  const ConversationCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(child: child);
  }
}

