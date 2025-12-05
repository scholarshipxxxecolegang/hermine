import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  State<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'all';
  final List<String> _categories = ['all', 'parent', 'eleve', 'enseignant'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Search and filter bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Rechercher un utilisateur...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _categories.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(cat == 'all' ? 'Tous' : cat),
                          selected: isSelected,
                          showCheckmark: true,
                          avatar: isSelected ? const Icon(Icons.check, size: 16) : null,
                          onSelected: (selected) {
                            setState(() => _selectedCategory = cat);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // Users list
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.red.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text('Erreur: ${snapshot.error}'),
                      ],
                    ),
                  );
                }

                final allDocs = snapshot.data?.docs ?? [];
                final searchTerm = _searchController.text.toLowerCase();

                // Filter by category
                var filteredDocs = allDocs.where((doc) {
                  if (_selectedCategory != 'all') {
                    final data = doc.data();
                    final category = (data['category'] ?? data['role'] ?? '')
                        .toString()
                        .toLowerCase();
                    if (category != _selectedCategory.toLowerCase()) {
                      return false;
                    }
                  }
                  return true;
                }).toList();

                // Filter by search term
                if (searchTerm.isNotEmpty) {
                  filteredDocs = filteredDocs.where((doc) {
                    final data = doc.data();
                    final name =
                        [
                              data['firstName'],
                              data['lastName'],
                              data['username'],
                              data['displayName'],
                              data['phone'],
                              data['email'],
                            ]
                            .where((e) => e != null)
                            .map((e) => e.toString().toLowerCase())
                            .join(' ');
                    return name.contains(searchTerm);
                  }).toList();
                }

                // Group by category
                final grouped =
                    <
                      String,
                      List<QueryDocumentSnapshot<Map<String, dynamic>>>
                    >{};
                for (final doc in filteredDocs) {
                  final data = doc.data();
                  final cat = (data['category'] ?? data['role'] ?? 'non défini')
                      .toString();
                  grouped.putIfAbsent(cat, () => []).add(doc);
                }

                if (filteredDocs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Aucun utilisateur trouvé',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Essayez de modifier votre recherche',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: grouped.length,
                  itemBuilder: (context, index) {
                    final category = grouped.keys.elementAt(index);
                    final users = grouped[category]!;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: _getCategoryColor(category),
                          child: Text(
                            users.length.toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        title: Text(category),
                        subtitle: Text('${users.length} utilisateur(s)'),
                        children: users.map((doc) {
                          final data = doc.data();
                          final firstName = data['firstName'] ?? '';
                          final lastName = data['lastName'] ?? '';
                          final username = data['username'] ?? '';
                          final displayName = data['displayName'] ?? '';
                          final phone = data['phone'] ?? '';
                          final email = data['email'] ?? '';

                          String name = username.isNotEmpty
                              ? username
                              : displayName.isNotEmpty
                              ? displayName
                              : [firstName, lastName]
                                    .where((e) => e.toString().isNotEmpty)
                                    .join(' ');
                          if (name.isEmpty) name = phone;
                          if (name.isEmpty) name = email;
                          if (name.isEmpty) name = 'Utilisateur';

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getCategoryColor(
                                category,
                              ).withOpacity(0.2),
                              child: Icon(
                                Icons.person,
                                color: _getCategoryColor(category),
                              ),
                            ),
                            title: Text(name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (phone.isNotEmpty) Text('📱 $phone'),
                                if (email.isNotEmpty) Text('✉️ $email'),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.info_outline),
                              onPressed: () {
                                _showUserDetails(context, data, name);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'parent':
        return Colors.blue;
      case 'eleve':
      case 'élève':
        return Colors.green;
      case 'enseignant':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  void _showUserDetails(
    BuildContext context,
    Map<String, dynamic> data,
    String name,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: _getCategoryColor(
                        data['category'] ?? '',
                      ).withOpacity(0.2),
                      child: Icon(
                        Icons.person,
                        size: 32,
                        color: _getCategoryColor(data['category'] ?? ''),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Chip(
                            label: Text(data['category'] ?? data['role'] ?? ''),
                            avatar: CircleAvatar(
                              backgroundColor: _getCategoryColor(
                                data['category'] ?? '',
                              ),
                              radius: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 32),
                _buildDetailRow(
                  context,
                  'Prénom',
                  data['firstName']?.toString() ?? 'Non renseigné',
                ),
                _buildDetailRow(
                  context,
                  'Nom',
                  data['lastName']?.toString() ?? 'Non renseigné',
                ),
                _buildDetailRow(
                  context,
                  'Téléphone',
                  data['phone']?.toString() ?? 'Non renseigné',
                ),
                _buildDetailRow(
                  context,
                  'Email',
                  data['email']?.toString() ?? 'Non renseigné',
                ),
                _buildDetailRow(
                  context,
                  'SMS Opt-in',
                  (data['smsOptIn'] ?? true) ? 'Oui' : 'Non',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}
