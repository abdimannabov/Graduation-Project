const express = require('express');
const router = express.Router();
const { getUserByEmail, getSiteInfo } = require('../services/moodle.service');

router.post('/verify-user', async (req, res) => {
  const { email } = req.body;
  const user = await getUserByEmail(email);

  if (!user) {
    return res.status(404).json({ error: 'User not found in Moodle' });
  }

  res.json({
    moodle_user_id: user.id,
    fullname: user.fullname,
  });
});

// Health/ping endpoint to validate Moodle connectivity/token using GET so it can be visited in a browser
router.get('/ping', async (req, res) => {
  try {
    const info = await getSiteInfo();
    res.json({ ok: true, info });
  } catch (err) {
    res.status(502).json({ ok: false, error: err.message });
  }
});

module.exports = router;
