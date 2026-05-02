/**
 * SOS 路由
 * 發送緊急求救，觸發推播通知
 */
const express = require('express');
const db = require('../config/database');
const auth = require('../middleware/auth');
const { sendPush } = require('../utils/apns');

const router = express.Router();

/**
 * POST /api/sos
 * 發送 SOS 警報
 * Body: { lat, lng }（可選，附帶當前位置）
 */
router.post('/', auth, async (req, res) => {
  try {
    const { lat, lng } = req.body;

    // 取得用戶和配對對象資訊
    const [users] = await db.query(
      `SELECT u.id, u.name, u.email, u.partner_id, p.device_token AS partner_device_token, p.name AS partner_name
       FROM users u
       LEFT JOIN users p ON u.partner_id = p.id
       WHERE u.id = ?`,
      [req.userId]
    );

    const user = users[0];

    if (!user.partner_id) {
      return res.status(400).json({ success: false, error: '尚未配對，無法發送 SOS' });
    }

    // 存入 SOS 記錄
    await db.query(
      'INSERT INTO sos_alerts (sender_id, lat, lng) VALUES (?, ?, ?)',
      [req.userId, lat || null, lng || null]
    );

    // 發送推播通知給配對對象
    const senderName = user.name || user.email;
    await sendPush(
      user.partner_device_token,
      '🆘 緊急求救！',
      `${senderName} 發送了 SOS 求救信號！`,
      {
        type: 'sos',
        sender_id: req.userId,
        lat: lat || null,
        lng: lng || null,
      }
    );

    // 同時透過 WebSocket 通知（如果對方在線）
    const wsService = require('../services/websocket');
    wsService.sendToUser(user.partner_id, {
      type: 'sos',
      sender_id: req.userId,
      sender_name: senderName,
      lat: lat || null,
      lng: lng || null,
      timestamp: new Date().toISOString(),
    });

    res.json({ success: true, data: { message: 'SOS 已發送' } });
  } catch (err) {
    console.error('[SOS] 發送錯誤:', err);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

module.exports = router;
