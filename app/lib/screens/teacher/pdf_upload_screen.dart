import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../widgets/math_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../../services/api_service.dart';

class PdfUploadScreen extends StatefulWidget {
  final String examId;
  final String examTitle;
  final String? preloadedPaperId;
  final List<dynamic>? preloadedQuestions;

  const PdfUploadScreen({
    super.key,
    required this.examId,
    required this.examTitle,
    this.preloadedPaperId,
    this.preloadedQuestions,
  });

  @override
  State<PdfUploadScreen> createState() => _PdfUploadScreenState();
}

class _PdfUploadScreenState extends State<PdfUploadScreen> {
  File? _selectedPdf;
  String? _pdfName;
  bool _uploading = false;
  bool _saving = false;
  List<Map<String, dynamic>> _parsedQuestions = [];
  String _status = '';
  String? _currentPaperId;
  String? _pagesDirectory;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedQuestions != null && widget.preloadedQuestions!.isNotEmpty) {
      _parsedQuestions = widget.preloadedQuestions!
          .map((q) => Map<String, dynamic>.from(q))
          .toList();
      _currentPaperId = widget.preloadedPaperId;
      _status = 'Loaded ${_parsedQuestions.length} questions from stored paper';
    }
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedPdf = File(result.files.single.path!);
        _pdfName = result.files.single.name;
        _parsedQuestions = [];
        _status = '';
      });
    }
  }

  Future<void> _uploadAndParse() async {
    if (_selectedPdf == null) return;
    setState(() { _uploading = true; _status = 'Extracting text from PDF...'; });

    try {
      final token = await ApiService.getToken();
      final req = http.MultipartRequest('POST', Uri.parse('http://10.0.2.2:3000/api/pdf/parse'));
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath('pdf', _selectedPdf!.path));

      setState(() => _status = 'AI is parsing questions...');
      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      final body = jsonDecode(res.body);

      if (res.statusCode == 200) {
        final rawQuestions = body['questions'] as List;
        setState(() {
          _parsedQuestions = rawQuestions.map((q) => Map<String, dynamic>.from(q)).toList();
          _currentPaperId = body['paper_id']?.toString();
          _pagesDirectory = body['pages_directory'];
          _status = 'Found ${_parsedQuestions.length} questions from ${body['pdf_pages']} pages';
          _uploading = false;
        });
      } else {
        setState(() {
          _status = body['error'] ?? 'Failed to parse PDF';
          _uploading = false;
        });
      }
    } catch (e) {
      setState(() { _status = 'Error: ${e.toString()}'; _uploading = false; });
    }
  }

  Future<void> _saveQuestions() async {
    if (_parsedQuestions.isEmpty) return;
    setState(() { _saving = true; _status = 'Saving questions to exam...'; });

    try {
      final payload = <String, dynamic>{
        'exam_id': widget.examId,
        'questions': _parsedQuestions,
        if (_currentPaperId != null) 'paper_id': _currentPaperId,
      };
      final data = await ApiService.post('/pdf/save', payload);

      if (mounted) {
        setState(() { _saving = false; _status = ''; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['message'] ?? 'Questions saved!'),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() { _saving = false; _status = 'Save failed: ${e.toString()}'; });
    }
  }

  void _editQuestion(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2E),
      builder: (_) => _QuestionEditor(
        question: _parsedQuestions[index],
        pagesDirectory: _pagesDirectory,
        onSave: (updated) {
          setState(() => _parsedQuestions[index] = updated);
        },
      ),
    );
  }

  void _removeQuestion(int index) {
    setState(() {
      _parsedQuestions.removeAt(index);
      // Renumber
      for (int i = 0; i < _parsedQuestions.length; i++) {
        _parsedQuestions[i]['question_number'] = i + 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Upload Question Paper', style: TextStyle(fontSize: 15)),
            Text(widget.examTitle, style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
        actions: [
          if (_parsedQuestions.isNotEmpty)
            TextButton.icon(
              onPressed: _saving ? null : _saveQuestions,
              icon: _saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save, color: Color(0xFFFF6F00), size: 18),
              label: Text(
                _saving ? 'Saving...' : 'Save All',
                style: const TextStyle(color: Color(0xFFFF6F00)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Upload section
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _selectedPdf != null ? const Color(0xFFFF6F00) : Colors.white24,
                style: _selectedPdf == null ? BorderStyle.solid : BorderStyle.solid,
              ),
            ),
            child: Column(
              children: [
                const Icon(Icons.picture_as_pdf, color: Color(0xFFFF6F00), size: 48),
                const SizedBox(height: 12),
                if (_selectedPdf == null) ...[
                  const Text('Select Question Paper PDF', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('Supports IOQM, RMO, INMO formats', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _pickPdf,
                    icon: const Icon(Icons.upload_file, color: Colors.white),
                    label: const Text('Choose PDF', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E)),
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 18),
                      const SizedBox(width: 8),
                      Flexible(child: Text(_pdfName ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(onPressed: _pickPdf, child: const Text('Change PDF')),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _uploading ? null : _uploadAndParse,
                        icon: _uploading
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                        label: Text(_uploading ? 'Parsing...' : 'Parse with AI', style: const TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6F00)),
                      ),
                    ],
                  ),
                ],
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _status.startsWith('Error') || _status.startsWith('AI could')
                          ? Colors.red.withValues(alpha: 0.1)
                          : Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _status,
                      style: TextStyle(
                        color: _status.startsWith('Error') || _status.startsWith('AI could') ? Colors.red : Colors.green,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Parsed questions list
          if (_parsedQuestions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '${_parsedQuestions.length} Questions Parsed',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  const Text('Tap to edit', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                itemCount: _parsedQuestions.length,
                itemBuilder: (context, i) {
                  final q = _parsedQuestions[i];
                  return _ParsedQuestionCard(
                    question: q,
                    index: i,
                    pagesDirectory: _pagesDirectory,
                    onEdit: () => _editQuestion(i),
                    onRemove: () => _removeQuestion(i),
                  );
                },
              ),
            ),
          ] else if (!_uploading && _selectedPdf != null && _parsedQuestions.isEmpty && _status.isEmpty) ...[
            const Expanded(
              child: Center(
                child: Text('Press "Parse with AI" to extract questions', style: TextStyle(color: Colors.white38)),
              ),
            ),
          ] else if (_uploading) ...[
            const Expanded(child: Center(child: _ParsingAnimation())),
          ] else ...[
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.upload_file, color: Colors.white12, size: 64),
                    SizedBox(height: 16),
                    Text('Upload a PDF to get started', style: TextStyle(color: Colors.white38)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: _parsedQuestions.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: _saving ? null : _saveQuestions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        'Save ${_parsedQuestions.length} Questions to Exam',
                        style: const TextStyle(fontSize: 16, color: Colors.white),
                      ),
              ),
            )
          : null,
    );
  }
}

class _ParsedQuestionCard extends StatelessWidget {
  final Map<String, dynamic> question;
  final int index;
  final String? pagesDirectory;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _ParsedQuestionCard({
    required this.question,
    required this.index,
    this.pagesDirectory,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final type = question['type'] ?? 'proof';
    final typeColor = type == 'mcq' ? Colors.blue : type == 'numerical' ? Colors.purple : Colors.orange;
    final options = question['options'] as List?;

    return GestureDetector(
      onTap: onEdit,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A237E),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                    child: Text(type.toUpperCase(), style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)),
                    child: Text(question['topic'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  ),
                  const Spacer(),
                  Text('${question['marks']} pts', style: const TextStyle(color: Color(0xFFFF6F00), fontSize: 12)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onRemove,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, color: Colors.white38, size: 16),
                    ),
                  ),
                ],
              ),
            ),

            // Question body
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: MathText(
                text: question['latex_body'] ?? '',
                textStyle: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            if (question['cropped_image_url'] != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    'http://10.0.2.2:3000${question['cropped_image_url']}',
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox.shrink(); // Hide if image fails to load
                    },
                  ),
                ),
              ),
            ] else if (pagesDirectory != null && question['page_number'] != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    'http://10.0.2.2:3000/uploads/pages/$pagesDirectory/page_${question['page_number']}.png',
                    height: 300,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox.shrink(); // Hide if image fails to load
                    },
                  ),
                ),
              ),
            ],

            // MCQ options preview
            if (type == 'mcq' && options != null && options.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(height: 1, color: Colors.white12),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: options.take(4).map((opt) {
                    final isCorrect = opt['is_correct'] == true;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            isCorrect ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: isCorrect ? Colors.green : Colors.white24,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text('(${opt['label']}) ', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          Expanded(
                            child: MathText(
                              text: opt['text'] ?? '',
                              textStyle: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            // Numerical answer preview
            if (type == 'numerical' && question['correct_value'] != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text('Answer: ${question['correct_value']}', style: const TextStyle(color: Colors.green, fontSize: 12)),
              ),
            ] else ...[
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuestionEditor extends StatefulWidget {
  final Map<String, dynamic> question;
  final String? pagesDirectory;
  final void Function(Map<String, dynamic>) onSave;

  const _QuestionEditor({required this.question, this.pagesDirectory, required this.onSave});

  @override
  State<_QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<_QuestionEditor> {
  late TextEditingController _latexCtrl;
  late String _type;
  late String _topic;
  late String _difficulty;
  late int _marks;
  late List<Map<String, dynamic>> _options;
  late TextEditingController _correctValueCtrl;

  final List<String> _topics = [
    'Number Theory', 'Algebra', 'Geometry', 'Combinatorics',
    'Trigonometry', 'Calculus', 'Probability', 'Inequalities', 'General'
  ];

  late int _pageNumber;
  String? _croppedImageUrl;
  bool _detectingDiagram = false;

  @override
  void initState() {
    super.initState();
    _latexCtrl = TextEditingController(text: widget.question['latex_body'] ?? '');
    _type = widget.question['type'] ?? 'proof';
    _topic = widget.question['topic'] ?? 'General';
    _difficulty = widget.question['difficulty'] ?? 'medium';
    _marks = widget.question['marks'] ?? 3;
    _pageNumber = widget.question['page_number'] ?? 1;
    _croppedImageUrl = widget.question['cropped_image_url'];
    _correctValueCtrl = TextEditingController(text: widget.question['correct_value']?.toString() ?? '');
    _options = ((widget.question['options'] as List?) ?? [])
        .map((o) => Map<String, dynamic>.from(o))
        .toList();
    if (_options.isEmpty && _type == 'mcq') {
      _options = [
        {'label': 'A', 'text': '', 'is_correct': false},
        {'label': 'B', 'text': '', 'is_correct': false},
        {'label': 'C', 'text': '', 'is_correct': false},
        {'label': 'D', 'text': '', 'is_correct': false},
      ];
    }
  }

  void _save() {
    final updated = Map<String, dynamic>.from(widget.question);
    updated['latex_body'] = _latexCtrl.text;
    updated['type'] = _type;
    updated['topic'] = _topic;
    updated['difficulty'] = _difficulty;
    updated['marks'] = _marks;
    updated['page_number'] = _pageNumber;
    updated['cropped_image_url'] = _croppedImageUrl;
    updated['options'] = _options;
    updated['correct_value'] = _correctValueCtrl.text.isEmpty ? null : num.tryParse(_correctValueCtrl.text);
    widget.onSave(updated);
    Navigator.pop(context);
  }

  Future<void> _redetectDiagram() async {
    if (widget.pagesDirectory == null) return;
    setState(() => _detectingDiagram = true);
    try {
      final token = await ApiService.getToken();
      final response = await http.post(
        Uri.parse('http://10.0.2.2:3000/api/pdf/detect-diagram'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'pages_directory': widget.pagesDirectory,
          'page_number': _pageNumber,
          'question_number': widget.question['question_number'],
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['cropped_image_url'] != null) {
          setState(() => _croppedImageUrl = data['cropped_image_url']);
        } else {
          setState(() => _croppedImageUrl = null);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No diagram found on this page')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _detectingDiagram = false);
    }
  }

  void _removeImage() {
    setState(() => _croppedImageUrl = null);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Edit Question', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E)),
                  child: const Text('Save', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Type
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'mcq', child: Text('MCQ')),
                DropdownMenuItem(value: 'numerical', child: Text('Numerical')),
                DropdownMenuItem(value: 'proof', child: Text('Proof')),
              ],
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 12),

            // LaTeX body
            TextField(
              controller: _latexCtrl,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Question (LaTeX)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),

            // Topic & difficulty
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _topics.contains(_topic) ? _topic : 'General',
                  decoration: const InputDecoration(labelText: 'Topic', border: OutlineInputBorder()),
                  items: _topics.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (v) => setState(() => _topic = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _difficulty,
                  decoration: const InputDecoration(labelText: 'Difficulty', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'easy', child: Text('Easy')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'hard', child: Text('Hard')),
                  ],
                  onChanged: (v) => setState(() => _difficulty = v!),
                ),
              ),
            ]),
            const SizedBox(height: 12),

            // Marks
            Row(children: [
              const Text('Marks:', style: TextStyle(color: Colors.white54)),
              const SizedBox(width: 12),
              IconButton(onPressed: _marks > 1 ? () => setState(() => _marks--) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('$_marks', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => setState(() => _marks++), icon: const Icon(Icons.add_circle_outline, color: Color(0xFFFF6F00))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Page Number:', style: TextStyle(color: Colors.white54)),
              const SizedBox(width: 12),
              IconButton(onPressed: _pageNumber > 1 ? () => setState(() => _pageNumber--) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('$_pageNumber', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => setState(() => _pageNumber++), icon: const Icon(Icons.add_circle_outline, color: Color(0xFFFF6F00))),
            ]),

            // Diagram Image Preview
            const SizedBox(height: 16),
            const Text('Diagram Image', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            if (_croppedImageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Image.network(
                    'http://10.0.2.2:3000$_croppedImageUrl',
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: const Center(child: Text('Image failed to load', style: TextStyle(color: Colors.red))),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _detectingDiagram ? null : _redetectDiagram,
                    icon: _detectingDiagram
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 16),
                    label: Text(_detectingDiagram ? 'Detecting...' : 'Re-detect'),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF6F00)),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _removeImage,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Remove'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ]),
            ] else ...[
              Container(
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.image_not_supported, color: Colors.white24, size: 28),
                      SizedBox(height: 4),
                      Text('No diagram image', style: TextStyle(color: Colors.white24, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _detectingDiagram ? null : _redetectDiagram,
                  icon: _detectingDiagram
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_fix_high, size: 16),
                  label: Text(_detectingDiagram ? 'Detecting...' : 'Detect Diagram on Page $_pageNumber'),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF6F00)),
                ),
              ),
            ],
            const SizedBox(height: 12),

            // MCQ options
            if (_type == 'mcq') ...[
              const Divider(color: Colors.white12),
              const Text('Options', style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 8),
              ..._options.asMap().entries.map((e) {
                final i = e.key;
                final opt = e.value;
                final ctrl = TextEditingController(text: opt['text'] ?? '');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() {
                          for (var o in _options) o['is_correct'] = false;
                          _options[i]['is_correct'] = true;
                        }),
                        child: Icon(
                          opt['is_correct'] == true ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: opt['is_correct'] == true ? Colors.green : Colors.white38,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: ctrl,
                          decoration: InputDecoration(
                            labelText: 'Option ${opt['label']}',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (v) => _options[i]['text'] = v,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],

            // Numerical answer
            if (_type == 'numerical') ...[
              const Divider(color: Colors.white12),
              TextField(
                controller: _correctValueCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Correct Answer', border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ParsingAnimation extends StatelessWidget {
  const _ParsingAnimation();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: Color(0xFFFF6F00)),
        SizedBox(height: 24),
        Text('AI is reading your question paper...', style: TextStyle(color: Colors.white, fontSize: 16)),
        SizedBox(height: 8),
        Text('This may take 15-30 seconds', style: TextStyle(color: Colors.white38, fontSize: 13)),
      ],
    );
  }
}
