import 'dart:io';
import 'package:flutter/material.dart';
import '../../widgets/math_text.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../services/api_service.dart';

class AddQuestionScreen extends StatefulWidget {
  final String examId;
  final int questionNumber;
  final Map<String, dynamic>? existingQuestion; // null = add mode, non-null = edit mode

  const AddQuestionScreen({
    super.key,
    required this.examId,
    required this.questionNumber,
    this.existingQuestion,
  });

  @override
  State<AddQuestionScreen> createState() => _AddQuestionScreenState();
}

class _AddQuestionScreenState extends State<AddQuestionScreen> {
  final _latexCtrl = TextEditingController();
  String _type = 'mcq';
  String _topic = 'Number Theory';
  String _difficulty = 'medium';
  int _marks = 3;
  bool _loading = false;
  bool _previewMode = false;
  File? _questionImage;       // newly picked local file
  String? _existingImageUrl;  // already-saved URL from the server
  bool _imageRemoved = false; // tracks if user explicitly removed the image

  // MCQ
  late final List<Map<String, dynamic>> _options;

  // Numerical
  late final TextEditingController _answerCtrl;
  late final TextEditingController _toleranceCtrl;

  bool get _isEditMode => widget.existingQuestion != null;

  final List<String> _topics = [
    'Number Theory', 'Algebra', 'Geometry', 'Combinatorics',
    'Trigonometry', 'Calculus', 'Probability', 'Inequalities'
  ];

  @override
  void initState() {
    super.initState();
    final q = widget.existingQuestion;
    if (q != null) {
      // Edit mode — pre-fill from existing question
      _latexCtrl.text = q['latex_body'] ?? '';
      _type = q['type'] ?? 'mcq';
      _topic = (q['topic'] != null && _topics.contains(q['topic'])) ? q['topic'] : 'Number Theory';
      _difficulty = q['difficulty'] ?? 'medium';
      _marks = (q['marks'] as num?)?.toInt() ?? 3;

      // MCQ options
      final existingOpts = q['options'] as List?;
      if (existingOpts != null && existingOpts.isNotEmpty) {
        _options = existingOpts.map((opt) => {
          'label': opt['option_label'] ?? opt['label'] ?? '',
          'text': TextEditingController(text: opt['latex_option'] ?? opt['text'] ?? ''),
          'is_correct': opt['is_correct'] == true,
        }).toList();
      } else {
        _options = _defaultOptions();
      }

      // Existing image
      _existingImageUrl = q['image_url'] as String?;

      // Numerical answer
      final na = q['numerical_answer'] as Map?;
      _answerCtrl = TextEditingController(text: na?['correct_value']?.toString() ?? '');
      _toleranceCtrl = TextEditingController(text: na?['tolerance']?.toString() ?? '0');
    } else {
      // Add mode — defaults
      _options = _defaultOptions();
      _answerCtrl = TextEditingController();
      _toleranceCtrl = TextEditingController(text: '0');
    }
  }

  List<Map<String, dynamic>> _defaultOptions() => [
    {'label': 'A', 'text': TextEditingController(), 'is_correct': false},
    {'label': 'B', 'text': TextEditingController(), 'is_correct': false},
    {'label': 'C', 'text': TextEditingController(), 'is_correct': false},
    {'label': 'D', 'text': TextEditingController(), 'is_correct': false},
  ];

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (img != null) setState(() {
      _questionImage = File(img.path);
      _existingImageUrl = null; // replaced by new pick
      _imageRemoved = false;    // new image replaces removal
    });
  }

  Future<void> _saveQuestion() async {
    if (_latexCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Question body cannot be empty')));
      return;
    }
    if (_type == 'mcq' && !_options.any((o) => o['is_correct'])) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please mark at least one correct option')));
      return;
    }
    setState(() => _loading = true);

    try {
      if (_isEditMode) {
        // ── Edit mode: use PUT /questions/:id ──
        final questionId = widget.existingQuestion!['id'];
        final token = await ApiService.getToken();

        if (_questionImage != null) {
          // New image picked — send as multipart so backend can store it
          final req = http.MultipartRequest(
              'PUT', Uri.parse('${ApiService.serverRoot}/api/questions/$questionId'));
          req.headers['Authorization'] = 'Bearer $token';
          req.fields['type'] = _type;
          req.fields['latex_body'] = _latexCtrl.text;
          req.fields['marks'] = _marks.toString();
          req.fields['topic'] = _topic;
          req.fields['difficulty'] = _difficulty;
          if (_type == 'mcq') {
            req.fields['options'] = jsonEncode(_options.map((o) => {
              'label': o['label'],
              'text': (o['text'] as TextEditingController).text,
              'is_correct': o['is_correct'],
            }).toList());
          } else if (_type == 'numerical') {
            req.fields['correct_value'] = _answerCtrl.text;
            req.fields['tolerance'] = _toleranceCtrl.text;
          }
          req.files.add(await http.MultipartFile.fromPath('image', _questionImage!.path));
          final streamed = await req.send();
          await http.Response.fromStream(streamed);
        } else {
          final body = <String, dynamic>{
            'type': _type,
            'latex_body': _latexCtrl.text,
            'marks': _marks,
            'topic': _topic,
            'difficulty': _difficulty,
          };
          if (_imageRemoved || (_questionImage == null && _existingImageUrl == null)) {
            body['remove_image'] = true;
          }
          if (_type == 'mcq') {
            body['options'] = _options.map((o) => {
              'label': o['label'],
              'text': (o['text'] as TextEditingController).text,
              'is_correct': o['is_correct'],
            }).toList();
          } else if (_type == 'numerical') {
            body['correct_value'] = double.tryParse(_answerCtrl.text) ?? 0;
            body['tolerance'] = double.tryParse(_toleranceCtrl.text) ?? 0;
          }
          await ApiService.put('/questions/$questionId', body);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Question updated!'),
            backgroundColor: Colors.green,
          ));
          Navigator.pop(context, true);
        }
      } else {
        // ── Add mode: use multipart POST /questions ──
        final token = await ApiService.getToken();
        final req = http.MultipartRequest('POST', Uri.parse('${ApiService.serverRoot}/api/questions'));
        req.headers['Authorization'] = 'Bearer $token';

        req.fields['exam_id'] = widget.examId;
        req.fields['question_number'] = widget.questionNumber.toString();
        req.fields['type'] = _type;
        req.fields['latex_body'] = _latexCtrl.text;
        req.fields['marks'] = _marks.toString();
        req.fields['topic'] = _topic;
        req.fields['difficulty'] = _difficulty;

        if (_type == 'mcq') {
          req.fields['options'] = jsonEncode(_options.map((o) => {
            'label': o['label'],
            'text': (o['text'] as TextEditingController).text,
            'is_correct': o['is_correct'],
          }).toList());
        } else if (_type == 'numerical') {
          req.fields['correct_value'] = _answerCtrl.text;
          req.fields['tolerance'] = _toleranceCtrl.text;
        }

        if (_questionImage != null) {
          req.files.add(await http.MultipartFile.fromPath('image', _questionImage!.path));
        }

        final streamed = await req.send();
        final res = await http.Response.fromStream(streamed);

        if (mounted) {
          if (res.statusCode == 201) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Question saved!'),
              backgroundColor: Colors.green,
            ));
            Navigator.pop(context, true);
          } else {
            final body = jsonDecode(res.body);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(body['error'] ?? 'Failed to save')));
          }
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(_isEditMode ? 'Edit Q${widget.questionNumber}' : 'Question ${widget.questionNumber}'),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _previewMode = !_previewMode),
            icon: Icon(_previewMode ? Icons.edit : Icons.preview, color: const Color(0xFFFF6F00)),
            label: Text(_previewMode ? 'Edit' : 'Preview', style: const TextStyle(color: Color(0xFFFF6F00))),
          ),
        ],
      ),
      body: _previewMode ? _buildPreview() : _buildEditor(),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _loading ? null : _saveQuestion,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A237E),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _loading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_isEditMode ? 'Update Question' : 'Save Question', style: const TextStyle(fontSize: 16, color: Colors.white)),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type selector
          const Text('Question Type', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 8),
          Row(
            children: [
              _TypeChip(label: 'MCQ', value: 'mcq', selected: _type, onTap: (v) => setState(() => _type = v)),
              const SizedBox(width: 8),
              _TypeChip(label: 'Numerical', value: 'numerical', selected: _type, onTap: (v) => setState(() => _type = v)),
              const SizedBox(width: 8),
              _TypeChip(label: 'Proof', value: 'proof', selected: _type, onTap: (v) => setState(() => _type = v)),
            ],
          ),
          const SizedBox(height: 20),

          // LaTeX body
          const Text('Question (LaTeX)', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      _LatexShortcut(label: '\\frac{}{}', ctrl: _latexCtrl),
                      _LatexShortcut(label: '^{}', ctrl: _latexCtrl),
                      _LatexShortcut(label: '\\sqrt{}', ctrl: _latexCtrl),
                      _LatexShortcut(label: '\\sum', ctrl: _latexCtrl),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                TextField(
                  controller: _latexCtrl,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Enter question in LaTeX...\ne.g. Find all integers n such that n^2 + 1 is divisible by 5.',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Optional image
          Row(
            children: [
              const Text('Add Figure (optional)', style: TextStyle(color: Colors.white54, fontSize: 13)),
              const Spacer(),
              TextButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image_outlined, size: 16),
                label: const Text('Upload'),
              ),
            ],
          ),
          if (_questionImage != null || _existingImageUrl != null) ...[
            const SizedBox(height: 8),
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _questionImage != null
                      ? Image.file(_questionImage!, height: 150, width: double.infinity, fit: BoxFit.cover)
                      : Image.network(
                          ApiService.getImageUrl($_existingImageUrl!),
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 150,
                            color: const Color(0xFF1E1E2E),
                            child: const Center(child: Icon(Icons.broken_image, color: Colors.white38)),
                          ),
                        ),
                ),
                Positioned(
                  top: 4, right: 4,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _questionImage = null;
                      _existingImageUrl = null;
                      _imageRemoved = true;
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),

          // Type-specific inputs
          if (_type == 'mcq') _buildMCQSection(),
          if (_type == 'numerical') _buildNumericalSection(),
          if (_type == 'proof') _buildProofSection(),

          const SizedBox(height: 20),

          // Marks, topic, difficulty
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Marks', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _marks > 1 ? () => setState(() => _marks--) : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('$_marks', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                        IconButton(
                          onPressed: () => setState(() => _marks++),
                          icon: const Icon(Icons.add_circle_outline, color: Color(0xFFFF6F00)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            value: _topic,
            decoration: const InputDecoration(labelText: 'Topic', border: OutlineInputBorder()),
            items: _topics.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) => setState(() => _topic = v!),
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            value: _difficulty,
            decoration: const InputDecoration(labelText: 'Difficulty', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'easy', child: Text('Easy')),
              DropdownMenuItem(value: 'medium', child: Text('Medium')),
              DropdownMenuItem(value: 'hard', child: Text('Hard')),
            ],
            onChanged: (v) => setState(() => _difficulty = v!),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildMCQSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Answer Options', style: TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 8),
        ..._options.map((opt) {
          final label = opt['label'] as String;
          final ctrl = opt['text'] as TextEditingController;
          final isCorrect = opt['is_correct'] as bool;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isCorrect ? const Color(0xFF1B5E20).withValues(alpha: 0.3) : const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isCorrect ? Colors.green : Colors.white24),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() {
                    for (var o in _options) o['is_correct'] = false;
                    opt['is_correct'] = true;
                  }),
                  child: Container(
                    width: 48,
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isCorrect ? Colors.green : Colors.white54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    decoration: InputDecoration(
                      hintText: 'Option $label (LaTeX)',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (isCorrect)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.check_circle, color: Colors.green, size: 18),
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        const Text('Tap option label to mark as correct', style: TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }

  Widget _buildNumericalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Correct Answer', style: TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _answerCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Correct Value',
            border: OutlineInputBorder(),
            hintText: 'e.g. 42 or 3.14',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _toleranceCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Tolerance (±)',
            border: OutlineInputBorder(),
            hintText: '0 for exact match',
          ),
        ),
      ],
    );
  }

  Widget _buildProofSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: const Row(
        children: [
          Icon(Icons.camera_alt_outlined, color: Colors.white54),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Proof Question', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Students will upload a photo of their handwritten solution. You will grade it manually.', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1E1E2E), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFF1A237E), borderRadius: BorderRadius.circular(4)),
                      child: Text(_type.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    Text(_topic, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    const Spacer(),
                    Text('$_marks marks', style: const TextStyle(color: Color(0xFFFF6F00), fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 16),
                _latexCtrl.text.isEmpty
                    ? const Text('(Question preview will appear here)', style: TextStyle(color: Colors.white38))
                    : MathText(text: _latexCtrl.text, textStyle: const TextStyle(color: Colors.white, fontSize: 16)),
                if (_questionImage != null || _existingImageUrl != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _questionImage != null
                        ? Image.file(_questionImage!, height: 150, fit: BoxFit.cover)
                        : Image.network(
                            ApiService.getImageUrl($_existingImageUrl!),
                            height: 150,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(),
                          ),
                  ),
                ],
              ],
            ),
          ),
          if (_type == 'mcq') ...[
            const SizedBox(height: 16),
            ..._options.map((opt) {
              final ctrl = opt['text'] as TextEditingController;
              final isCorrect = opt['is_correct'] as bool;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isCorrect ? const Color(0xFF1B5E20).withValues(alpha: 0.3) : const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isCorrect ? Colors.green : Colors.white12),
                ),
                child: Row(
                  children: [
                    Text('(${opt['label']})  ', style: TextStyle(color: isCorrect ? Colors.green : Colors.white54)),
                    if (ctrl.text.isNotEmpty)
                      Expanded(child: MathText(text: ctrl.text, textStyle: const TextStyle(color: Colors.white)))
                    else
                      const Text('(empty)', style: TextStyle(color: Colors.white38)),
                    if (isCorrect) const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  ],
                ),
              );
            }),
          ],
          if (_type == 'numerical') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF1E1E2E), borderRadius: BorderRadius.circular(8)),
              child: Text('Correct Answer: ${_answerCtrl.text} ± ${_toleranceCtrl.text}', style: const TextStyle(color: Colors.green)),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final void Function(String) onTap;

  const _TypeChip({required this.label, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A237E) : const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFFFF6F00) : Colors.white24),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontSize: 13)),
      ),
    );
  }
}

class _LatexShortcut extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;

  const _LatexShortcut({required this.label, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final text = ctrl.text;
        final sel = ctrl.selection;
        final newText = text.replaceRange(sel.start, sel.end, label);
        ctrl.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: sel.start + label.length),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A3E),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: const TextStyle(color: Color(0xFFFF6F00), fontSize: 11, fontFamily: 'monospace')),
      ),
    );
  }
}
