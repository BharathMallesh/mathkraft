const express = require('express');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const pool = require('../config/db');
const { authenticate, authorize } = require('../middleware/auth');
const router = express.Router();

router.post('/', authenticate, authorize('student'), async (req, res) => {
  const { question_id, hint_level = 1, student_working } = req.body;

  try {
    const qResult = await pool.query('SELECT * FROM questions WHERE id=$1', [question_id]);
    const question = qResult.rows[0];
    if (!question) return res.status(404).json({ error: 'Question not found' });

    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });

    const prompt = `You are a Socratic math tutor for Indian Olympiad students (IOQM/RMO/INMO level).

Question (in LaTeX): ${question.latex_body}
Topic: ${question.topic || 'Mathematics'}
Hint Level: ${hint_level} (1=very subtle, 3=more direct)
Student's current working: ${student_working || 'Not provided'}

Give a single Socratic hint that nudges the student toward the solution WITHOUT revealing the answer.
- For hint level 1: mention a relevant mathematical concept or theorem
- For hint level 2: suggest a specific approach or technique
- For hint level 3: give a concrete first step

Keep the hint to 2-3 sentences. Use LaTeX for any math expressions.`;

    const result = await model.generateContent(prompt);
    const hint_text = result.response.text();

    await pool.query(
      'INSERT INTO hints (question_id, student_id, hint_level, hint_text) VALUES ($1,$2,$3,$4)',
      [question_id, req.user.id, hint_level, hint_text]
    );

    res.json({ hint: hint_text, hint_level });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Get hint history for a question
router.get('/:question_id', authenticate, authorize('student'), async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM hints WHERE question_id=$1 AND student_id=$2 ORDER BY hint_level',
      [req.params.question_id, req.user.id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
