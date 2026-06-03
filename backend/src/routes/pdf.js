const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const pdfParse = require('pdf-parse');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const { fromPath } = require('pdf2pic');
const { Jimp } = require('jimp');
const pool = require('../config/db');
const { cloudinary, storage: cloudinaryStorage } = require('../config/cloudinary');
const { authenticate, authorize } = require('../middleware/auth');

const router = express.Router();

// Ensure uploads directory exists (required for Render.com / CI environments)
const uploadsDir = path.join(__dirname, '../../uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

// Render all pages of a PDF to PNG images. Returns the directory name.
async function renderPdfPages(pdfPath, numPages) {
  const dirName = `pdf_${Date.now()}`;
  const pagesDir = path.join(uploadsDir, 'pages', dirName);
  fs.mkdirSync(pagesDir, { recursive: true });

  const converter = fromPath(pdfPath, {
    density: 150,
    saveFilename: 'page',
    savePath: pagesDir,
    format: 'png',
    width: 1240,
    height: 1754,
  });

  const pagesToRender = Math.min(numPages || 30, 30);
  for (let i = 1; i <= pagesToRender; i++) {
    try {
      await converter(i, { responseType: 'image' });
    } catch (e) {
      console.warn(`Page ${i} render failed:`, e.message);
    }
  }

  return dirName;
}

// Ask Gemini to find a diagram bounding box in a page image, then crop it.
// Returns the cropped image URL or null.
async function detectAndCropDiagram(pagesDirectory, pageNumber, questionNumber) {
  // pdf2pic saves files as "page.N.png" (dot separator, not underscore)
  const imagePath = path.join(uploadsDir, 'pages', pagesDirectory, `page.${pageNumber}.png`);
  if (!fs.existsSync(imagePath)) return null;

  try {
    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });

    const prompt = `Analyze this exam question paper page image.
Find the diagram, circuit, graph, or geometric figure that belongs to question number ${questionNumber}.
Return the bounding box in normalized coordinates (0–1000) as JSON: { "box_2d": [ymin, xmin, ymax, xmax] }
Rules:
- Only return a box if there is a clear diagram/figure (circle, sphere, circuit, graph, geometric shape, etc.) visible on the page.
- IMPORTANT: If the multiple choice options (A, B, C, D) for this question are images/graphs, include ALL the option images inside the bounding box.
- The box must include the full diagram with all labels — do NOT cut off edges.
- Do NOT include question text, unless the options are images. If options are images, do not include the question text, but do include the options A, B, C, D.
- If the page has multiple diagrams, return the one for question ${questionNumber}.
- If no diagram or figure is found on this page, return { "box_2d": null }.
Return ONLY the JSON object. No markdown.`;

    const result = await model.generateContent({
      contents: [{ role: 'user', parts: [
        { inlineData: { mimeType: 'image/png', data: fs.readFileSync(imagePath).toString('base64') } },
        { text: prompt }
      ]}],
      generationConfig: { responseMimeType: 'application/json', temperature: 0.1 }
    });

    let responseText = result.response.text().trim()
      .replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();

    const data = JSON.parse(responseText);
    if (!data || !data.box_2d) return null;

    const box = data.box_2d;
    const image = await Jimp.read(imagePath);
    const w = image.bitmap.width;
    const h = image.bitmap.height;

    // Add 2% padding on each side so tight boxes don't clip edges
    const PAD_X = Math.round(w * 0.02);
    const PAD_Y = Math.round(h * 0.02);

    const ymin = Math.max(0, Math.round(box[0] / 1000 * h) - PAD_Y);
    const xmin = Math.max(0, Math.round(box[1] / 1000 * w) - PAD_X);
    const ymax = Math.min(h, Math.round(box[2] / 1000 * h) + PAD_Y);
    const xmax = Math.min(w, Math.round(box[3] / 1000 * w) + PAD_X);

    const cropW = xmax - xmin;
    const cropH = ymax - ymin;
    if (cropW < 10 || cropH < 10) return null;

    const outputFilename = `q_${questionNumber}_p${pageNumber}.png`;
    const outputPath = path.join(uploadsDir, 'pages', pagesDirectory, outputFilename);
    image.crop({ x: xmin, y: ymin, w: cropW, h: cropH });
    await image.write(outputPath);

    // Upload to Cloudinary
    const cloudRes = await cloudinary.uploader.upload(outputPath, {
      folder: 'mathkraft_diagrams',
    });

    // Delete local file asynchronously
    fs.unlink(outputPath, () => {});

    return cloudRes.secure_url;
  } catch (e) {
    console.warn(`Diagram detection failed for Q${questionNumber} page ${pageNumber}:`, e.message);
    return null;
  }
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

const uploadImage = multer({
  storage: cloudinaryStorage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith('image/')) cb(null, true);
    else cb(new Error('Only image files are allowed'));
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

    const startQuestion = req.body.start_question ? parseInt(req.body.start_question) : null;
    const startInstruction = startQuestion 
      ? `- Start extracting from question number ${startQuestion}. Ignore any questions before it.` 
      : '';

    // Step 2: Build prompt for JEE / Olympiad papers
    const prompt = `You are an expert at parsing Indian competitive exam question papers (JEE Advanced, JEE Main, NEET, Math Olympiad).

Carefully read the attached PDF and extract questions into a structured JSON array.

Rules:
- Read ALL pages of the PDF carefully. Questions may span multiple pages.
- Identify each question by its number (1., 2., Q1, Q2, etc.)
${startInstruction}
- Question types:
  * "mcq" — has (A)(B)(C)(D) options; JEE Advanced may have multiple correct answers
  * "numerical" — integer or decimal answer (0–9 range for JEE integer type)
  * "proof" — subjective / long answer
- Convert ALL math to proper LaTeX and ALWAYS wrap math expressions in $...$ delimiters:
  * Fractions: $\\frac{a}{b}$
  * Powers: $x^{2}$, $x^{n}$
  * Square roots: $\\sqrt{x}$
  * Greek: $\\alpha$, $\\beta$, $\\theta$, $\\lambda$, $\\mu$, $\\epsilon$, $\\omega$
  * Vectors: $\\vec{F}$, $\\hat{i}$
  * Chemistry: $\\text{H}_2\\text{O}$, $\\text{CO}_2$
  * Infinity: $\\infty$
  * Mixed: "The value of $K_0$ is $\\frac{Qq}{8\\pi\\epsilon_0 R}$"
  * NEVER write raw LaTeX without $ delimiters (e.g. write "$\\frac{a}{b}$" not "\\frac{a}{b}")
- For diagrams/figures: set has_diagram=true and describe them briefly in latex_body as [Diagram: description].
- IMPORTANT: If the question contains a data table, grid, or 'Match the Following' columns, DO NOT treat it as a diagram. Instead, format it natively as a LaTeX table using \\begin{array}{|c|c|} ... \\end{array}.
- IMPORTANT: If the multiple choice options (A, B, C, D) themselves are images, graphs, or complex diagrams, set "has_diagram"=true, mention "[Diagram: Options]" in latex_body, and leave the option "text" fields EMPTY strings (""). The system will capture the options as an image.
- Mark correct answers if the answer key is visible in the PDF
- Detect subject + topic (e.g. "Physics - Electrostatics", "Chemistry - Organic", "Mathematics - Calculus")
- Marks: MCQ=4, Numerical=3 unless specified in the paper
- Return only the FIRST 5 questions found in the document. Do not attempt to parse the entire document.

Return ONLY a valid JSON array. No markdown. No explanation. Just raw JSON:
[
  {
    "question_number": 1,
    "page_number": 3,
    "type": "mcq",
    "latex_body": "full question text with proper LaTeX",
    "topic": "Physics - Electrostatics",
    "difficulty": "hard",
    "marks": 4,
    "has_diagram": false,
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
      const geminiModel = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });

      console.log('Sending PDF to Gemini vision...');
      const result = await geminiModel.generateContent({
        contents: [{ role: 'user', parts: [
          { inlineData: { mimeType: 'application/pdf', data: pdfBuffer.toString('base64') } },
          { text: prompt }
        ]}],
        generationConfig: { responseMimeType: 'application/json', temperature: 0.1 }
      });
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
      fs.writeFileSync('last_ai_error.log', JSON.stringify({ error: parseErr.message, response: responseText }));
      return res.status(500).json({
        error: `AI Error: ${parseErr.message}. Output may be too long. Try parsing fewer questions at a time.`,
        ai_response_preview: responseText.substring(0, 300),
      });
    }

    // Step 5: Render PDF pages to images for diagram cropping
    let pagesDirectory = null;
    try {
      console.log(`Rendering ${pdfData.numpages} PDF pages to images...`);
      pagesDirectory = await renderPdfPages(req.file.path, pdfData.numpages);
      console.log(`Pages rendered to: ${pagesDirectory}`);
    } catch (renderErr) {
      console.warn('PDF page rendering failed (diagrams will not be available):', renderErr.message);
    }

    // Step 6: Auto-detect and crop diagrams for ALL questions.
    // Check both the question page and the next page (diagrams may spill across page breaks).
    // We try every question (not just has_diagram=true) because AI sometimes misses the flag.
    if (pagesDirectory) {
      console.log('Auto-detecting diagrams for all questions...');
      for (const q of questions) {
        if (!q.page_number) continue;
        const pagesToCheck = [q.page_number, q.page_number + 1];
        for (const pg of pagesToCheck) {
          const croppedUrl = await detectAndCropDiagram(pagesDirectory, pg, q.question_number);
          if (croppedUrl) {
            q.cropped_image_url = croppedUrl;
            q.has_diagram = true;
            console.log(`Q${q.question_number}: diagram cropped from page ${pg} → ${croppedUrl}`);
            break;
          }
        }
        if (!q.cropped_image_url) {
          console.log(`Q${q.question_number}: no diagram found`);
        }
      }
    }

    // Step 7: Save paper record to DB
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
      pages_directory: pagesDirectory,
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
    const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });

    const prompt = `You are an expert at parsing Indian Math Olympiad question papers.
Parse this text into a structured JSON array of questions with LaTeX formatting.
Return ONLY valid JSON. No markdown. No explanation.
IMPORTANT: Return only the first 15 questions. Keep latex_body under 200 chars.

Text:
${rawText.substring(0, 6000)}

Format: [{"question_number":1,"type":"mcq|numerical|proof","latex_body":"...","topic":"...","difficulty":"easy|medium|hard","marks":3,"options":[{"label":"A","text":"...","is_correct":false}],"correct_value":null,"tolerance":0}]`;

    const result = await model.generateContent({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: { responseMimeType: 'application/json', temperature: 0.1 },
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

  // pdf2pic saves as "page.N.png" (dot separator)
  const imagePath = path.join(uploadsDir, 'pages', pages_directory, `page.${page_number}.png`);
  if (!fs.existsSync(imagePath)) {
    return res.status(404).json({ error: 'Page image not found' });
  }

  try {
    const croppedUrl = await detectAndCropDiagram(pages_directory, page_number, question_number);
    if (croppedUrl) {
      res.json({ cropped_image_url: croppedUrl });
    } else {
      res.json({ cropped_image_url: null });
    }
  } catch (err) {
    console.error('Diagram detection error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// Upload a manual diagram image for a question
router.post('/upload-diagram', authenticate, authorize('teacher', 'admin'), uploadImage.single('image'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No image uploaded' });
  }
  try {
    const fileUrl = req.file.path; // Cloudinary returns full URL here
    res.json({ cropped_image_url: fileUrl });
  } catch (err) {
    console.error('Manual diagram upload error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
