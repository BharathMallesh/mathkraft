const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const pdfParse = require('pdf-parse');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const pool = require('../config/db');
const { authenticate, authorize } = require('../middleware/auth');

const router = express.Router();

// Ensure uploads directory exists (required for Render.com / CI environments)
const uploadsDir = path.join(__dirname, '../../uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadsDir),
  filename: (req, file, cb) => cb(null, `pdf-${Date.now()}-${file.originalname}`),
});

const upload = multer({
  storage,
  limits: { fileSize: 50 * 1024 * 1024 }, // 50MB
  fileFilter: (req, file, cb) => {
    const isPdf = file.mimetype === 'application/pdf' ||
                  file.mimetype === 'application/octet-stream' ||
                  file.originalname.toLowerCase().endsWith('.pdf');
    if (isPdf) cb(null, true);
    else cb(new Error('Only PDF files are allowed'));
  },
});

// Parse PDF and extract questions using Gemini AI
router.post('/parse', authenticate, authorize('teacher', 'admin'), upload.single('pdf'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No PDF uploaded' });

  try {
    // Step 1: Extract raw text from PDF
    const pdfBuffer = fs.readFileSync(req.file.path);
    const pdfData = await pdfParse(pdfBuffer);
    const rawText = pdfData.text;

    console.log('PDF pages:', pdfData.numpages);
    console.log('Extracted text length:', rawText?.length ?? 0);
    console.log('Text preview:', rawText?.substring(0, 200));

    if (!rawText || rawText.trim().length < 10) {
      console.error('Text extraction failed — likely a scanned PDF');
      return res.status(400).json({ error: 'Could not extract text from PDF. Make sure the PDF is not scanned/image-based.' });
    }

    // Step 2: Send to Gemini to parse into structured questions
    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });

    const prompt = `You are an expert at parsing Indian Math Olympiad question papers (IOQM, RMO, INMO).

Below is raw text extracted from a question paper PDF. Parse it into a structured JSON array of questions.

Rules:
- Identify each question carefully (they usually start with Q1, Q2, 1., 2., etc.)
- For MCQ questions: extract all 4 options and mark the correct one if visible (otherwise set is_correct: false for all)
- For numerical answer questions: extract the correct answer if visible
- For proof/subjective questions: mark as type "proof"
- Convert ALL math expressions to proper LaTeX format:
  - Fractions: \\frac{a}{b}
  - Powers: x^{2}
  - Square roots: \\sqrt{x}
  - Summation: \\sum_{i=1}^{n}
  - Greek letters: \\alpha, \\beta, \\theta
  - Infinity: \\infty
  - Therefore: \\therefore
  - Belongs to: \\in
  - For all: \\forall
  - There exists: \\exists
- Detect the topic from context: Number Theory, Algebra, Geometry, Combinatorics, Trigonometry, Inequalities, Probability
- Estimate difficulty: easy, medium, hard (based on complexity)
- Default marks: MCQ=3, Numerical=6, Proof=10 (adjust if specified in paper)

IMPORTANT: If there are more than 15 questions, return only the first 15. Keep each latex_body concise (under 200 chars).

Raw PDF text:
${rawText.substring(0, 6000)}

Return ONLY a valid JSON array. No explanation. No markdown. Just the JSON:
[
  {
    "question_number": 1,
    "type": "mcq|numerical|proof",
    "latex_body": "question text with LaTeX",
    "topic": "Number Theory|Algebra|Geometry|Combinatorics|Trigonometry|Inequalities|Probability",
    "difficulty": "easy|medium|hard",
    "marks": 3,
    "options": [
      {"label": "A", "text": "option text with LaTeX", "is_correct": false},
      {"label": "B", "text": "option text with LaTeX", "is_correct": true},
      {"label": "C", "text": "option text with LaTeX", "is_correct": false},
      {"label": "D", "text": "option text with LaTeX", "is_correct": false}
    ],
    "correct_value": null,
    "tolerance": 0
  }
]`;

    const result = await model.generateContent({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: { maxOutputTokens: 8192, temperature: 0.1 },
    });
    let responseText = result.response.text().trim();
    console.log('Gemini raw response (first 500):', responseText.substring(0, 500));

    // Clean up response — remove markdown code blocks if present
    responseText = responseText.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();

    let questions;
    try {
      questions = JSON.parse(responseText);
    } catch (parseErr) {
      console.error('JSON parse error:', parseErr.message);
      console.error('Response that failed to parse:', responseText.substring(0, 1000));
      return res.status(500).json({
        error: 'AI could not parse questions from this PDF. Try a cleaner PDF or add questions manually.',
        raw_text_preview: rawText.substring(0, 500),
      });
    }

    // Save paper record to database
    const fileSizeKb = Math.round(req.file.size / 1024);
    const fileUrl = `/uploads/${req.file.filename}`;
    const paperTitle = req.file.originalname.replace('.pdf', '').replace(/-/g, ' ').replace(/_/g, ' ');

    const paperResult = await pool.query(
      `INSERT INTO question_papers
       (title, file_name, file_url, file_size_kb, pages, teacher_id, questions_extracted, raw_text, parsed_questions)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
      [paperTitle, req.file.originalname, fileUrl, fileSizeKb, pdfData.numpages, req.user.id, questions.length, rawText, JSON.stringify(questions)]
    );
    const paper = paperResult.rows[0];

    res.json({
      paper_id: paper.id,
      total_questions: questions.length,
      pdf_pages: pdfData.numpages,
      questions,
    });

  } catch (err) {
    console.error('PDF parse route error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// List all stored question papers
router.get('/papers', authenticate, authorize('teacher', 'admin'), async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT qp.*, u.name as teacher_name, e.title as exam_title
       FROM question_papers qp
       LEFT JOIN users u ON qp.teacher_id = u.id
       LEFT JOIN exams e ON qp.exam_id = e.id
       ORDER BY qp.created_at DESC`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Get single paper with its raw text (for re-parsing)
router.get('/papers/:id', authenticate, authorize('teacher', 'admin'), async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM question_papers WHERE id=$1', [req.params.id]);
    if (!result.rows.length) return res.status(404).json({ error: 'Paper not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Re-parse an already stored paper for a different exam
router.post('/papers/:id/reparse', authenticate, authorize('teacher', 'admin'), async (req, res) => {
  try {
    const paperResult = await pool.query('SELECT * FROM question_papers WHERE id=$1', [req.params.id]);
    if (!paperResult.rows.length) return res.status(404).json({ error: 'Paper not found' });

    const paper = paperResult.rows[0];

    // Return previously saved edited questions if available
    if (paper.parsed_questions && paper.parsed_questions.length > 0) {
      return res.json({
        paper_id: paper.id,
        total_questions: paper.parsed_questions.length,
        questions: paper.parsed_questions,
        source: 'saved',
      });
    }

    const rawText = paper.raw_text;

    if (!rawText || rawText.trim().length < 10) {
      return res.status(400).json({ error: 'No stored text for this paper' });
    }

    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });

    const prompt = `You are an expert at parsing Indian Math Olympiad question papers.
Parse this text into a structured JSON array of questions with LaTeX formatting.
Return ONLY valid JSON. No markdown. No explanation.
IMPORTANT: Return only the first 15 questions. Keep latex_body under 200 chars.

Text:
${rawText.substring(0, 6000)}

Format: [{"question_number":1,"type":"mcq|numerical|proof","latex_body":"...","topic":"...","difficulty":"easy|medium|hard","marks":3,"options":[{"label":"A","text":"...","is_correct":false}],"correct_value":null,"tolerance":0}]`;

    const result = await model.generateContent({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: { maxOutputTokens: 8192, temperature: 0.1 },
    });

    let responseText = result.response.text().trim()
      .replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();

    let questions;
    try {
      questions = JSON.parse(responseText);
    } catch {
      return res.status(500).json({ error: 'AI could not parse this paper. Try uploading again.' });
    }

    res.json({ paper_id: paper.id, total_questions: questions.length, questions });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Delete a stored paper
router.delete('/papers/:id', authenticate, authorize('teacher', 'admin'), async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM question_papers WHERE id=$1 AND teacher_id=$2', [req.params.id, req.user.id]);
    if (!result.rows.length) return res.status(404).json({ error: 'Paper not found' });
    await pool.query('DELETE FROM question_papers WHERE id=$1', [req.params.id]);
    res.json({ message: 'Paper deleted' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Save parsed questions to an exam
router.post('/save', authenticate, authorize('teacher', 'admin'), async (req, res) => {
  const { exam_id, questions, paper_id } = req.body;

  if (!exam_id || !questions || !Array.isArray(questions)) {
    return res.status(400).json({ error: 'exam_id and questions array required' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const saved = [];

    for (const q of questions) {
      // Insert question
      const qResult = await client.query(
        `INSERT INTO questions
         (exam_id, question_number, type, latex_body, marks, partial_marks, topic, difficulty)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *`,
        [
          exam_id,
          q.question_number,
          q.type,
          q.latex_body,
          q.marks || 3,
          q.partial_marks || 0,
          q.topic || 'General',
          q.difficulty || 'medium',
        ]
      );
      const question = qResult.rows[0];

      // Insert MCQ options
      if (q.type === 'mcq' && q.options && q.options.length > 0) {
        for (const opt of q.options) {
          await client.query(
            'INSERT INTO mcq_options (question_id, option_label, latex_option, is_correct) VALUES ($1,$2,$3,$4)',
            [question.id, opt.label, opt.text, opt.is_correct || false]
          );
        }
      }

      // Insert numerical answer
      if (q.type === 'numerical' && q.correct_value !== null && q.correct_value !== undefined) {
        await client.query(
          'INSERT INTO numerical_answers (question_id, correct_value, tolerance) VALUES ($1,$2,$3)',
          [question.id, q.correct_value, q.tolerance || 0]
        );
      }

      saved.push(question);
    }

    // Update exam total marks
    await client.query(
      'UPDATE exams SET total_marks = (SELECT COALESCE(SUM(marks),0) FROM questions WHERE exam_id=$1) WHERE id=$1',
      [exam_id]
    );

    // Link paper to exam and save final edited questions
    if (paper_id) {
      await client.query(
        'UPDATE question_papers SET exam_id=$1, parsed_questions=$2 WHERE id=$3',
        [exam_id, JSON.stringify(questions), paper_id]
      );
    }

    await client.query('COMMIT');
    res.json({ saved: saved.length, message: `${saved.length} questions saved successfully` });

  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ error: err.message });
  } finally {
    client.release();
  }
});

module.exports = router;
