/**
 * 地理圍欄路由
 * CRUD 操作
 */
const express = require('express');
const db = require('../config/database');
const auth = require('../middleware/auth');

const router = express.Router();

/**
 * GET /api/geofences
 * 列出用戶的所有圍欄（包含配對對象的）
 */
router.get('/', auth, async (req, res) => {
  try {
    const [users] = await db.query('SELECT partner_id FROM users WHERE id = ?', [req.userId]);
    const partnerId = users[0].partner_id;

    // 只查詢自己的圍欄（對方的圍欄由對方手機監控）
    const sql = 'SELECT * FROM geofences WHERE user_id = ? ORDER BY created_at DESC';
    const params = [req.userId];

    const [rows] = await db.query(sql, params);

    res.json({ success: true, data: rows });
  } catch (err) {
    console.error('[Geofence] 列出錯誤:', err);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

/**
 * POST /api/geofences
 * 新增圍欄
 */
router.post('/', auth, async (req, res) => {
  try {
    const { name, lat, lng, radius, notify_type } = req.body;

    // 驗證必填欄位
    if (!name || lat == null || lng == null) {
      return res.status(400).json({ success: false, error: '請提供名稱、經度和緯度' });
    }

    const [result] = await db.query(
      'INSERT INTO geofences (user_id, name, lat, lng, radius, notify_type) VALUES (?, ?, ?, ?, ?, ?)',
      [req.userId, name, lat, lng, radius || 200, notify_type || 'both']
    );

    const [rows] = await db.query('SELECT * FROM geofences WHERE id = ?', [result.insertId]);

    res.status(201).json({ success: true, data: rows[0] });
  } catch (err) {
    console.error('[Geofence] 新增錯誤:', err);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

/**
 * PUT /api/geofences/:id
 * 更新圍欄
 */
router.put('/:id', auth, async (req, res) => {
  try {
    const { id } = req.params;
    const { name, lat, lng, radius, notify_type, is_active } = req.body;

    // 確認圍欄屬於此用戶
    const [existing] = await db.query('SELECT * FROM geofences WHERE id = ? AND user_id = ?', [id, req.userId]);
    if (existing.length === 0) {
      return res.status(404).json({ success: false, error: '圍欄不存在或無權限' });
    }

    // 動態建構更新語句
    const updates = [];
    const params = [];

    if (name !== undefined) { updates.push('name = ?'); params.push(name); }
    if (lat !== undefined) { updates.push('lat = ?'); params.push(lat); }
    if (lng !== undefined) { updates.push('lng = ?'); params.push(lng); }
    if (radius !== undefined) { updates.push('radius = ?'); params.push(radius); }
    if (notify_type !== undefined) { updates.push('notify_type = ?'); params.push(notify_type); }
    if (is_active !== undefined) { updates.push('is_active = ?'); params.push(is_active ? 1 : 0); }

    if (updates.length === 0) {
      return res.status(400).json({ success: false, error: '沒有要更新的欄位' });
    }

    params.push(id);
    await db.query(`UPDATE geofences SET ${updates.join(', ')} WHERE id = ?`, params);

    const [rows] = await db.query('SELECT * FROM geofences WHERE id = ?', [id]);

    res.json({ success: true, data: rows[0] });
  } catch (err) {
    console.error('[Geofence] 更新錯誤:', err);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

/**
 * DELETE /api/geofences/:id
 * 刪除圍欄
 */
router.delete('/:id', auth, async (req, res) => {
  try {
    const { id } = req.params;

    // 確認圍欄屬於此用戶
    const [existing] = await db.query('SELECT id FROM geofences WHERE id = ? AND user_id = ?', [id, req.userId]);
    if (existing.length === 0) {
      return res.status(404).json({ success: false, error: '圍欄不存在或無權限' });
    }

    await db.query('DELETE FROM geofences WHERE id = ?', [id]);

    res.json({ success: true, data: { message: '圍欄已刪除' } });
  } catch (err) {
    console.error('[Geofence] 刪除錯誤:', err);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

module.exports = router;
