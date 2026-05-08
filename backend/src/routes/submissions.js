const express = require('express');
const multer = require('multer');
const path = require('path');
const pool = require('../config/db');
const { authenticate, authorize } = require('../middleware/auth');
const router = express.Router();

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, path.join(__dirname, '../../uploads')),
  filename: (req, file, cb) => cb(null, `proof-${Date.now()}-${file.originalname}`),
});
const upload = multer({ storage, limits: { fileSize: 20 * 1024 * 1024 } });

// Student: start exam
router.post('/start', authenticate, authorize('student'), async (req, res) => {
  const { exam_id } = req.body;
  try {
    const existing = await pool.query(
      'SELECT * FROM submissions WHERE student_id=$1 AND exam_id=$2 AND status=$3',
      [req.user.id, exam_id, 'in_progress']
    );
    if (existing.rows.length) return res.json(existing.rows[0]);

    const result = await pool.query(
      'INSERT INTO submissions (student_id, exam_id) VALUES ($1,$2) RETURNING *',
      [req.user.id, exam_id]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Student: submit answer
router.post('/answer', authenticate, authorize('student'), upload.single('proof_photo'), async (req, res) => {
  const { submission_id, question_id, selected_option, numerical_value } = req.body;
  const proof_photo_url = req.file ? `/uploads/${req.file.filename}` : null;

  try {
    const question = await pool.query('SELECT * FROM questions WHERE id=$1', [question_id]);
    const q = question.rows[0];
    let marks_awarded = 0;

    if (q.type === 'mcq' && selected_option) {
      const correct = await pool.query(
        'SELECT * FROM mcq_options WHERE question_id=$1 AND option_label=$2 AND is_correct=TRUE',
        [question_id, selected_option]
      );
      if (correct.rows.length) marks_awarded = q.marks;
    } else if (q.type === 'numerical' && numerical_value !== undefined) {
      const ans = await pool.query('SELECT * FROM numerical_answers WHERE question_id=$1', [question_id]);
      if (ans.rows.length) {
        const diff = Math.abs(parseFloat(numerical_value) - parseFloat(ans.rows[0].correct_value));
        if (diff <= parseFloat(ans.rows[0].tolerance)) marks_awarded = q.marks;
      }
    }

    const result = await pool.query(
      `INSERT INTO answers (submission_id, question_id, selected_option, numerical_value, proof_photo_url, marks_awarded)
       VALUES ($1,$2,$3,$4,$5,$6)
       ON CONFLICT (submission_id, question_id) DO UPDATE
       SET selected_option=$3, numerical_value=$4, proof_photo_url=$5, marks_awarded=$6
       RETURNING *`,
      [submission_id, question_id, selected_option, numerical_value, proof_photo_url, marks_awarded]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Student: submit exam
router.post('/:id/submit', authenticate, authorize('student'), async (req, res) => {
  try {
    const totalMarks = await pool.query(
      'SELECT COALESCE(SUM(marks_awarded),0) as total FROM answers WHERE submission_id=$1',
      [req.params.id]
    );
    const result = await pool.query(
      'UPDATE submissions SET status=$1, submitted_at=NOW(), total_marks_awarded=$2 WHERE id=$3 RETURNING *',
      ['submitted', totalMarks.rows[0].total, req.params.id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Teacher: grade proof answer
router.patch('/answer/:id/grade', authenticate, authorize('teacher', 'admin'), async (req, res) => {
  const { marks_awarded, error_type, teacher_feedback } = req.body;
  try {
    const result = await pool.query(
      'UPDATE answers SET marks_awarded=$1, error_type=$2, teacher_feedback=$3, is_graded=TRUE WHERE id=$4 RETURNING *',
      [marks_awarded, error_type, teacher_feedback, req.params.id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Student: get my results
router.get('/my-results', authenticate, authorize('student'), async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT s.*, e.title, e.total_marks FROM submissions s
       JOIN exams e ON s.exam_id = e.id
       WHERE s.student_id=$1 ORDER BY s.started_at DESC`,
      [req.user.id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Teacher: get all submissions for an exam
router.get('/exam/:examId', authenticate, authorize('teacher', 'admin'), async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT s.*, u.name as student_name, u.class as student_class
       FROM submissions s JOIN users u ON s.student_id = u.id
       WHERE s.exam_id=$1 ORDER BY s.submitted_at DESC`,
      [req.params.examId]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Teacher/Student: get answers for a submission
router.get('/:id/answers', authenticate, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT a.*, q.latex_body, q.type, q.marks, q.topic
       FROM answers a JOIN questions q ON a.question_id = q.id
       WHERE a.submission_id=$1 ORDER BY q.question_number`,
      [req.params.id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
