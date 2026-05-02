/**
 * 配對路由
 * 處理配對碼生成、連接、解除配對
 */
const express = require('express');
const db = require('../config/database');
const auth = require('../middleware/auth');

const router = express.Router();

/**
 * POST /api/pair/generate
 * 生成 6 位配對碼（5 分鐘有效）
 */
router.post('/generate', auth, async (req, res) => {
  try {
    // 檢查是否已有配對
    const [users] = await db.query('SELECT partner_id FROM users WHERE id = ?', [req.userId]);
    if (users[0].partner_id) {
      return res.status(400).json({ success: false, error: '你已經有配對對象了' });
    }

    // 刪除此用戶舊的配對碼
    await db.query('DELETE FROM pair_codes WHERE user_id = ?', [req.userId]);

    // 生成不重複的 6 位數字碼
    let code;
    let attempts = 0;
    do {
      code = String(Math.floor(100000 + Math.random() * 900000));
      const [existing] = await db.query(
        'SELECT id FROM pair_codes WHERE code = ? AND expires_at > NOW()',
        [code]
      );
      if (existing.length === 0) break;
      attempts++;
    } while (attempts < 10);

    if (attempts >= 10) {
      return res.status(500).json({ success: false, error: '無法生成配對碼，請稍後再試' });
    }

    // 存入資料庫，5 分鐘後過期
    await db.query(
      'INSERT INTO pair_codes (user_id, code, expires_at) VALUES (?, ?, DATE_ADD(NOW(), INTERVAL 5 MINUTE))',
      [req.userId, code]
    );

    res.json({
      success: true,
      data: {
        code,
        expires_in: 300, // 秒
      },
    });
  } catch (err) {
    console.error('[Pair] 生成配對碼錯誤:', err);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

/**
 * POST /api/pair/connect
 * 輸入配對碼綁定
 */
router.post('/connect', auth, async (req, res) => {
  try {
    const { code } = req.body;

    if (!code || code.length !== 6) {
      return res.status(400).json({ success: false, error: '請提供 6 位配對碼' });
    }

    // 檢查自己是否已有配對
    const [self] = await db.query('SELECT partner_id FROM users WHERE id = ?', [req.userId]);
    if (self[0].partner_id) {
      return res.status(400).json({ success: false, error: '你已經有配對對象了' });
    }

    // 查詢有效的配對碼
    const [codes] = await db.query(
      'SELECT * FROM pair_codes WHERE code = ? AND expires_at > NOW()',
      [code]
    );

    if (codes.length === 0) {
      return res.status(404).json({ success: false, error: '配對碼無效或已過期' });
    }

    const pairCode = codes[0];

    // 不能跟自己配對
    if (pairCode.user_id === req.userId) {
      return res.status(400).json({ success: false, error: '不能跟自己配對' });
    }

    // 檢查對方是否已有配對
    const [partner] = await db.query('SELECT partner_id FROM users WHERE id = ?', [pairCode.user_id]);
    if (partner[0].partner_id) {
      return res.status(400).json({ success: false, error: '對方已經有配對對象了' });
    }

    // 建立雙向配對
    const conn = await db.getConnection();
    try {
      await conn.beginTransaction();

      await conn.query('UPDATE users SET partner_id = ? WHERE id = ?', [pairCode.user_id, req.userId]);
      await conn.query('UPDATE users SET partner_id = ? WHERE id = ?', [req.userId, pairCode.user_id]);

      // 刪除已使用的配對碼
      await conn.query('DELETE FROM pair_codes WHERE id = ?', [pairCode.id]);

      await conn.commit();
    } catch (txErr) {
      await conn.rollback();
      throw txErr;
    } finally {
      conn.release();
    }

    // 查詢配對對象的完整資料
    const [partnerInfo] = await db.query(
      'SELECT id, email, name FROM users WHERE id = ?',
      [pairCode.user_id]
    );

    res.json({
      success: true,
      data: {
        is_paired: true,
        partner_uid: String(pairCode.user_id),
        partner: partnerInfo.length > 0 ? {
          uid: String(partnerInfo[0].id),
          email: partnerInfo[0].email,
          name: partnerInfo[0].name || '',
        } : null,
      },
    });
  } catch (err) {
    console.error('[Pair] 配對連接錯誤:', err);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

/**
 * DELETE /api/pair
 * 解除配對
 */
router.delete('/', auth, async (req, res) => {
  try {
    const [users] = await db.query('SELECT partner_id FROM users WHERE id = ?', [req.userId]);
    const partnerId = users[0].partner_id;

    if (!partnerId) {
      return res.status(400).json({ success: false, error: '你目前沒有配對對象' });
    }

    // 解除雙向配對
    const conn = await db.getConnection();
    try {
      await conn.beginTransaction();

      await conn.query('UPDATE users SET partner_id = NULL WHERE id = ?', [req.userId]);
      await conn.query('UPDATE users SET partner_id = NULL WHERE id = ?', [partnerId]);

      await conn.commit();
    } catch (txErr) {
      await conn.rollback();
      throw txErr;
    } finally {
      conn.release();
    }

    res.json({ success: true, data: { message: '已解除配對' } });
  } catch (err) {
    console.error('[Pair] 解除配對錯誤:', err);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

/**
 * GET /api/pair/status
 * 取得配對狀態
 */
router.get('/status', auth, async (req, res) => {
  try {
    const [users] = await db.query(
      `SELECT u.partner_id, p.name AS partner_name, p.email AS partner_email
       FROM users u
       LEFT JOIN users p ON u.partner_id = p.id
       WHERE u.id = ?`,
      [req.userId]
    );

    const user = users[0];

    if (!user.partner_id) {
      return res.json({
        success: true,
        data: { is_paired: false, partner_uid: null, partner: null },
      });
    }

    res.json({
      success: true,
      data: {
        is_paired: true,
        partner_uid: String(user.partner_id),
        partner: {
          uid: String(user.partner_id),
          name: user.partner_name || '',
          email: user.partner_email || '',
        },
      },
    });
  } catch (err) {
    console.error('[Pair] 配對狀態錯誤:', err);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

module.exports = router;
