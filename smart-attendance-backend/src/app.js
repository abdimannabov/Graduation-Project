const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');

const moodleRoutes = require('./routes/moodle.routes');
const attendanceRoutes = require('./routes/attendance.route');
const { handleError } = require('./utils/errors');

const app = express();

app.use((req, res, next) => {
  console.log(`[REQ] ${req.method} ${req.url}`);
  next();
});

app.use(cors());
app.use(bodyParser.json());

app.use('/api/moodle', moodleRoutes);
app.use('/api/attendance', attendanceRoutes);

app.use((err, req, res, next) => {
  if (res.headersSent) return next(err);
  return handleError(err, res);
});

module.exports = app;
