import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'pdf_upload_screen.dart';

class StoredPapersScreen extends StatefulWidget {
  final String examId;
  final String examTitle;

  const StoredPapersScreen({
    super.key,
    required this.examId,
    required this.examTitle,
  });

  @override
  State<StoredPapersScreen> createState() => _StoredPapersScreenState();
}

class _StoredPapersScreenState extends State<StoredPapersScreen> {
  List<dynamic> _papers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPapers();
  }

  Future<void> _loadPapers() async {
    try {
      final data = await ApiService.get('/pdf/papers');
      setState(() {
        _papers = data is List ? data : [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load papers: $e')),
        );
      }
    }
  }

  Future<void> _deletePaper(Map<String, dynamic> paper) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Delete Paper?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${paper['title']}"? This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await ApiService.delete('/pdf/papers/${paper['id']}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paper deleted'), backgroundColor: Colors.green),
        );
        _loadPapers();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _reparseAndUse(Map<String, dynamic> paper) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Reuse This Paper', style: TextStyle(color: Colors.white)),
        content: Text(
          'Re-parse "${paper['title']}" and import its questions into ${widget.examTitle}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Re-parsing paper...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    try {
      final result = await ApiService.post('/pdf/papers/${paper['id']}/reparse', {});
      if (!mounted) return;
      Navigator.pop(context); // close loading

      final questions = result['questions'] as List? ?? [];
      if (questions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No questions could be parsed from this paper')),
        );
        return;
      }

      // Navigate to PDF upload screen in review mode with pre-parsed questions
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfUploadScreen(
            examId: widget.examId,
            examTitle: widget.examTitle,
            preloadedPaperId: paper['id'].toString(),
            preloadedQuestions: questions,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reparse: $e')),
        );
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Stored Question Papers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _loading = true);
              _loadPapers();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _papers.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf, color: Colors.white12, size: 64),
                      SizedBox(height: 16),
                      Text('No papers stored yet', style: TextStyle(color: Colors.white54, fontSize: 16)),
                      SizedBox(height: 8),
                      Text('Upload a PDF to store it for reuse', style: TextStyle(color: Colors.white38, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _papers.length,
                  itemBuilder: (context, i) {
                    final paper = _papers[i] as Map<String, dynamic>;
                    final isLinked = paper['exam_id'] != null;
                    final qCount = paper['questions_extracted'] ?? 0;
                    final pages = paper['pages'] ?? 0;
                    final sizeKb = paper['file_size_kb'] ?? 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isLinked
                              ? Colors.green.withValues(alpha: 0.3)
                              : Colors.white12,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A237E).withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.picture_as_pdf, color: Color(0xFFFF6F00), size: 24),
                        ),
                        title: Text(
                          paper['title'] ?? 'Untitled Paper',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _InfoChip(label: '$qCount questions'),
                                const SizedBox(width: 6),
                                _InfoChip(label: '$pages pages'),
                                const SizedBox(width: 6),
                                _InfoChip(label: '${sizeKb}KB'),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  _formatDate(paper['uploaded_at']),
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                                if (isLinked) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Used in: ${paper['exam_title'] ?? 'Exam'}',
                                      style: const TextStyle(color: Colors.green, fontSize: 10),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A237E),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              onPressed: () => _reparseAndUse(paper),
                              child: const Text('Import', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _deletePaper(paper),
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                              tooltip: 'Delete Paper',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
    );
  }
}
