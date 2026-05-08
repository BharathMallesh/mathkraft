import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import 'create_exam_screen.dart';
import 'exam_detail_screen.dart';

class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  List<dynamic> _exams = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExams();
  }

  Future<void> _loadExams() async {
    try {
      final data = await ApiService.get('/exams/teacher/my-exams');
      setState(() { _exams = data is List ? data : []; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _publishExam(String id) async {
    await ApiService.patch('/exams/$id/publish', {});
    _loadExams();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MathKraft', style: TextStyle(color: Color(0xFFFF6F00), fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1E2E),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => context.read<AuthProvider>().logout()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateExamScreen())).then((_) => _loadExams()),
        backgroundColor: const Color(0xFFFF6F00),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Exam', style: TextStyle(color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome, ${user?['name'] ?? 'Teacher'}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            const Text('Manage your olympiad exams', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 24),
            const Text('My Exams', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_exams.isEmpty)
              const Center(child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No exams created yet.\nTap + to create your first exam.', style: TextStyle(color: Colors.white54), textAlign: TextAlign.center),
              ))
            else
              ..._exams.map((exam) => _ExamCard(
                exam: exam,
                onPublish: () => _publishExam(exam['id']),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ExamDetailScreen(exam: exam),
                )).then((_) => _loadExams()),
              )),
          ],
        ),
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  final dynamic exam;
  final VoidCallback onPublish;
  final VoidCallback onTap;

  const _ExamCard({required this.exam, required this.onPublish, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPublished = exam['is_published'] == true;
    return GestureDetector(
      onTap: onTap,
      child: _buildCard(context, isPublished),
    );
  }

  Widget _buildCard(BuildContext context, bool isPublished) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isPublished ? Colors.green.withValues(alpha: 0.5) : Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(exam['title'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPublished ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(isPublished ? 'Published' : 'Draft', style: TextStyle(color: isPublished ? Colors.green : Colors.orange, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${exam['duration_minutes']} min  •  ${exam['exam_type']}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
          if (!isPublished) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onPublish,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E)),
                child: const Text('Publish to Students', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
