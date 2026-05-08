import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../widgets/math_text.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../services/api_service.dart';
import 'exam_result_screen.dart';

class ExamScreen extends StatefulWidget {
  final String examId;
  final String examTitle;

  const ExamScreen({super.key, required this.examId, required this.examTitle});

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  Map<String, dynamic>? _exam;
  String? _submissionId;
  bool _loading = true;
  int _currentIndex = 0;
  Timer? _timer;
  int _secondsLeft = 0;
  final Map<String, dynamic> _answers = {};

  @override
  void initState() {
    super.initState();
    _startExam();
  }

  Future<void> _startExam() async {
    try {
      final exam = await ApiService.get('/exams/${widget.examId}');
      final sub = await ApiService.post('/submissions/start', {'exam_id': widget.examId});
      setState(() {
        _exam = exam;
        _submissionId = sub['id'];
        _secondsLeft = (exam['duration_minutes'] ?? 60) * 60;
        _loading = false;
      });
      _startTimer();
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _submitExam();
      }
    });
  }

  Future<void> _submitAnswer(String questionId, Map<String, dynamic> answer) async {
    setState(() => _answers[questionId] = answer);
    await ApiService.post('/submissions/answer', {
      'submission_id': _submissionId,
      'question_id': questionId,
      ...answer,
    });
  }

  Future<void> _submitProofPhoto(String questionId, File photo) async {
    setState(() => _answers[questionId] = {'proof_photo': photo.path});
    await ApiService.uploadFile('/submissions/answer', photo, {
      'submission_id': _submissionId!,
      'question_id': questionId,
    });
  }

  Future<void> _submitExam() async {
    _timer?.cancel();

    // Show submitting indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Submitting exam...'),
            ],
          ),
        ),
      );
    }

    try {
      final submission = await ApiService.post('/submissions/$_submissionId/submit', {});
      final answers = await ApiService.get('/submissions/$_submissionId/answers');

      if (mounted) {
        Navigator.pop(context); // close dialog
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ExamResultScreen(
              submission: submission,
              answers: answers is List ? answers : [],
              examTitle: widget.examTitle,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submission failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _getHint(String questionId) async {
    final data = await ApiService.post('/hints', {
      'question_id': questionId,
      'hint_level': 1,
    });
    if (mounted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1E1E2E),
        builder: (_) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AI Hint', style: TextStyle(color: Color(0xFFFF6F00), fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(data['hint'] ?? '', style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }
  }

  String get _timerText {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final questions = _exam?['questions'] as List? ?? [];
    if (questions.isEmpty) return const Scaffold(body: Center(child: Text('No questions found')));

    final question = questions[_currentIndex] as Map<String, dynamic>;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(widget.examTitle, style: const TextStyle(fontSize: 14)),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _secondsLeft < 300 ? Colors.red : const Color(0xFF1A237E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_timerText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_currentIndex + 1) / questions.length,
            backgroundColor: const Color(0xFF1E1E2E),
            color: const Color(0xFFFF6F00),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Q${_currentIndex + 1} of ${questions.length}  •  ${question['marks']} marks',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  _QuestionBody(question: question),
                  const SizedBox(height: 24),
                  if (question['type'] == 'mcq')
                    _MCQOptions(
                      question: question,
                      selected: _answers[question['id']]?['selected_option'],
                      onSelect: (opt) => _submitAnswer(question['id'], {'selected_option': opt}),
                    )
                  else if (question['type'] == 'numerical')
                    _NumericalInput(
                      value: _answers[question['id']]?['numerical_value']?.toString(),
                      onSubmit: (val) => _submitAnswer(question['id'], {'numerical_value': val}),
                    )
                  else
                    _ProofUpload(
                      photoPath: _answers[question['id']]?['proof_photo'],
                      onUpload: (file) => _submitProofPhoto(question['id'], file),
                    ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => _getHint(question['id']),
                    icon: const Icon(Icons.lightbulb_outline, color: Color(0xFFFF6F00)),
                    label: const Text('Get AI Hint', style: TextStyle(color: Color(0xFFFF6F00))),
                  ),
                ],
              ),
            ),
          ),
          _BottomNav(
            currentIndex: _currentIndex,
            total: questions.length,
            onPrev: _currentIndex > 0 ? () => setState(() => _currentIndex--) : null,
            onNext: _currentIndex < questions.length - 1 ? () => setState(() => _currentIndex++) : null,
            onSubmit: _submitExam,
          ),
        ],
      ),
    );
  }
}

class _QuestionBody extends StatelessWidget {
  final Map<String, dynamic> question;
  const _QuestionBody({required this.question});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E1E2E), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MathText(
            text: question['latex_body'] ?? '',
            textStyle: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          if (question['image_url'] != null) ...[
            const SizedBox(height: 12),
            Image.network(
              'http://10.0.2.2:3000${question['image_url']}',
              errorBuilder: (_, __, ___) => const SizedBox(),
            ),
          ],
        ],
      ),
    );
  }
}

class _MCQOptions extends StatelessWidget {
  final Map<String, dynamic> question;
  final String? selected;
  final void Function(String) onSelect;

  const _MCQOptions({required this.question, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final options = question['options'] as List? ?? [];
    return Column(
      children: options.map((opt) {
        final isSelected = selected == opt['option_label'];
        return GestureDetector(
          onTap: () => onSelect(opt['option_label']),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF1A237E) : const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isSelected ? const Color(0xFFFF6F00) : Colors.transparent),
            ),
            child: Row(
              children: [
                Text('(${opt['option_label']})  ', style: TextStyle(color: isSelected ? const Color(0xFFFF6F00) : Colors.white54, fontSize: 14)),
                Expanded(
                  child: MathText(
                    text: opt['latex_option'] ?? '',
                    textStyle: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _NumericalInput extends StatelessWidget {
  final String? value;
  final void Function(String) onSubmit;

  const _NumericalInput({required this.value, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController(text: value);
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Your Answer',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.check),
          onPressed: () => onSubmit(ctrl.text),
        ),
      ),
      onSubmitted: onSubmit,
    );
  }
}

class _ProofUpload extends StatelessWidget {
  final String? photoPath;
  final void Function(File) onUpload;

  const _ProofUpload({required this.photoPath, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (photoPath != null)
          Image.file(File(photoPath!), height: 200),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () async {
            final picker = ImagePicker();
            final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
            if (image != null) onUpload(File(image.path));
          },
          icon: const Icon(Icons.camera_alt),
          label: Text(photoPath == null ? 'Upload Solution Photo' : 'Retake Photo'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E)),
        ),
      ],
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onSubmit;

  const _BottomNav({required this.currentIndex, required this.total, this.onPrev, this.onNext, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF1E1E2E),
      child: Row(
        children: [
          if (onPrev != null)
            OutlinedButton(onPressed: onPrev, child: const Text('Previous')),
          const Spacer(),
          if (onNext != null)
            ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E)),
              child: const Text('Next', style: TextStyle(color: Colors.white)),
            )
          else
            ElevatedButton(
              onPressed: onSubmit,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Submit Exam', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
  }
}
