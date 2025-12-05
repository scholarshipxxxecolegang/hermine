import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  String _selectedCategory = 'parent';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des utilisateurs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showUserForm(context),
            tooltip: 'Ajouter',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                const Text('Catégorie :'),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _selectedCategory,
                  items: const [
                    DropdownMenuItem(value: 'parent', child: Text('Parent')),
                    DropdownMenuItem(value: 'eleve', child: Text('Élève')),
                    DropdownMenuItem(value: 'enseignant', child: Text('Enseignant')),
                  ],
                  onChanged: (v) => setState(() => _selectedCategory = v!),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('category', isEqualTo: _selectedCategory)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('Aucun utilisateur'));
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data();
                    final name = data['displayName'] ?? data['firstName'] ?? 'Utilisateur';
                    final phone = data['phone'] ?? '';
                    return ListTile(
                      title: Text(name),
                      subtitle: Text(phone),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _showUserForm(context, doc: docs[i]),
                            tooltip: 'Éditer',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _confirmDeleteUser(docs[i]),
                            tooltip: 'Supprimer',
                          ),
                        ],
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

  void _showUserForm(BuildContext context, {QueryDocumentSnapshot<Map<String, dynamic>>? doc}) {
    final isEdit = doc != null;
    final data = doc?.data() ?? {};
    final _formKey = GlobalKey<FormState>();
    final TextEditingController firstNameCtrl =
        TextEditingController(text: data['firstName'] ?? '');
    final TextEditingController lastNameCtrl =
        TextEditingController(text: data['lastName'] ?? '');
    final TextEditingController emailCtrl =
        TextEditingController(text: data['email'] ?? '');
    final TextEditingController phoneCtrl =
        TextEditingController(text: data['phone'] ?? '');
    final TextEditingController passwordCtrl =
        TextEditingController(text: '');
    String category = data['category'] ?? data['role'] ?? _selectedCategory;

    // Champs spécifiques selon la catégorie
    final TextEditingController parentOfCtrl = TextEditingController(
      text: data['parentOf'] ?? '',
    );
    final TextEditingController studentClassCtrl = TextEditingController(
      text: data['studentClass'] ?? '',
    );
    final TextEditingController subjectCtrl = TextEditingController(
      text: data['subject'] ?? '',
    );
    final TextEditingController classesCtrl = TextEditingController(
      text: (data['classes'] is List)
          ? (data['classes'] as List)
              .whereType<String>()
              .toList()
              .join(', ')
          : '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'Éditer utilisateur' : 'Ajouter utilisateur'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: lastNameCtrl,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (v) => v == null || v.isEmpty ? 'Nom requis' : null,
              ),
              TextFormField(
                controller: firstNameCtrl,
                decoration: const InputDecoration(labelText: 'Prénom'),
                validator: (v) => v == null || v.isEmpty ? 'Prénom requis' : null,
              ),
              TextFormField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Téléphone'),
                keyboardType: TextInputType.phone,
                validator: (v) => v == null || v.isEmpty ? 'Téléphone requis' : null,
              ),
              TextFormField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email (obligatoire)'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v == null || v.trim().isEmpty ? 'Email requis' : null,
              ),
              if (!isEdit) ...[
                TextFormField(
                  controller: passwordCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mot de passe provisoire',
                    hintText: '8 caractères minimum',
                  ),
                  obscureText: true,
                  validator: (v) => !isEdit && (v == null || v.length < 8) 
                      ? '8 caractères minimum' 
                      : null,
                ),
              ],
              DropdownButtonFormField<String>(
                value: category,
                items: const [
                  DropdownMenuItem(value: 'parent', child: Text('Parent')),
                  DropdownMenuItem(value: 'eleve', child: Text('Élève')),
                  DropdownMenuItem(value: 'enseignant', child: Text('Enseignant')),
                ],
                onChanged: (v) => category = v!,
                decoration: const InputDecoration(labelText: 'Catégorie'),
              ),
              const SizedBox(height: 8),
              if (category == 'parent') ...[
                TextFormField(
                  controller: parentOfCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Parent de…',
                    hintText: 'Ex: Jean Dupont',
                  ),
                ),
                TextFormField(
                  controller: studentClassCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Classe de l\'élève',
                    hintText: 'Ex: 3e A',
                  ),
                ),
              ] else if (category == 'enseignant') ...[
                TextFormField(
                  controller: subjectCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Matière',
                    hintText: 'Ex: Mathématiques',
                  ),
                ),
                TextFormField(
                  controller: classesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Classes (séparées par des virgules)',
                    hintText: 'Ex: 3e A, 4e B',
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!_formKey.currentState!.validate()) return;
              try {
                final first = firstNameCtrl.text.trim();
                final last = lastNameCtrl.text.trim();
                final displayName = [first, last]
                    .where((e) => e.isNotEmpty)
                    .join(' ')
                    .trim();

                // Générer des keywords similaires au sign up
                final keywords = <String>{};
                if (first.isNotEmpty) {
                  keywords.add(first.toLowerCase());
                  for (int i = 1; i <= first.length; i++) {
                    keywords.add(first.toLowerCase().substring(0, i));
                  }
                }
                if (last.isNotEmpty) {
                  keywords.add(last.toLowerCase());
                  for (int i = 1; i <= last.length; i++) {
                    keywords.add(last.toLowerCase().substring(0, i));
                  }
                }
                final phone = phoneCtrl.text.trim();
                if (phone.isNotEmpty) {
                  keywords.add(phone);
                }

                final Map<String, dynamic> userData = {
                  'firstName': first,
                  'lastName': last,
                  'displayName': displayName.isNotEmpty
                      ? displayName
                      : emailCtrl.text.trim(),
                  'username': displayName.isNotEmpty
                      ? displayName
                      : emailCtrl.text.trim(),
                  'phone': phone.isEmpty ? null : phone,
                  'email': emailCtrl.text.trim().isEmpty
                      ? null
                      : emailCtrl.text.trim(),
                  'category': category,
                  'role': category,
                  'keywords': keywords.toList(),
                };

                if (category == 'parent') {
                  userData['parentOf'] = parentOfCtrl.text.trim().isEmpty
                      ? null
                      : parentOfCtrl.text.trim();
                  userData['studentClass'] = studentClassCtrl.text.trim().isEmpty
                      ? null
                      : studentClassCtrl.text.trim();
                } else if (category == 'enseignant') {
                  userData['subject'] = subjectCtrl.text.trim().isEmpty
                      ? null
                      : subjectCtrl.text.trim();
                  final classesText = classesCtrl.text.trim();
                  if (classesText.isNotEmpty) {
                    userData['classes'] = classesText
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                  }
                }

                if (isEdit) {
                  await doc!.reference.update(userData);
                } else {
                  await _createUserWithAdminRights({
                    ...userData,
                    'password': passwordCtrl.text.trim(),
                    'email': emailCtrl.text.trim(),
                  });
                }

                if (context.mounted) {
                  Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erreur : ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Text(isEdit ? 'Enregistrer' : 'Ajouter'),
          ),
        ],
      ),
    );
  }

  Future<void> _createUserWithAdminRights(Map<String, dynamic> userData) async {
  try {
    final String apiKey = 'AIzaSyDdB79uf2CzF1QAATUXkf0vWFlFkDSuwWo'; // À remplacer par ta clé API Firebase
    final String email = userData['email'];
    final String password = userData['password'];
    
    // 1. Créer l'utilisateur dans Firebase Auth
      final authResponse = await http.post(
        Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      if (authResponse.statusCode == 200) {
        final authData = jsonDecode(authResponse.body);
        final String uid = authData['localId'];
        
        // 2. Créer le document dans Firestore
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'uid': uid,
          'email': email,
          'firstName': userData['firstName'],
          'lastName': userData['lastName'],
          'phone': userData['phone'],
          'category': userData['category'],
          'role': userData['category'],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final error = jsonDecode(authResponse.body);
        throw Exception(error['error']['message'] ?? 'Erreur inconnue');
      }
    } catch (e) {
      print('Erreur lors de la création de l\'utilisateur: $e');
      rethrow;
    }
  }

  void _confirmDeleteUser(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer utilisateur'),
        content: const Text('Voulez-vous vraiment supprimer cet utilisateur ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await doc.reference.delete();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
