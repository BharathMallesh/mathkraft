const express = require('express');
const pool = require('../config/db');
const { authenticate, authorize } = require('../middleware/auth');
const router = express.Router();

// Teacher: create exam
router.post('/', authenticate, authorize('teacher', 'admin'), async (req, res) => {
  const { title, description, exam_type, duration_minutes, start_time, target_class } = req.body;
  try {
    const result = await pool.query(
      'INSERT INTO exams (title, description, teacher_id, exam_type, duration_minutes, start_time, target_class) VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *',
      [title, description, req.user.id, exam_type, duration_minutes, start_time, target_class || 'all']
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Teacher: publish exam
router.patch('/:id/publish', authenticate, authorize('teacher', 'admin'), async (req, res) => {
  try {
    const result = await pool.query(
      'UPDATE exams SET is_published = TRUE WHERE id = $1 AND teacher_id = $2 RETURNING *',
      [req.params.id, req.user.id]
    );
    if (!result.rows.length) return res.status(404).json({ error: 'Exam not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Student: get published exams (filtered by student's class)
router.get('/', authenticate, async (req, res) => {
  try {
    const studentClass = req.user.role === 'student'
      ? (await pool.query('SELECT class FROM users WHERE id=$1', [req.user.id])).rows[0]?.class
      : null;

    const result = await pool.query(
      `SELECT e.*, u.name as teacher_name,
       (SELECT COUNT(*) FROM questions WHERE exam_id = e.id) as question_count
       FROM exams e JOIN users u ON e.teacher_id = u.id
       WHERE e.is_published = TRUE
         AND (e.target_class = 'all' OR e.target_class = $1)
       ORDER BY e.created_at DESC`,
      [studentClass || 'all']
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Get single exam with questions
router.get('/:id', authenticate, async (req, res) => {
  try {
    const exam = await pool.query('SELECT * FROM exams WHERE id = $1', [req.params.id]);
    if (!exam.rows.length) return res.status(404).json({ error: 'Exam not found' });

    const questions = await pool.query(
      'SELECT * FROM questions WHERE exam_id = $1 ORDER BY question_number',
      [req.params.id]
    );

    for (let q of questions.rows) {
      if (q.type === 'mcq') {
        const options = await pool.query('SELECT * FROM mcq_options WHERE question_id = $1', [q.id]);
        q.options = options.rows;
      }
      if (q.type === 'numerical') {
        const na = await pool.query('SELECT * FROM numerical_answers WHERE question_id = $1', [q.id]);
        if (na.rows.length) q.numerical_answer = na.rows[0];
      }
    }

    res.json({ ...exam.rows[0], questions: questions.rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Teacher: get my exams
router.get('/teacher/my-exams', authenticate, authorize('teacher', 'admin'), async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM exams WHERE teacher_id = $1 ORDER BY created_at DESC',
      [req.user.id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
