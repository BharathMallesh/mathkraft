import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../services/api_service.dart';

class ResultDetailScreen extends StatefulWidget {
  final Map<String, dynamic> submission;

  const ResultDetailScreen({super.key, required this.submission});

  @override
  State<ResultDetailScreen> createState() => _ResultDetailScreenState();
}

class _ResultDetailScreenState extends State<ResultDetailScreen> {
  List<dynamic> _answers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAnswers();
  }

  Future<void> _loadAnswers() async {
    try {
      final data = await ApiService.get('/submissions/${widget.submission['id']}/answers');
      setState(() { _answers = data is List ? data : []; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Color _errorColor(String? type) {
    switch (type) {
      case 'conceptual_gap': return Colors.red;
      case 'calculation_slip': return Colors.orange;
      case 'logical_fallacy': return Colors.purple;
      default: return Colors.green;
    }
  }

  String _errorLabel(String? type) {
    switch (type) {
      case 'conceptual_gap': return 'Conceptual Gap';
      case 'calculation_slip': return 'Calculation Slip';
      case 'logical_fallacy': return 'Logical Fallacy';
      default: return 'Correct';
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.submission['total_marks'] ?? 0;
    final awarded = widget.submission['total_marks_awarded'] ?? 0;
    final pct = total > 0 ? (awarded / total * 100).toStringAsFixed(1) : '0.0';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(widget.submission['title'] ?? 'Results'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _ScoreBanner(awarded: awarded, total: total, pct: pct),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _answers.length,
                    itemBuilder: (context, i) {
                      final ans = _answers[i] as Map<String, dynamic>;
                      final correct = ans['marks_awarded'] == ans['marks'];
                      final errorType = ans['error_type'] as String?;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E2E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: correct ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Text('Q${i + 1}', style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  Text(ans['topic'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                  const Spacer(),
                                  Text('${ans['marks_awarded']}/${ans['marks']}', style: TextStyle(color: correct ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Math.tex(
                                (ans['latex_body'] ?? '').length > 100
                                    ? '${ans['latex_body'].substring(0, 100)}...'
                                    : ans['latex_body'] ?? '',
                                textStyle: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                            ),
                            if (!correct && errorType != null) ...[
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _errorColor(errorType).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: _errorColor(errorType).withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.analytics_outlined, color: _errorColor(errorType), size: 14),
                                      const SizedBox(width: 6),
                                      Text(_errorLabel(errorType), style: TextStyle(color: _errorColor(errorType), fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (ans['teacher_feedback'] != null && (ans['teacher_feedback'] as String).isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.comment_outlined, color: Colors.white38, size: 14),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text(ans['teacher_feedback'], style: const TextStyle(color: Colors.white54, fontSize: 12))),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _ScoreBanner extends StatelessWidget {
  final int awarded;
  final int total;
  final String pct;

  const _ScoreBanner({required this.awarded, required this.total, required this.pct});

  @override
  Widget build(BuildContext context) {
    final score = double.tryParse(pct) ?? 0;
    final color = score >= 70 ? Colors.green : score >= 40 ? Colors.orange : Colors.red;

    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF1E1E2E),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            children: [
              Text('$awarded', style: TextStyle(color: color, fontSize: 48, fontWeight: FontWeight.bold)),
              Text('out of $total', style: const TextStyle(color: Colors.white54)),
            ],
          ),
          const SizedBox(width: 32),
          Column(
            children: [
              Text('$pct%', style: TextStyle(color: color, fontSize: 36, fontWeight: FontWeight.bold)),
              Text(score >= 70 ? 'Excellent!' : score >= 40 ? 'Keep Practicing' : 'Needs Work', style: TextStyle(color: color.withValues(alpha: 0.7))),
            ],
          ),
        ],
      ),
    );
  }
}
