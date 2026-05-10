require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');

const pool = require('./config/db');
const authRoutes = require('./routes/auth');
const examRoutes = require('./routes/exams');
const questionRoutes = require('./routes/questions');
const submissionRoutes = require('./routes/submissions');
const hintRoutes = require('./routes/hints');
const userRoutes = require('./routes/users');
const pdfRoutes = require('./routes/pdf');

const app = express();

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use('/uploads', express.static(path.join(__dirname, '../uploads')));

app.use('/api/auth', authRoutes);
app.use('/api/exams', examRoutes);
app.use('/api/questions', questionRoutes);
app.use('/api/submissions', submissionRoutes);
app.use('/api/hints', hintRoutes);
app.use('/api/users', userRoutes);
app.use('/api/pdf', pdfRoutes);

app.get('/api/health', async (req, res) => {
  const start = Date.now();
  try {
    const result = await pool.query('SELECT NOW() AS db_time');
    res.json({
      status: 'ok',
      version: '1.0.0',
      uptime_seconds: Math.floor(process.uptime()),
      db: {
        status: 'connected',
        time: result.rows[0].db_time,
        latency_ms: Date.now() - start,
      },
      server_time: new Date().toISOString(),
    });
  } catch (err) {
    res.status(503).json({
      status: 'degraded',
      version: '1.0.0',
      uptime_seconds: Math.floor(process.uptime()),
      db: {
        status: 'error',
        error: err.message,
      },
      server_time: new Date().toISOString(),
    });
  }
});

app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Something went wrong' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`MathKraft backend running on port ${PORT}`);
});
