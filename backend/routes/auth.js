/**
 * 認證路由
 * 處理註冊、登入、取得用戶資料
 */
const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../config/database');
const auth = require('../middleware/auth');

const router = express.Router();

/**
 * POST /api/auth/register
 * 註冊新用戶
 */
router.post('/register', async (req, res) => {
  try {
    const { email, password, name } = req.body;

    // 驗證必填欄位
    if (!email || !password) {
      return res.status(400).json({ success: false, error: '請提供 email 和密碼' });
    }

    // 驗證 email 格式
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return res.status(400).json({ success: false, error: 'Email 格式不正確' });
    }

    // 密碼長度檢查
    if (password.length < 6) {
      return res.status(400).json({ success: false, error: '密碼至少需要 6 個字元' });
    }

    // 檢查 email 是否已存在
    const [existing] = await db.query('SELECT id FROM users WHERE email = ?', [email]);
    if (existing.length > 0) {
      return res.status(409).json({ success: false, error: '此 Email 已被註冊' });
    }

    // 雜湊密碼並建立用戶
    const passwordHash = await bcrypt.hash(password, 12);
    const [result] = await db.query(
      'INSERT INTO users (email, password_hash, name) VALUES (?, ?, ?)',
      [email, passwordHash, name || null]
    );

    // 產生 JWT
    const token = jwt.sign({ userId: result.insertId }, process.env.JWT_SECRET, {
      expiresIn: '30d',
    });

    res.status(201).json({
      success: true,
      data: {
        token,
        user: {
          id: result.insertId,
          email,
          name: name || null,
        },
      },
    });
  } catch (err) {
    console.error('[Auth] 註冊錯誤:', err);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

/**
 * POST /api/auth/login
 * 用戶登入
 */
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ success: false, error: '請提供 email 和密碼' });
    }

    // 查詢用戶
    const [users] = await db.query('SELECT * FROM users WHERE email = ?', [email]);
    if (users.length === 0) {
      return res.status(401).json({ success: false, error: 'Email 或密碼錯誤' });
    }

    const user = users[0];

    // 驗證密碼
    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) {
      return res.status(401).json({ success: false, error: 'Email 或密碼錯誤' });
    }

    // 產生 JWT
    const token = jwt.sign({ userId: user.id }, process.env.JWT_SECRET, {
      expiresIn: '30d',
    });

    res.json({
      success: true,
      data: {
        token,
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          partner_id: user.partner_id,
        },
      },
    });
  } catch (err) {
    console.error('[Auth] 登入錯誤:', err);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

/**
 * GET /api/auth/me
 * 取得當前用戶資料
 */
router.get('/me', auth, async (req, res) => {
  try {
    const [users] = await db.query(
      'SELECT id, email, name, partner_id, device_token, created_at FROM users WHERE id = ?',
      [req.userId]
    );

    if (users.length === 0) {
      return res.status(404).json({ success: false, error: '用戶不存在' });
    }

    res.json({ success: true, data: users[0] });
  } catch (err) {
    console.error('[Auth] 取得用戶錯誤:', err);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

/**
 * PUT /api/auth/device-token
 * 更新裝置推播 Token
 */
router.put('/device-token', auth, async (req, res) => {
  try {
    const { device_token } = req.body;

    await db.query('UPDATE users SET device_token = ? WHERE id = ?', [device_token, req.userId]);

    res.json({ success: true, data: { message: '裝置 Token 已更新' } });
  } catch (err) {
    console.error('[Auth] 更新 Token 錯誤:', err);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

module.exports = router;
