import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import 'exam_list_screen.dart';
import 'my_results_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
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
      setState(() { _results = data is List ? data : []; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MathKraft', style: TextStyle(color: Color(0xFFFF6F00), fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1E2E),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hello, ${user?['name'] ?? 'Student'} 👋',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text('Class ${user?['class'] ?? ''}', style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 24),
            _ActionCard(
              icon: Icons.quiz_outlined,
              title: 'Take Exam',
              subtitle: 'View and attempt available olympiad exams',
              color: const Color(0xFF1A237E),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExamListScreen())),
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.bar_chart,
              title: 'My Results',
              subtitle: '${_results.length} exams attempted',
              color: const Color(0xFF1B5E20),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyResultsScreen()),
              ).then((_) => _loadResults()),
            ),
            const SizedBox(height: 24),
            const Text('Recent Results', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_results.isEmpty)
              const Center(child: Text('No exams attempted yet', style: TextStyle(color: Colors.white54)))
            else
              ..._results.take(5).map((r) => _ResultTile(result: r)),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final dynamic result;
  const _ResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1E1E2E), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(result['title'] ?? '', style: const TextStyle(color: Colors.white))),
          Text(
            '${result['total_marks_awarded']}/${result['total_marks']}',
            style: const TextStyle(color: Color(0xFFFF6F00), fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
