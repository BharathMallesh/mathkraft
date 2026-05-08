import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../services/api_service.dart';

class GradeSubmissionsScreen extends StatefulWidget {
  final String examId;

  const GradeSubmissionsScreen({super.key, required this.examId});

  @override
  State<GradeSubmissionsScreen> createState() => _GradeSubmissionsScreenState();
}

class _GradeSubmissionsScreenState extends State<GradeSubmissionsScreen> {
  List<dynamic> _submissions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  Future<void> _loadSubmissions() async {
    try {
      final data = await ApiService.get('/submissions/exam/${widget.examId}');
      setState(() { _submissions = data is List ? data : []; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Student Submissions'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _submissions.isEmpty
              ? const Center(child: Text('No submissions yet', style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _submissions.length,
                  itemBuilder: (context, i) {
                    final sub = _submissions[i];
                    return GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => GradeDetailScreen(submission: sub),
                      )).then((_) => _loadSubmissions()),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E2E),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(backgroundColor: Color(0xFF1A237E), child: Icon(Icons.person, color: Colors.white)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(sub['student_name'] ?? 'Student', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  Text(sub['status'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${sub['total_marks_awarded']}', style: const TextStyle(color: Color(0xFFFF6F00), fontSize: 18, fontWeight: FontWeight.bold)),
                                const Text('marks', style: TextStyle(color: Colors.white38, fontSize: 11)),
                              ],
                            ),
                            const SizedBox(width: 8),
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

class GradeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> submission;

  const GradeDetailScreen({super.key, required this.submission});

  @override
  State<GradeDetailScreen> createState() => _GradeDetailScreenState();
}

class _GradeDetailScreenState extends State<GradeDetailScreen> {
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

  Future<void> _gradeAnswer(String answerId, int marks, String errorType, String feedback) async {
    await ApiService.patch('/submissions/answer/$answerId/grade', {
      'marks_awarded': marks,
      'error_type': errorType,
      'teacher_feedback': feedback,
    });
    _loadAnswers();
  }

  void _showGradeDialog(Map<String, dynamic> answer) {
    final marksCtrl = TextEditingController(text: '${answer['marks_awarded'] ?? 0}');
    final feedbackCtrl = TextEditingController(text: answer['teacher_feedback'] ?? '');
    String errorType = answer['error_type'] ?? 'conceptual_gap';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2E),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16, left: 16, right: 16, top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Grade Answer', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: marksCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Marks Awarded', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            StatefulBuilder(builder: (ctx, setS) => DropdownButtonFormField<String>(
              value: errorType,
              decoration: const InputDecoration(labelText: 'Error Type (if wrong)', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'conceptual_gap', child: Text('Conceptual Gap')),
                DropdownMenuItem(value: 'calculation_slip', child: Text('Calculation Slip')),
                DropdownMenuItem(value: 'logical_fallacy', child: Text('Logical Fallacy')),
              ],
              onChanged: (v) => setS(() => errorType = v!),
            )),
            const SizedBox(height: 12),
            TextField(
              controller: feedbackCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Feedback to Student', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _gradeAnswer(answer['id'], int.tryParse(marksCtrl.text) ?? 0, errorType, feedbackCtrl.text);
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Save Grade', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(widget.submission['student_name'] ?? 'Student Answers'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _answers.length,
              itemBuilder: (context, i) {
                final answer = _answers[i] as Map<String, dynamic>;
                final isProof = answer['proof_photo_url'] != null;
                final isGraded = answer['is_graded'] == true;

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E2E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isGraded ? Colors.green.withValues(alpha: 0.3) : Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Question', style: TextStyle(color: Colors.white54, fontSize: 12)),
                            const SizedBox(height: 6),
                            Math.tex(
                              (answer['latex_body'] ?? '').length > 100
                                  ? '${answer['latex_body'].substring(0, 100)}...'
                                  : answer['latex_body'] ?? '',
                              textStyle: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Colors.white12),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Student Answer', style: TextStyle(color: Colors.white54, fontSize: 12)),
                            const SizedBox(height: 6),
                            if (isProof)
                              GestureDetector(
                                onTap: () => _showGradeDialog(answer),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    'https://mathkraft.onrender.com${answer['proof_photo_url']}',
                                    height: 200,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Text('Photo unavailable', style: TextStyle(color: Colors.white38)),
                                  ),
                                ),
                              )
                            else
                              Text(
                                answer['selected_option'] ?? answer['numerical_value']?.toString() ?? '(no answer)',
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                          ],
                        ),
                      ),
                      if (isProof)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => _showGradeDialog(answer),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isGraded ? Colors.green.withValues(alpha: 0.2) : const Color(0xFF1A237E),
                              ),
                              child: Text(
                                isGraded ? 'Graded: ${answer['marks_awarded']} marks' : 'Grade This Answer',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Row(
                            children: [
                              const Icon(Icons.auto_awesome, color: Color(0xFFFF6F00), size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Auto-graded: ${answer['marks_awarded']} marks',
                                style: const TextStyle(color: Color(0xFFFF6F00), fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
