import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class CreateExamScreen extends StatefulWidget {
  const CreateExamScreen({super.key});

  @override
  State<CreateExamScreen> createState() => _CreateExamScreenState();
}

class _CreateExamScreenState extends State<CreateExamScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _durationCtrl = TextEditingController(text: '180');
  String _examType = 'mock';
  String _targetClass = 'all';
  bool _loading = false;

  final List<String> _classes = ['all', '5', '6', '7', '8', '9', '10', '11', '12'];

  Future<void> _createExam() async {
    if (_titleCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    try {
      final data = await ApiService.post('/exams', {
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'exam_type': _examType,
        'duration_minutes': int.parse(_durationCtrl.text),
        'target_class': _targetClass,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exam created! Add questions next.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Exam'), backgroundColor: const Color(0xFF1E1E2E)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Exam Title', border: OutlineInputBorder(), hintText: 'e.g. IOQM Mock Test 1'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _examType,
              decoration: const InputDecoration(labelText: 'Exam Type', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'mock', child: Text('Mock Test')),
                DropdownMenuItem(value: 'practice', child: Text('Practice Set')),
                DropdownMenuItem(value: 'diagnostic', child: Text('Diagnostic Test')),
              ],
              onChanged: (v) => setState(() => _examType = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _durationCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Duration (minutes)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _targetClass,
              decoration: const InputDecoration(
                labelText: 'Target Class',
                border: OutlineInputBorder(),
                helperText: 'Which class can see this exam',
              ),
              items: _classes.map((c) => DropdownMenuItem(
                value: c,
                child: Text(c == 'all' ? 'All Classes' : 'Class $c'),
              )).toList(),
              onChanged: (v) => setState(() => _targetClass = v!),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _loading ? null : _createExam,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create Exam', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
