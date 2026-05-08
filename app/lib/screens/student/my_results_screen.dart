import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'exam_result_screen.dart';

class MyResultsScreen extends StatefulWidget {
  const MyResultsScreen({super.key});

  @override
  State<MyResultsScreen> createState() => _MyResultsScreenState();
}

class _MyResultsScreenState extends State<MyResultsScreen> {
  List<dynamic> _results = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    try {
      final data = await ApiService.get('/submissions/my-results');
      setState(() {
        _results = data is List ? data : [];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _openResult(Map<String, dynamic> submission) async {
    try {
      final answers = await ApiService.get('/submissions/${submission['id']}/answers');
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExamResultScreen(
              submission: submission,
              answers: answers is List ? answers : [],
              examTitle: submission['title'] ?? 'Exam',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load result: ${e.toString()}')),
        );
      }
    }
  }

  Color _scoreColor(num awarded, num total) {
    if (total == 0) return Colors.white54;
    final pct = awarded / total * 100;
    if (pct >= 70) return Colors.green;
    if (pct >= 40) return Colors.orange;
    return Colors.red;
  }

  String _scorePercent(num awarded, num total) {
    if (total == 0) return 'Pending';
    return '${(awarded / total * 100).toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Results'),
        backgroundColor: const Color(0xFF1E1E2E),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bar_chart, color: Colors.white12, size: 64),
                      SizedBox(height: 16),
                      Text('No exams attempted yet', style: TextStyle(color: Colors.white54, fontSize: 16)),
                      SizedBox(height: 8),
                      Text('Take an exam to see your results here', style: TextStyle(color: Colors.white38, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final result = _results[i] as Map<String, dynamic>;
                    final awarded = (result['total_marks_awarded'] ?? 0) as num;
                    final total = (result['total_marks'] ?? 0) as num;
                    final color = _scoreColor(awarded, total);
                    final pct = _scorePercent(awarded, total);
                    final status = result['status'] ?? '';

                    return GestureDetector(
                      onTap: () => _openResult(result),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E2E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: color.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            // Score circle
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                                border: Border.all(color: color, width: 2),
                              ),
                              child: Center(
                                child: Text(
                                  pct,
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: pct == 'Pending' ? 9 : 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    result['title'] ?? 'Exam',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$awarded / $total marks',
                                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: status == 'graded'
                                              ? Colors.green.withValues(alpha: 0.2)
                                              : Colors.orange.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          status == 'graded' ? 'Graded' : status == 'submitted' ? 'Submitted' : status,
                                          style: TextStyle(
                                            color: status == 'graded' ? Colors.green : Colors.orange,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
