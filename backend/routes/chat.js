/**
 * 聊天路由
 * 處理聊天歷史查詢（即時聊天透過 WebSocket）
 */
const express = require('express');
const db = require('../config/database');
const auth = require('../middleware/auth');

const router = express.Router();

/**
 * GET /api/chat/history
 * 查詢聊天歷史（分頁）
 * Query params:
 *   - before: 在此訊息 ID 之前的訊息（用於向上捲動載入）
 *   - limit: 每頁筆數（預設 50，最大 100）
 */
router.get('/history', auth, async (req, res) => {
  try {
    // 取得配對對象
    const [users] = await db.query('SELECT partner_id FROM users WHERE id = ?', [req.userId]);
    const partnerId = users[0].partner_id;

    if (!partnerId) {
      return res.status(400).json({ success: false, error: '尚未配對，無聊天記錄' });
    }

    const { before, limit } = req.query;
    const pageSize = Math.min(parseInt(limit, 10) || 50, 100);

    // 查詢雙方的訊息
    let sql = `
      SELECT id, sender_id, receiver_id, text, created_at
      FROM messages
      WHERE (sender_id = ? AND receiver_id = ?)
         OR (sender_id = ? AND receiver_id = ?)
    `;
    const params = [req.userId, partnerId, partnerId, req.userId];

    // 分頁：用 before cursor（訊息 ID）
    if (before) {
      sql += ' AND id < ?';
      params.push(parseInt(before, 10));
    }

    sql += ' ORDER BY id DESC LIMIT ?';
    params.push(pageSize);

    const [rows] = await db.query(sql, params);

    // 回傳時反轉為時間正序
    res.json({
      success: true,
      data: {
        messages: rows.reverse(),
        has_more: rows.length === pageSize,
      },
    });
  } catch (err) {
    console.error('[Chat] 查詢歷史錯誤:', err);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

module.exports = router;
