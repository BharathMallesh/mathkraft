import 'package:flutter/material.dart';
import '../../widgets/math_text.dart';
import '../../services/api_service.dart';
import 'add_question_screen.dart';
import 'grade_submissions_screen.dart';
import 'pdf_upload_screen.dart';
import 'stored_papers_screen.dart';

class ExamDetailScreen extends StatefulWidget {
  final Map<String, dynamic> exam;

  const ExamDetailScreen({super.key, required this.exam});

  @override
  State<ExamDetailScreen> createState() => _ExamDetailScreenState();
}

class _ExamDetailScreenState extends State<ExamDetailScreen> {
  Map<String, dynamic>? _examData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExam();
  }

  Future<void> _loadExam() async {
    try {
      final data = await ApiService.get('/exams/${widget.exam['id']}');
      setState(() { _examData = data; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _publishExam() async {
    await ApiService.patch('/exams/${widget.exam['id']}/publish', {});
    _loadExam();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exam published to students!'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final questions = _examData?['questions'] as List? ?? [];
    final isPublished = _examData?['is_published'] == true;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(widget.exam['title'] ?? '', style: const TextStyle(fontSize: 15)),
        actions: [
          if (!isPublished && questions.isNotEmpty)
            TextButton(
              onPressed: _publishExam,
              child: const Text('Publish', style: TextStyle(color: Color(0xFFFF6F00))),
            ),
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => GradeSubmissionsScreen(examId: widget.exam['id']),
            )),
            icon: const Icon(Icons.grading),
            tooltip: 'Grade Submissions',
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'stored',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => StoredPapersScreen(
                examId: widget.exam['id'],
                examTitle: widget.exam['title'] ?? '',
              )),
            ).then((_) => _loadExam()),
            backgroundColor: const Color(0xFF37474F),
            tooltip: 'Reuse Stored Paper',
            child: const Icon(Icons.folder_open, color: Colors.white),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'pdf',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PdfUploadScreen(
                examId: widget.exam['id'],
                examTitle: widget.exam['title'] ?? '',
              )),
            ).then((saved) { if (saved == true) _loadExam(); }),
            backgroundColor: const Color(0xFF1B5E20),
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            label: const Text('Upload PDF', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'manual',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AddQuestionScreen(
                examId: widget.exam['id'],
                questionNumber: questions.length + 1,
              )),
            ).then((added) { if (added == true) _loadExam(); }),
            backgroundColor: const Color(0xFFFF6F00),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Add Manually', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _ExamSummaryBar(exam: _examData ?? widget.exam, questionCount: questions.length),
                Expanded(
                  child: questions.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.quiz_outlined, color: Colors.white24, size: 64),
                              SizedBox(height: 16),
                              Text('No questions yet', style: TextStyle(color: Colors.white54, fontSize: 16)),
                              SizedBox(height: 8),
                              Text('Tap + to add your first question', style: TextStyle(color: Colors.white38, fontSize: 13)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: questions.length,
                          itemBuilder: (context, i) => _QuestionCard(
                            question: questions[i],
                            index: i,
                            onDelete: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: const Color(0xFF1E1E2E),
                                  title: const Text('Delete Question?', style: TextStyle(color: Colors.white)),
                                  content: Text(
                                    'Q${i + 1} will be permanently deleted.',
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
                              if (confirm == true) {
                                await ApiService.delete('/questions/${questions[i]['id']}');
                                _loadExam();
                              }
                            },
                            onEdit: () async {
                              final updated = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AddQuestionScreen(
                                    examId: widget.exam['id'],
                                    questionNumber: i + 1,
                                    existingQuestion: questions[i] as Map<String, dynamic>,
                                  ),
                                ),
                              );
                              if (updated == true) _loadExam();
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _ExamSummaryBar extends StatelessWidget {
  final Map<String, dynamic> exam;
  final int questionCount;

  const _ExamSummaryBar({required this.exam, required this.questionCount});

  @override
  Widget build(BuildContext context) {
    final isPublished = exam['is_published'] == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF1E1E2E),
      child: Row(
        children: [
          _StatBadge(label: 'Questions', value: '$questionCount'),
          const SizedBox(width: 16),
          _StatBadge(label: 'Duration', value: '${exam['duration_minutes']}m'),
          const SizedBox(width: 16),
          _StatBadge(label: 'Type', value: exam['exam_type'] ?? 'mock'),
          const SizedBox(width: 16),
          _StatBadge(
            label: 'Class',
            value: exam['target_class'] == 'all' || exam['target_class'] == null ? 'All' : 'Std ${exam['target_class']}',
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isPublished ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isPublished ? 'Live' : 'Draft',
              style: TextStyle(color: isPublished ? Colors.green : Colors.orange, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;

  const _StatBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final Map<String, dynamic> question;
  final int index;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _QuestionCard({required this.question, required this.index, required this.onDelete, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final type = question['type'] ?? 'mcq';
    final typeColors = {'mcq': Colors.blue, 'numerical': Colors.purple, 'proof': Colors.orange};

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Q${index + 1}', style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (typeColors[type] ?? Colors.grey).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(type.toUpperCase(), style: TextStyle(color: typeColors[type] ?? Colors.grey, fontSize: 10)),
              ),
              const SizedBox(width: 8),
              Text(question['topic'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              const Spacer(),
              Text('${question['marks']} pts', style: const TextStyle(color: Color(0xFFFF6F00), fontSize: 12)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onEdit,
                child: const Icon(Icons.edit_outlined, color: Colors.white38, size: 18),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onDelete,
                child: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          MathText(
            text: question['latex_body'] ?? '',
            textStyle: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          if (type == 'mcq' && question['options'] != null) ...[
            const SizedBox(height: 8),
            const Divider(color: Colors.white12),
            ...((question['options'] as List).map((opt) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    opt['is_correct'] == true ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: opt['is_correct'] == true ? Colors.green : Colors.white24,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text('(${opt['option_label']}) ', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  Expanded(
                    child: Text(
                      opt['latex_option'] ?? '',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ))),
          ],
        ],
      ),
    );
  }
}
