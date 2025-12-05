import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:hermine_admin/services/cloudinary_service.dart';
import 'package:hermine_admin/widgets/post_media_carousel.dart';
import 'package:cloud_functions/cloud_functions.dart';

class FeedScreenAdmin extends StatefulWidget {
  const FeedScreenAdmin({super.key});

  @override
  State<FeedScreenAdmin> createState() => _FeedScreenAdminState();
}

class _FeedScreenAdminState extends State<FeedScreenAdmin> {
  List<File> _selectedImages = [];
  final TextEditingController _postController = TextEditingController();
  bool _isPosting = false;
  String _query = '';

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage(imageQuality: 80);
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _selectedImages = pickedFiles.map((x) => File(x.path)).toList();
      });
    }
  }

  Future<void> _addPost() async {
    if (_postController.text.isEmpty && _selectedImages.isEmpty) return;
    setState(() => _isPosting = true);
    try {
      // Capture navigator and messenger before any await to avoid
      // `use_build_context_synchronously` analyzer warnings.
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);

      final user = FirebaseAuth.instance.currentUser;
      final mediaUrls = <String>[];
      final mediaPublicIds = <String>[];

      // Upload images to Cloudinary
      for (final image in _selectedImages) {
        final uploadResponse = await CloudinaryService.instance.uploadImage(image);
        if (uploadResponse != null) {
          mediaUrls.add(uploadResponse.secureUrl);
          if (uploadResponse.publicId.isNotEmpty) mediaPublicIds.add(uploadResponse.publicId);
        }
      }

      // Add post to Firestore
      await FirebaseFirestore.instance.collection('posts').add({
        'userId': user?.uid,
        'authorName': user?.displayName ?? 'Admin',
        'authorPhotoUrl': user?.photoURL,
        'text': _postController.text.trim(),
        'mediaUrls': mediaUrls,
        'mediaPublicIds': mediaPublicIds,
        'createdAt': FieldValue.serverTimestamp(),
        'likes': [],
        'comments': [],
        'commentsCount': 0,
      });

      setState(() {
        _selectedImages = [];
        _postController.clear();
        _isPosting = false;
      });

      // Use captured navigator/messenger (safe across async gaps)
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('✅ Publication réussie!')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
      setState(() => _isPosting = false);
    }
  }

  void _showAddPostDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _postController,
                  decoration: const InputDecoration(
                    labelText: 'Écrire quelque chose...',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                if (_selectedImages.isNotEmpty)
                  SizedBox(
                    height: 140,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedImages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          _selectedImages[i],
                          height: 140,
                          width: 140,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.image),
                      onPressed: _pickImages,
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: _isPosting ? null : _addPost,
                      child: _isPosting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Publier'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Toggle like for a post (adds/removes current uid in the 'likes' array)
  Future<void> _toggleLike(String postId, bool isLiked) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final postRef = FirebaseFirestore.instance.collection('posts').doc(postId);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(postRef);
        final data = snapshot.data() ?? {};
        final likes = List<String>.from(data['likes'] ?? []);
        if (isLiked) {
          likes.remove(currentUser.uid);
        } else {
          if (!likes.contains(currentUser.uid)) likes.add(currentUser.uid);
        }
        transaction.update(postRef, {'likes': likes});
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur like: $e')),
        );
      }
    }
  }

  // Show comments sheet for a post
  void _showCommentsSheet(BuildContext context, String postId) {
    final TextEditingController commentController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    'Commentaires',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('posts').doc(postId).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final comments = List<Map<String, dynamic>>.from(snapshot.data?['comments'] ?? []);
                  if (comments.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.comment_outlined, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text('Aucun commentaire pour le moment', style: TextStyle(color: Colors.grey[600])),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      final c = comments[index];
                      final text = c['text'] ?? '';
                      final uid = c['userId'] ?? '';
                      final createdAt = c['createdAt'];
                      final timestamp = createdAt is Timestamp ? createdAt.toDate() : DateTime.now();
                      return ListTile(
                        title: Text(text),
                        subtitle: Text('$uid • ${timestamp.toString()}'),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey[300]!))),
              padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: commentController,
                      decoration: InputDecoration(hintText: 'Ajouter un commentaire...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), filled: true, fillColor: Colors.grey[100], contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                      minLines: 1,
                      maxLines: 3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    onPressed: () async {
                      final text = commentController.text.trim();
                      final currentUser = FirebaseAuth.instance.currentUser;
                      if (text.isEmpty || currentUser == null) return;
                      final postRef = FirebaseFirestore.instance.collection('posts').doc(postId);
                      await FirebaseFirestore.instance.runTransaction((transaction) async {
                        final snapshot = await transaction.get(postRef);
                        List<dynamic> comments = [];
                        if (snapshot.exists && snapshot.data() != null && snapshot.data()!.containsKey('comments')) {
                          final raw = snapshot['comments'];
                          if (raw is List) comments = List.from(raw);
                        }
                        comments.add({'userId': currentUser.uid, 'text': text, 'createdAt': FieldValue.serverTimestamp()});
                        transaction.update(postRef, {'comments': comments, 'commentsCount': FieldValue.increment(1)});
                      });
                      commentController.clear();
                    },
                    child: const Icon(Icons.send, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Report dialog and submission
  void _showReportDialog(BuildContext context, String postId) {
    final reasons = ['Contenu offensant', 'Spam', 'Contenu violent', 'Partage de données privées', 'Autre'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Signaler cette publication'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Pourquoi signalez-vous cette publication?'), const SizedBox(height: 12), ...reasons.map((r) => ListTile(title: Text(r), onTap: () { Navigator.pop(context); _submitReport(postId, r); })).toList()]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler'))],
      ),
    );
  }

  Future<void> _submitReport(String postId, String reason) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      await FirebaseFirestore.instance.collection('reports').add({'postId': postId, 'reportedBy': currentUser.uid, 'reason': reason, 'createdAt': FieldValue.serverTimestamp(), 'status': 'pending'});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Merci de votre signalement.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur lors du signalement: $e')));
    }
  }

  // Confirm deletion dialog
  void _confirmDelete(String postId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la publication'),
        content: const Text('Voulez-vous vraiment supprimer cette publication ? Cette action est irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deletePost(postId);
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // Delete a post document
  Future<void> _deletePost(String postId) async {
    try {
      final postRef = FirebaseFirestore.instance.collection('posts').doc(postId);
      final doc = await postRef.get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        final publicIds = List<String>.from(data['mediaPublicIds'] ?? []);
        // Fallback: try to extract last path segment from mediaUrls
        if (publicIds.isEmpty && data['mediaUrls'] is List) {
          final urls = List<String>.from(data['mediaUrls']);
          for (final u in urls) {
            try {
              final parts = u.split('/');
              final last = parts.isNotEmpty ? parts.last : '';
              if (last.isNotEmpty) {
                // remove extension
                final dot = last.lastIndexOf('.');
                final pid = dot > 0 ? last.substring(0, dot) : last;
                publicIds.add(pid);
              }
            } catch (_) {}
          }
        }

        // Call Cloud Function to delete images if any
        if (publicIds.isNotEmpty) {
          try {
            // Use callable function
            // Import at top: cloud_functions package
            // Using lazy import here to avoid unused import lint if package missing
            final functions = FirebaseFunctions.instance;
            await functions.httpsCallable('deleteCloudinaryImages').call({
              'publicIds': publicIds,
            });
          } catch (e) {
            debugPrint('Erreur suppression images Cloudinary: $e');
          }
        }

        // Finally delete the post document
        await postRef.delete();
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Publication supprimée')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur suppression: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fil d\'actualité')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Rechercher...',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Erreur: \\${snapshot.error}'));
                }
                var docs = snapshot.data?.docs ?? [];
                if (_query.isNotEmpty) {
                  docs = docs.where((d) {
                    final m = d.data();
                    final t = (m['text'] as String?)?.toLowerCase() ?? '';
                    final a = (m['authorName'] as String?)?.toLowerCase() ?? '';
                    return t.contains(_query) || a.contains(_query);
                  }).toList();
                }
                if (docs.isEmpty) {
                  return const Center(child: Text('Aucune publication \n\t\tconnecter vous a internet .........'));
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final text = data['text'] as String? ?? '';
                    // Support multiple images like the client app and fall back to legacy keys
                    List<String> mediaUrls = (data['mediaUrls'] as List<dynamic>?)
                            ?.map((e) => e as String)
                            .toList() ?? [];
                    if (mediaUrls.isEmpty &&
                        data['mediaUrl'] is String &&
                        (data['mediaUrl'] as String).isNotEmpty) {
                      mediaUrls = [data['mediaUrl'] as String];
                    }
                    final String? imageUrl = mediaUrls.isNotEmpty
                        ? mediaUrls.first
                        : data['imageUrl'] as String?;
                    final authorName = data['authorName'] as String? ?? 'Utilisateur';
                    final authorPhotoUrl = data['authorPhotoUrl'] as String?;
                    final likes = List<String>.from(data['likes'] ?? []);
                    final comments = List<Map<String, dynamic>>.from(data['comments'] ?? []);
                    final commentsCount = (data['commentsCount'] as int?) ?? comments.length;
                    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                    final postId = docs[index].id;
                    final currentUser = FirebaseAuth.instance.currentUser;
                    final isLiked = currentUser != null && likes.contains(currentUser.uid);
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              leading: CircleAvatar(
                                backgroundImage: authorPhotoUrl != null ? NetworkImage(authorPhotoUrl) : null,
                                child: authorPhotoUrl == null ? const Icon(Icons.person) : null,
                              ),
                              title: Text(authorName),
                              subtitle: createdAt != null
                                  ? Text('${createdAt.day}/${createdAt.month}/${createdAt.year} à ${createdAt.hour}h${createdAt.minute.toString().padLeft(2, '0')}')
                                  : null,
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                onPressed: () => _confirmDelete(postId),
                                tooltip: 'Supprimer la publication',
                              ),
                            ),
                            // Media (carousel or single image)
                            if (mediaUrls.isNotEmpty)
                              PostMediaCarousel(urls: mediaUrls),
                            if (mediaUrls.isEmpty && imageUrl != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AspectRatio(
                                  aspectRatio: 4 / 5,
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return const Center(child: CircularProgressIndicator());
                                    },
                                    errorBuilder: (context, error, stack) =>
                                        const Center(child: Text("Impossible d'afficher l'image")),
                                  ),
                                ),
                              ),
                            if (text.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                child: Text(text),
                              ),
                            ],

                            // Action buttons: Like, Comment, Report
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton.icon(
                                    style: TextButton.styleFrom(foregroundColor: isLiked ? Colors.blueAccent : null),
                                    onPressed: currentUser == null ? null : () => _toggleLike(postId, isLiked),
                                    icon: Icon(isLiked ? Icons.thumb_up : Icons.thumb_up_off_alt),
                                    label: Text('${likes.length}'),
                                  ),
                                ),
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: () => _showCommentsSheet(context, postId),
                                    icon: const Icon(Icons.comment_outlined),
                                    label: Text('$commentsCount'),
                                  ),
                                ),
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: () => _showReportDialog(context, postId),
                                    icon: const Icon(Icons.flag_outlined, color: Colors.redAccent),
                                    label: const Text('Signaler'),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPostDialog,
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}
