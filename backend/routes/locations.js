/**
 * 位置路由
 * 處理位置歷史查詢（即時位置透過 WebSocket）
 */
const express = require('express');
const db = require('../config/database');
const auth = require('../middleware/auth');

const router = express.Router();

/**
 * GET /api/locations/history
 * 查詢位置歷史
 * Query params:
 *   - user_id: 查詢對象（自己或配對對象）
 *   - start: 開始時間 (ISO 8601)
 *   - end: 結束時間 (ISO 8601)
 *   - limit: 筆數限制（預設 100，最大 1000）
 */
router.get('/history', auth, async (req, res) => {
  try {
    const { user_id, start, end, limit } = req.query;

    // 確認查詢對象是自己或配對對象
    const [users] = await db.query('SELECT partner_id FROM users WHERE id = ?', [req.userId]);
    const partnerId = users[0].partner_id;

    const targetId = user_id ? parseInt(user_id, 10) : req.userId;

    if (targetId !== req.userId && targetId !== partnerId) {
      return res.status(403).json({ success: false, error: '只能查詢自己或配對對象的位置' });
    }

    // 建構查詢
    let sql = 'SELECT id, user_id, lat, lng, accuracy, battery, created_at FROM locations WHERE user_id = ?';
    const params = [targetId];

    if (start) {
      sql += ' AND created_at >= ?';
      params.push(new Date(start));
    }

    if (end) {
      sql += ' AND created_at <= ?';
      params.push(new Date(end));
    }

    sql += ' ORDER BY created_at DESC';

    const maxLimit = Math.min(parseInt(limit, 10) || 100, 1000);
    sql += ' LIMIT ?';
    params.push(maxLimit);

    const [rows] = await db.query(sql, params);

    res.json({ success: true, data: rows });
  } catch (err) {
    console.error('[Location] 查詢歷史錯誤:', err);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

module.exports = router;
