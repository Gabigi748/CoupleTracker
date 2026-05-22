/**
 * 通話狀態路由
 * POST /api/call-status — 通知配對對象通話狀態（離線推播用）
 */
const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/auth');
const db = require('../config/database');
const { sendToUser, isUserOnline } = require('../services/websocket');
const { sendPush } = require('../utils/apns');

/**
 * POST /api/call-status
 * Body: { status: "started" | "ended" }
 * 當 WebSocket 不可用時，透過 REST API 通知對方通話狀態
 */
router.post('/', authMiddleware, async (req, res) => {
  try {
    const { status } = req.body;
    const userId = req.userId;

    // 驗證 status
    if (!status || !['started', 'ended'].includes(status)) {
      return res.status(400).json({
        success: false,
        error: 'status 必須是 "started" 或 "ended"',
      });
    }

    // 取得配對對象
    const [users] = await db.query(
      `SELECT u.partner_id, u.name, u.email, p.device_token AS partner_device_token
       FROM users u
       LEFT JOIN users p ON u.partner_id = p.id
       WHERE u.id = ?`,
      [userId]
    );

    const user = users[0];
    if (!user?.partner_id) {
      return res.status(400).json({
        success: false,
        error: '尚未配對',
      });
    }

    const senderName = user.name || user.email;
    const timestamp = new Date().toISOString();

    // 嘗試透過 WebSocket 轉發
    const delivered = sendToUser(user.partner_id, {
      type: 'partner_call_status',
      partnerName: senderName,
      status,
      timestamp,
    });

    // 對方不在線，發推播
    if (!delivered && user.partner_device_token) {
      const title = status === 'started' ? '📞 通話中' : '📞 通話結束';
      const body = status === 'started'
        ? `${senderName} 正在通話中`
        : `${senderName} 已結束通話`;

      await sendPush(user.partner_device_token, title, body, {
        type: 'call_status',
        sender_id: userId,
        status,
      });
    }

    res.json({
      success: true,
      data: { delivered, status, timestamp },
    });
  } catch (err) {
    console.error('[CallStatus] 錯誤:', err.message);
    res.status(500).json({ success: false, error: '伺服器錯誤' });
  }
});

module.exports = router;
