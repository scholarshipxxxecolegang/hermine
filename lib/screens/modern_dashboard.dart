import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'compose_message_screen.dart';
import 'user_management_screen.dart';
import 'stats_screen.dart';
import 'settings_screen.dart';
import 'feed_screen_admin.dart';
import 'reception_screen.dart';
import 'sent_messages_history_screen.dart';

class ModernDashboard extends StatefulWidget {
  const ModernDashboard({super.key});

  @override
  State<ModernDashboard> createState() => _ModernDashboardState();
}

class _ModernDashboardState extends State<ModernDashboard> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const FeedScreenAdmin(),
    const ReceptionScreen(),
    const ComposeMessageScreen(),
    const UserManagementScreen(),
    const StatsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: IndexedStack(index: _currentIndex, children: _screens),
        ),
      ),
      bottomNavigationBar: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('reception')
            .where('handled', isEqualTo: false)
            .snapshots(),
        builder: (context, snap) {
          final unread = snap.data?.docs.length ?? 0;
          return NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() => _currentIndex = index);
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.dynamic_feed_outlined, color: Colors.blueAccent),
                selectedIcon: Icon(Icons.dynamic_feed, color: Colors.blueGrey,),
                label: ' ',
              ),
              NavigationDestination(
                icon: Stack(
                  children: [
                    const Icon(Icons.inbox_outlined, color: Colors.blueAccent),
                    if (unread > 0)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: CircleAvatar(
                          radius: 8,
                          backgroundColor: Colors.red,
                          child: Text(
                            unread > 99 ? '99+' : unread.toString(),
                            style: const TextStyle(fontSize: 9, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
                selectedIcon: Stack(
                  children: [
                    const Icon(Icons.inbox, color: Colors.blueGrey,),
                    if (unread > 0)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: CircleAvatar(
                          radius: 8,
                          backgroundColor: Colors.red,
                          child: Text(
                            unread > 99 ? '99+' : unread.toString(),
                            style: const TextStyle(fontSize: 9, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
                label: ' ',
              ),
              const NavigationDestination(
                icon: Icon(Icons.message_outlined, color: Colors.blueAccent),
                selectedIcon: Icon(Icons.message, color: Colors.blueGrey,),
                label: ' ',
              ),
              const NavigationDestination(
                icon: Icon(Icons.people_outline, color: Colors.blueAccent),
                selectedIcon: Icon(Icons.people, color: Colors.blueGrey,),
                label: ' ',
              ),
              const NavigationDestination(
                icon: Icon(Icons.analytics_outlined, color: Colors.blueAccent,),
                selectedIcon: Icon(Icons.analytics, color: Colors.blueGrey,),
                label: ' ',
              ),
            ],
          );
        },
      ),
      appBar: AppBar(
        title: const Text('Hermine Admin'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            onSelected: (value) {
              if (value == 'logout') {
                FirebaseAuth.instance.signOut();
              } else if (value == 'settings') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              } else if (value == 'history') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SentMessagesHistoryScreen()),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'history',
                child: Row(
                  children:  [
                    Icon(Icons.history),
                    SizedBox(width: 8),
                    Text('Historique messages'),
                  ],
                ),
              ),
               PopupMenuDivider(),
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children:  [
                    Icon(Icons.person),
                    SizedBox(width: 8),
                    Text('Profil'),
                  ],
                ),
              ),
               PopupMenuDivider(),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children:  [
                    Icon(Icons.settings),
                    SizedBox(width: 8),
                    Text('Paramètres'),
                  ],
                ),
              ),
               PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children:  [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Déconnexion', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
