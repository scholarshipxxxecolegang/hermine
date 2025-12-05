import 'package:flutter/material.dart';

class PostMediaCarousel extends StatefulWidget {
  final List<String> urls;
  const PostMediaCarousel({super.key, required this.urls});

  @override
  State<PostMediaCarousel> createState() => _PostMediaCarouselState();
}

class _PostMediaCarouselState extends State<PostMediaCarousel> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openViewer(int initialPage) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PostMediaViewer(urls: widget.urls, initialIndex: initialPage),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => _openViewer(_index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 4 / 5,
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: widget.urls.length,
                itemBuilder: (context, i) {
                  final url = widget.urls[i];
                  final provider = NetworkImage(url);
                  return Hero(
                    tag: url,
                    child: Image(
                      image: provider,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stack) =>
                          const Center(child: Text("Impossible d'afficher l'image")),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (widget.urls.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.urls.length, (i) {
              final active = i == _index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 6,
                width: active ? 18 : 6,
                decoration: BoxDecoration(
                  color: active ? Colors.blueAccent : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
      ],
    );
  }
}

class PostMediaViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const PostMediaViewer({super.key, required this.urls, this.initialIndex = 0});

  @override
  State<PostMediaViewer> createState() => _PostMediaViewerState();
}

class _PostMediaViewerState extends State<PostMediaViewer> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    // Evict images from the in-memory cache to avoid keeping them in phone RAM
    for (final u in widget.urls) {
      try {
        NetworkImage(u).evict();
      } catch (_) {}
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black87),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        itemBuilder: (context, i) {
          final url = widget.urls[i];
          final provider = NetworkImage(url);
          return InteractiveViewer(
            child: Center(
              child: Hero(
                tag: url,
                child: Image(
                  image: provider,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                  errorBuilder: (context, error, stack) => const Center(
                      child: Text("Impossible d'afficher l'image", style: TextStyle(color: Colors.white))),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
