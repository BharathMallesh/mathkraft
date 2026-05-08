require('dotenv').config();
const pool = require('./db');

const createTables = async () => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(`
      CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(255) NOT NULL,
        email VARCHAR(255) UNIQUE NOT NULL,
        password_hash VARCHAR(255) NOT NULL,
        role VARCHAR(20) NOT NULL CHECK (role IN ('student', 'teacher', 'admin')),
        class VARCHAR(10),
        phone VARCHAR(15),
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS exams (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        title VARCHAR(255) NOT NULL,
        description TEXT,
        teacher_id UUID REFERENCES users(id),
        exam_type VARCHAR(20) DEFAULT 'mock' CHECK (exam_type IN ('mock', 'practice', 'diagnostic')),
        duration_minutes INTEGER NOT NULL,
        total_marks INTEGER DEFAULT 0,
        start_time TIMESTAMP,
        is_published BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS questions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        exam_id UUID REFERENCES exams(id) ON DELETE CASCADE,
        question_number INTEGER NOT NULL,
        type VARCHAR(20) NOT NULL CHECK (type IN ('mcq', 'numerical', 'proof')),
        latex_body TEXT NOT NULL,
        image_url VARCHAR(500),
        marks INTEGER DEFAULT 1,
        partial_marks INTEGER DEFAULT 0,
        topic VARCHAR(100),
        difficulty VARCHAR(20) DEFAULT 'medium' CHECK (difficulty IN ('easy', 'medium', 'hard')),
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS mcq_options (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        question_id UUID REFERENCES questions(id) ON DELETE CASCADE,
        option_label VARCHAR(5) NOT NULL,
        latex_option TEXT NOT NULL,
        is_correct BOOLEAN DEFAULT FALSE
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS numerical_answers (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        question_id UUID REFERENCES questions(id) ON DELETE CASCADE,
        correct_value NUMERIC NOT NULL,
        tolerance NUMERIC DEFAULT 0
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS submissions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        student_id UUID REFERENCES users(id),
        exam_id UUID REFERENCES exams(id),
        started_at TIMESTAMP DEFAULT NOW(),
        submitted_at TIMESTAMP,
        total_marks_awarded INTEGER DEFAULT 0,
        status VARCHAR(20) DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'submitted', 'graded'))
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS answers (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        submission_id UUID REFERENCES submissions(id) ON DELETE CASCADE,
        question_id UUID REFERENCES questions(id),
        UNIQUE(submission_id, question_id),
        selected_option VARCHAR(5),
        numerical_value NUMERIC,
        proof_photo_url VARCHAR(500),
        marks_awarded INTEGER DEFAULT 0,
        error_type VARCHAR(30) CHECK (error_type IN ('conceptual_gap', 'calculation_slip', 'logical_fallacy')),
        teacher_feedback TEXT,
        is_graded BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS hints (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        question_id UUID REFERENCES questions(id),
        student_id UUID REFERENCES users(id),
        hint_level INTEGER DEFAULT 1,
        hint_text TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS student_progress (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        student_id UUID REFERENCES users(id),
        topic VARCHAR(100) NOT NULL,
        strength_score NUMERIC DEFAULT 50,
        questions_attempted INTEGER DEFAULT 0,
        questions_correct INTEGER DEFAULT 0,
        last_updated TIMESTAMP DEFAULT NOW(),
        UNIQUE(student_id, topic)
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS question_papers (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        title VARCHAR(255) NOT NULL,
        file_name VARCHAR(255),
        file_url VARCHAR(500),
        file_size_kb INTEGER,
        pages INTEGER,
        teacher_id UUID REFERENCES users(id),
        questions_extracted INTEGER DEFAULT 0,
        raw_text TEXT,
        parsed_questions JSONB,
        exam_id UUID REFERENCES exams(id),
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);

    await client.query('COMMIT');
    console.log('All tables created successfully');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migration failed:', err);
  } finally {
    client.release();
    pool.end();
  }
};

createTables();
