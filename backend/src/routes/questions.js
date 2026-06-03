const express = require('express');
const multer = require('multer');
const path = require('path');
const pool = require('../config/db');
const { authenticate, authorize } = require('../middleware/auth');
const router = express.Router();

const { storage } = require('../config/cloudinary');

const upload = multer({ storage, limits: { fileSize: 10 * 1024 * 1024 } });

// Teacher: add question to exam
router.post('/', authenticate, authorize('teacher', 'admin'), upload.single('image'), async (req, res) => {
  const { exam_id, question_number, type, latex_body, marks, partial_marks, topic, difficulty } = req.body;
  const image_url = req.file ? req.file.path : null; // Cloudinary returns full URL in req.file.path
  try {
    const result = await pool.query(
      'INSERT INTO questions (exam_id, question_number, type, latex_body, image_url, marks, partial_marks, topic, difficulty) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *',
      [exam_id, question_number, type, latex_body, image_url, marks, partial_marks, topic, difficulty]
    );
    const question = result.rows[0];

    if (type === 'mcq' && req.body.options) {
      const options = JSON.parse(req.body.options);
      for (const opt of options) {
        await pool.query(
          'INSERT INTO mcq_options (question_id, option_label, latex_option, is_correct) VALUES ($1,$2,$3,$4)',
          [question.id, opt.label, opt.text, opt.is_correct]
        );
      }
    }

    if (type === 'numerical' && req.body.correct_value !== undefined) {
      await pool.query(
        'INSERT INTO numerical_answers (question_id, correct_value, tolerance) VALUES ($1,$2,$3)',
        [question.id, req.body.correct_value, req.body.tolerance || 0]
      );
    }

    // Keep exam total_marks in sync
    await pool.query(
      'UPDATE exams SET total_marks = (SELECT COALESCE(SUM(marks),0) FROM questions WHERE exam_id=$1) WHERE id=$1',
      [exam_id]
    );

    res.status(201).json(question);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Update question (latex_body, marks, topic, difficulty + MCQ options + numerical answer)
router.put('/:id', authenticate, authorize('teacher', 'admin'), upload.single('image'), async (req, res) => {
  const { latex_body, marks, topic, difficulty, type, options, correct_value, tolerance, remove_image } = req.body;
  const new_image_url = req.file ? req.file.path : null; // Cloudinary returns full URL in req.file.path
  const shouldRemoveImage = remove_image === 'true' || remove_image === true;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    let result;
    if (new_image_url) {
      result = await client.query(
        'UPDATE questions SET latex_body=$1, marks=$2, topic=$3, difficulty=$4, image_url=$5 WHERE id=$6 RETURNING *',
        [latex_body, marks, topic, difficulty, new_image_url, req.params.id]
      );
    } else if (shouldRemoveImage) {
      result = await client.query(
        'UPDATE questions SET latex_body=$1, marks=$2, topic=$3, difficulty=$4, image_url=NULL WHERE id=$5 RETURNING *',
        [latex_body, marks, topic, difficulty, req.params.id]
      );
    } else {
      result = await client.query(
        'UPDATE questions SET latex_body=$1, marks=$2, topic=$3, difficulty=$4 WHERE id=$5 RETURNING *',
        [latex_body, marks, topic, difficulty, req.params.id]
      );
    }
    const question = result.rows[0];

    if (type === 'mcq' && options) {
      await client.query('DELETE FROM mcq_options WHERE question_id=$1', [req.params.id]);
      for (const opt of options) {
        await client.query(
          'INSERT INTO mcq_options (question_id, option_label, latex_option, is_correct) VALUES ($1,$2,$3,$4)',
          [req.params.id, opt.label, opt.text, opt.is_correct]
        );
      }
    }

    if (type === 'numerical' && correct_value !== undefined) {
      await client.query('DELETE FROM numerical_answers WHERE question_id=$1', [req.params.id]);
      await client.query(
        'INSERT INTO numerical_answers (question_id, correct_value, tolerance) VALUES ($1,$2,$3)',
        [req.params.id, correct_value, tolerance || 0]
      );
    }

    // Recalculate exam total_marks
    await client.query(
      'UPDATE exams SET total_marks = (SELECT COALESCE(SUM(marks),0) FROM questions WHERE exam_id=(SELECT exam_id FROM questions WHERE id=$1)) WHERE id=(SELECT exam_id FROM questions WHERE id=$1)',
      [req.params.id]
    );

    await client.query('COMMIT');
    res.json(question);
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ error: err.message });
  } finally {
    client.release();
  }
});

// Delete question
router.delete('/:id', authenticate, authorize('teacher', 'admin'), async (req, res) => {
  try {
    // Get exam_id before deleting
    const q = await pool.query('SELECT exam_id FROM questions WHERE id=$1', [req.params.id]);
    if (!q.rows.length) return res.status(404).json({ error: 'Question not found' });
    const examId = q.rows[0].exam_id;

    // Delete all related records first (foreign key constraints)
    await pool.query('DELETE FROM hints WHERE question_id = $1', [req.params.id]);
    await pool.query('DELETE FROM answers WHERE question_id = $1', [req.params.id]);
    await pool.query('DELETE FROM mcq_options WHERE question_id = $1', [req.params.id]);
    await pool.query('DELETE FROM numerical_answers WHERE question_id = $1', [req.params.id]);
    await pool.query('DELETE FROM questions WHERE id = $1', [req.params.id]);

    // Recalculate total_marks
    await pool.query(
      'UPDATE exams SET total_marks = (SELECT COALESCE(SUM(marks),0) FROM questions WHERE exam_id=$1) WHERE id=$1',
      [examId]
    );

    res.json({ message: 'Question deleted' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
