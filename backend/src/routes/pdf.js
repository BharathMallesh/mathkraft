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

// Parse PDF and extract questions using AI vision (Gemini or Claude)
router.post('/parse', authenticate, authorize('teacher', 'admin'), upload.single('pdf'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No PDF uploaded' });

  const engine = req.query.engine || req.body.engine || 'gemini'; // 'gemini' or 'claude'
  console.log(`Using AI engine: ${engine}`);

  try {
    const pdfBuffer = fs.readFileSync(req.file.path);

    // Step 1: Extract basic metadata via pdfParse (page count, raw text for DB storage)
    // NOTE: Math fonts often garble during text extraction — AI vision reads the PDF directly
    let pdfData = { numpages: 0, text: '' };
    try {
      pdfData = await pdfParse(pdfBuffer);
    } catch (e) {
      console.warn('pdfParse metadata extraction failed (continuing with vision):', e.message);
    }

    const rawText = pdfData.text || '';
    console.log(`PDF: ${pdfData.numpages} pages, ${rawText.length} text chars extracted`);
    // Note: even if rawText is garbled/empty, AI vision reads the PDF directly below

    // Step 2: Build prompt for JEE / Olympiad papers
    const prompt = `You are an expert at parsing Indian competitive exam question papers (JEE Advanced, JEE Main, NEET, Math Olympiad).

Carefully read the attached PDF and extract questions into a structured JSON array.

Rules:
- Read ALL pages of the PDF carefully. Questions may span multiple pages.
- Identify each question by its number (1., 2., Q1, Q2, etc.)
- Question types:
  * "mcq" — has (A)(B)(C)(D) options; JEE Advanced may have multiple correct answers
  * "numerical" — integer or decimal answer (0–9 range for JEE integer type)
  * "proof" — subjective / long answer
- Convert ALL math to proper LaTeX:
  * Fractions: \\frac{a}{b}
  * Powers: x^{2}, x^{n}
  * Square roots: \\sqrt{x}
  * Greek: \\alpha, \\beta, \\theta, \\lambda, \\mu, \\epsilon, \\omega
  * Vectors: \\vec{F}, \\hat{i}
  * Chemistry: \\text{H}_2\\text{O}, \\text{CO}_2
  * Infinity: \\infty
- For diagrams/figures: describe them inside the latex_body as [Diagram: detailed description]
- Mark correct answers if the answer key is visible in the PDF
- Detect subject + topic (e.g. "Physics - Electrostatics", "Chemistry - Organic", "Mathematics - Calculus")
- Marks: MCQ=4, Numerical=3 unless specified in the paper
- Return at most 15 questions

Return ONLY a valid JSON array. No markdown. No explanation. Just raw JSON:
[
  {
    "question_number": 1,
    "page_number": 1,
    "type": "mcq",
    "latex_body": "full question text with proper LaTeX",
    "topic": "Physics - Electrostatics",
    "difficulty": "hard",
    "marks": 4,
    "options": [
      {"label": "A", "text": "option A in LaTeX", "is_correct": false},
      {"label": "B", "text": "option B in LaTeX", "is_correct": true},
      {"label": "C", "text": "option C in LaTeX", "is_correct": false},
      {"label": "D", "text": "option D in LaTeX", "is_correct": false}
    ],
    "correct_value": null,
    "tolerance": 0
  }
]`;

    // Step 3: Send PDF visually to AI (bypasses garbled text-extraction problem)
    let responseText;

    if (engine === 'claude') {
      // ---- Claude (Anthropic) — sends PDF as base64 document ----
      const Anthropic = require('@anthropic-ai/sdk');
      const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

      console.log('Sending PDF to Claude vision...');
      const message = await anthropic.messages.create({
        model: 'claude-opus-4-5',
        max_tokens: 8192,
        messages: [{
          role: 'user',
          content: [
            {
              type: 'document',
              source: { type: 'base64', media_type: 'application/pdf', data: pdfBuffer.toString('base64') },
            },
            { type: 'text', text: prompt },
          ],
        }],
      });
      responseText = message.content[0].text.trim();
      console.log('Claude response (first 300):', responseText.substring(0, 300));

    } else {
      // ---- Gemini (default) — sends PDF as inline base64 with vision ----
      const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
      const geminiModel = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });

      console.log('Sending PDF to Gemini vision...');
      const result = await geminiModel.generateContent([
        { inlineData: { mimeType: 'application/pdf', data: pdfBuffer.toString('base64') } },
        prompt,
      ]);
      responseText = result.response.text().trim();
      console.log('Gemini response (first 300):', responseText.substring(0, 300));
    }

    // Step 4: Clean markdown code fences and parse JSON
    responseText = responseText.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();

    let questions;
    try {
      questions = JSON.parse(responseText);
      if (!Array.isArray(questions)) throw new Error('Response is not a JSON array');
    } catch (parseErr) {
      console.error('JSON parse error:', parseErr.message);
      console.error('Raw response:', responseText.substring(0, 500));
      return res.status(500).json({
        error: 'AI could not structure the questions. Try again or add questions manually.',
        ai_response_preview: responseText.substring(0, 300),
      });
    }

    // Step 5: Save paper record to DB
    const fileSizeKb = Math.round(req.file.size / 1024);
    const fileUrl = `/uploads/${req.file.filename}`;
    const paperTitle = req.file.originalname
      .replace(/\.pdf$/i, '')
      .replace(/[-_]/g, ' ')
      .trim();

    const paperResult = await pool.query(
      `INSERT INTO question_papers
       (title, file_name, file_url, file_size_kb, pages, teacher_id, questions_extracted, raw_text, parsed_questions)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
      [paperTitle, req.file.originalname, fileUrl, fileSizeKb, pdfData.numpages,
       req.user.id, questions.length, rawText, JSON.stringify(questions)]
    );

    res.json({
      paper_id: paperResult.rows[0].id,
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
         (exam_id, question_number, type, latex_body, image_url, marks, partial_marks, topic, difficulty)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
        [
          exam_id,
          q.question_number,
          q.type,
          q.latex_body,
          q.cropped_image_url || null,
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

// Detect bounding box of diagram on a page and crop it
router.post('/detect-diagram', authenticate, authorize('teacher', 'admin'), async (req, res) => {
  const { pages_directory, page_number, question_number } = req.body;
  if (!pages_directory || !page_number) {
    return res.status(400).json({ error: 'pages_directory and page_number are required' });
  }

  const path = require('path');
  const fs = require('fs');
  const imagePath = path.join(__dirname, '../../uploads/pages', pages_directory, `page_${page_number}.png`);
  
  if (!fs.existsSync(imagePath)) {
    return res.status(404).json({ error: 'Page image not found' });
  }

  try {
    const { GoogleGenerativeAI } = require('@google/generative-ai');
    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });

    const prompt = `You are an expert at document layout analysis. 
Analyze the provided image of a document page and find the main diagram, graph, circuit, or geometric figure.
Return the bounding box of the diagram in normalized coordinates (0-1000) as a JSON object with a 'box_2d' field.
Format: { "box_2d": [ymin, xmin, ymax, xmax] }
If there are multiple diagrams, return the box for the one that looks like a main problem diagram.
If no diagram or figure is found on the page, return { "box_2d": null }.
Return ONLY the JSON object. No markdown.`;

    const result = await model.generateContent([
      {
        inlineData: {
          mimeType: 'image/png',
          data: fs.readFileSync(imagePath).toString('base64')
        }
      },
      prompt
    ]);

    let responseText = result.response.text().trim();
    responseText = responseText.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();

    const data = JSON.parse(responseText);
    
    if (data && data.box_2d) {
      // Crop the image
      const { Jimp } = require('jimp');
      const box = data.box_2d;
      const qNum = question_number || `p${page_number}`;
      const outputFilename = `q_${qNum}.png`;
      const outputPath = path.join(__dirname, '../../uploads/pages', pages_directory, outputFilename);

      const image = await Jimp.read(imagePath);
      const width = image.bitmap.width;
      const height = image.bitmap.height;

      const ymin = Math.round(box[0] / 1000 * height);
      const xmin = Math.round(box[1] / 1000 * width);
      const ymax = Math.round(box[2] / 1000 * height);
      const xmax = Math.round(box[3] / 1000 * width);

      const cropWidth = xmax - xmin;
      const cropHeight = ymax - ymin;

      if (cropWidth > 10 && cropHeight > 10) {
        image.crop({ x: xmin, y: ymin, w: cropWidth, h: cropHeight });
        await image.write(outputPath);
        const croppedUrl = `/uploads/pages/${pages_directory}/${outputFilename}`;
        console.log(`Cropped diagram saved: ${croppedUrl}`);
        res.json({ box_2d: data.box_2d, cropped_image_url: croppedUrl });
      } else {
        res.json({ box_2d: data.box_2d, cropped_image_url: null });
      }
    } else {
      res.json({ box_2d: null, cropped_image_url: null });
    }

  } catch (err) {
    console.error('Diagram detection error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
