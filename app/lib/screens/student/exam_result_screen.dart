import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../widgets/math_text.dart';

class ExamResultScreen extends StatelessWidget {
  final Map<String, dynamic> submission;
  final List<dynamic> answers;
  final String examTitle;

  const ExamResultScreen({
    super.key,
    required this.submission,
    required this.answers,
    required this.examTitle,
  });

  Color _scoreColor(double pct) {
    if (pct >= 70) return Colors.green;
    if (pct >= 40) return Colors.orange;
    return Colors.red;
  }

  String _scoreLabel(double pct) {
    if (pct >= 90) return 'Outstanding!';
    if (pct >= 70) return 'Well Done!';
    if (pct >= 40) return 'Keep Practicing';
    return 'Needs More Work';
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

  IconData _errorIcon(String? type) {
    switch (type) {
      case 'conceptual_gap': return Icons.psychology_outlined;
      case 'calculation_slip': return Icons.calculate_outlined;
      case 'logical_fallacy': return Icons.account_tree_outlined;
      default: return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final awarded = (submission['total_marks_awarded'] ?? 0) as num;
    final total = (submission['total_marks'] ?? 0) as num;
    final pct = total > 0 ? (awarded / total * 100).toDouble() : 0.0;
    final color = _scoreColor(pct);

    final correct = answers.where((a) => (a['marks_awarded'] ?? 0) == (a['marks'] ?? 0) && (a['marks'] ?? 0) > 0).length;
    final wrong = answers.where((a) => (a['marks_awarded'] ?? 0) == 0 && (a['type'] != 'proof')).length;
    final pending = answers.where((a) => a['type'] == 'proof' && a['is_graded'] != true).length;

    // Topic-wise breakdown
    final Map<String, Map<String, int>> topicStats = {};
    for (final a in answers) {
      final topic = a['topic'] ?? 'General';
      topicStats.putIfAbsent(topic, () => {'awarded': 0, 'total': 0});
      topicStats[topic]!['awarded'] = topicStats[topic]!['awarded']! + ((a['marks_awarded'] ?? 0) as num).toInt();
      topicStats[topic]!['total'] = topicStats[topic]!['total']! + ((a['marks'] ?? 0) as num).toInt();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        automaticallyImplyLeading: false,
        title: Text(examTitle, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            child: const Text('Home', style: TextStyle(color: Color(0xFFFF6F00))),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Score banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.4), width: 2)),
              ),
              child: Column(
                children: [
                  Text(
                    '${pct.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: color),
                  ),
                  Text(
                    _scoreLabel(pct),
                    style: TextStyle(fontSize: 20, color: color, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$awarded out of $total marks',
                    style: const TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  // Score breakdown row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatBadge(value: '$correct', label: 'Correct', color: Colors.green),
                      _StatBadge(value: '$wrong', label: 'Wrong', color: Colors.red),
                      if (pending > 0)
                        _StatBadge(value: '$pending', label: 'Pending', color: Colors.orange),
                      _StatBadge(value: '${answers.length}', label: 'Total', color: Colors.white54),
                    ],
                  ),
                ],
              ),
            ),

            // Topic-wise performance
            if (topicStats.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Topic Performance', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              ...topicStats.entries.map((e) {
                final topicPct = e.value['total']! > 0
                    ? e.value['awarded']! / e.value['total']!
                    : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E2E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(e.key, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                            Text(
                              '${e.value['awarded']}/${e.value['total']}',
                              style: TextStyle(color: _scoreColor(topicPct * 100), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: topicPct,
                            backgroundColor: Colors.white12,
                            color: _scoreColor(topicPct * 100),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],

            // Per-question breakdown
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Question Breakdown', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            ...answers.asMap().entries.map((e) {
              final i = e.key;
              final ans = e.value as Map<String, dynamic>;
              final marksAwarded = (ans['marks_awarded'] ?? 0) as num;
              final marksTotal = (ans['marks'] ?? 0) as num;
              final isCorrect = marksAwarded == marksTotal && marksTotal > 0;
              final isProof = ans['type'] == 'proof';
              final isPending = isProof && ans['is_graded'] != true;
              final errorType = ans['error_type'] as String?;

              return Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isPending
                        ? Colors.orange.withValues(alpha: 0.3)
                        : isCorrect
                            ? Colors.green.withValues(alpha: 0.3)
                            : Colors.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isPending
                                  ? Colors.orange.withValues(alpha: 0.2)
                                  : isCorrect
                                      ? Colors.green.withValues(alpha: 0.2)
                                      : Colors.red.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              isPending ? Icons.hourglass_empty : isCorrect ? Icons.check : Icons.close,
                              color: isPending ? Colors.orange : isCorrect ? Colors.green : Colors.red,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('Q${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Text(ans['topic'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                          const Spacer(),
                          Text(
                            isPending ? 'Pending' : '$marksAwarded/$marksTotal',
                            style: TextStyle(
                              color: isPending ? Colors.orange : isCorrect ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: MathText(
                        text: ans['latex_body'] ?? '',
                        textStyle: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    // Error type badge
                    if (!isCorrect && !isPending && errorType != null) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_errorIcon(errorType), color: _errorColor(errorType), size: 14),
                            const SizedBox(width: 6),
                            Text(_errorLabel(errorType), style: TextStyle(color: _errorColor(errorType), fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                    // Teacher feedback
                    if (ans['teacher_feedback'] != null && (ans['teacher_feedback'] as String).isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.comment_outlined, color: Colors.white38, size: 13),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(ans['teacher_feedback'], style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              );
            }),

            // Study plan suggestion
            if (pct < 70) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1A237E)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lightbulb_outline, color: Color(0xFFFF6F00), size: 18),
                          SizedBox(width: 8),
                          Text('Study Plan', style: TextStyle(color: Color(0xFFFF6F00), fontWeight: FontWeight.bold, fontSize: 15)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Weak topics
                      ...topicStats.entries
                          .where((e) => e.value['total']! > 0 && e.value['awarded']! / e.value['total']! < 0.5)
                          .map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                const Icon(Icons.arrow_right, color: Colors.white54, size: 16),
                                Text('Focus on ${e.key}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                              ],
                            ),
                          )),
                      if (pct < 40)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text('Review fundamental concepts before the next attempt.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Back to Home', style: TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatBadge({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}
