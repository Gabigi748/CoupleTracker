/**
 * WebSocket 服務
 * 處理即時位置同步和聊天訊息
 */
const { WebSocketServer } = require('ws');
const jwt = require('jsonwebtoken');
const db = require('../config/database');
const { sendPush } = require('../utils/apns');

// 儲存在線用戶的 WebSocket 連線 { userId: ws }
const clients = new Map();

// 記錄每個用戶最後一次存入 DB 的位置時間（節流用）
const lastLocationSave = new Map();

// 位置存入 DB 的最小間隔（毫秒）
const LOCATION_SAVE_INTERVAL = 30 * 1000;

/**
 * 初始化 WebSocket 伺服器
 * @param {import('http').Server} server - HTTP 伺服器實例
 */
function initWebSocket(server) {
  const wss = new WebSocketServer({ server, path: '/ws' });

  wss.on('connection', async (ws, req) => {
    // 從 URL query 取得 token 進行認證
    const url = new URL(req.url, `http://${req.headers.host}`);
    const token = url.searchParams.get('token');

    if (!token) {
      ws.close(4001, '未提供認證 Token');
      return;
    }

    let userId;
    try {
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      userId = decoded.userId;
    } catch (err) {
      ws.close(4002, 'Token 無效或已過期');
      return;
    }

    // 關閉此用戶的舊連線（如果有的話）
    const existingWs = clients.get(userId);
    if (existingWs && existingWs.readyState === existingWs.OPEN) {
      existingWs.close(4003, '已在其他裝置登入');
    }

    // 註冊連線
    clients.set(userId, ws);
    console.log(`[WS] 用戶 ${userId} 已連線，在線人數: ${clients.size}`);

    // 通知配對對象上線
    notifyPartnerStatus(userId, true);

    // 處理收到的訊息
    ws.on('message', async (raw) => {
      try {
        const data = JSON.parse(raw.toString());
        await handleMessage(userId, data);
      } catch (err) {
        console.error(`[WS] 用戶 ${userId} 訊息處理錯誤:`, err.message);
        ws.send(JSON.stringify({ type: 'error', error: '訊息格式錯誤' }));
      }
    });

    // 處理斷線
    ws.on('close', () => {
      clients.delete(userId);
      lastLocationSave.delete(userId);
      console.log(`[WS] 用戶 ${userId} 已斷線，在線人數: ${clients.size}`);
      notifyPartnerStatus(userId, false);
    });

    // 處理錯誤
    ws.on('error', (err) => {
      console.error(`[WS] 用戶 ${userId} 連線錯誤:`, err.message);
    });

    // 發送連線成功訊息
    ws.send(JSON.stringify({ type: 'connected', userId }));

    // 心跳檢測
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });
  });

  // 每 30 秒檢查心跳
  const heartbeatInterval = setInterval(() => {
    wss.clients.forEach((ws) => {
      if (!ws.isAlive) {
        ws.terminate();
        return;
      }
      ws.isAlive = false;
      ws.ping();
    });
  }, 30000);

  wss.on('close', () => {
    clearInterval(heartbeatInterval);
  });

  console.log('[WS] WebSocket 伺服器已啟動');
  return wss;
}

/**
 * 處理收到的 WebSocket 訊息
 */
async function handleMessage(userId, data) {
  switch (data.type) {
    case 'location':
      await handleLocation(userId, data);
      break;
    case 'chat':
      await handleChat(userId, data);
      break;
    case 'ping':
      sendToUser(userId, { type: 'pong', timestamp: Date.now() });
      break;
    default:
      sendToUser(userId, { type: 'error', error: `未知的訊息類型: ${data.type}` });
  }
}

/**
 * 處理位置更新
 * - 即時轉發給配對對象
 * - 節流存入 DB（每 30 秒最多一筆）
 */
async function handleLocation(userId, data) {
  const { lat, lng, accuracy, battery, timestamp } = data;

  if (lat == null || lng == null) return;

  // 取得配對對象
  const [users] = await db.query('SELECT partner_id FROM users WHERE id = ?', [userId]);
  const partnerId = users[0]?.partner_id;

  // 即時轉發給配對對象（不管節流）
  if (partnerId) {
    sendToUser(partnerId, {
      type: 'location',
      user_id: userId,
      lat,
      lng,
      accuracy,
      battery,
      timestamp: timestamp || Date.now(),
    });
  }

  // 節流存入 DB
  const now = Date.now();
  const lastSave = lastLocationSave.get(userId) || 0;

  if (now - lastSave >= LOCATION_SAVE_INTERVAL) {
    lastLocationSave.set(userId, now);
    try {
      await db.query(
        'INSERT INTO locations (user_id, lat, lng, accuracy, battery) VALUES (?, ?, ?, ?, ?)',
        [userId, lat, lng, accuracy || null, battery || null]
      );
    } catch (err) {
      console.error(`[WS] 儲存位置錯誤 (用戶 ${userId}):`, err.message);
    }
  }
}

/**
 * 處理聊天訊息
 * - 存入 DB
 * - 轉發給配對對象
 * - 對方離線時發推播
 */
async function handleChat(userId, data) {
  const { text } = data;

  if (!text || !text.trim()) return;

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
    sendToUser(userId, { type: 'error', error: '尚未配對，無法發送訊息' });
    return;
  }

  // 存入 DB
  const [result] = await db.query(
    'INSERT INTO messages (sender_id, receiver_id, text) VALUES (?, ?, ?)',
    [userId, user.partner_id, text.trim()]
  );

  const message = {
    type: 'chat',
    id: result.insertId,
    sender_id: userId,
    text: text.trim(),
    timestamp: new Date().toISOString(),
  };

  // 轉發給配對對象
  const delivered = sendToUser(user.partner_id, message);

  // 回傳確認給發送者
  sendToUser(userId, { ...message, type: 'chat_ack' });

  // 對方不在線，發推播
  if (!delivered) {
    const senderName = user.name || user.email;
    await sendPush(
      user.partner_device_token,
      senderName,
      text.trim(),
      { type: 'chat', sender_id: userId }
    );
  }
}

/**
 * 通知配對對象上線/離線狀態
 */
async function notifyPartnerStatus(userId, online) {
  try {
    const [users] = await db.query('SELECT partner_id FROM users WHERE id = ?', [userId]);
    const partnerId = users[0]?.partner_id;
    if (partnerId) {
      sendToUser(partnerId, {
        type: 'partner_status',
        user_id: userId,
        online,
        timestamp: Date.now(),
      });
    }
  } catch (err) {
    console.error('[WS] 通知狀態錯誤:', err.message);
  }
}

/**
 * 發送訊息給指定用戶
 * @param {number} userId - 目標用戶 ID
 * @param {object} data - 要發送的資料
 * @returns {boolean} 是否成功發送
 */
function sendToUser(userId, data) {
  const ws = clients.get(userId);
  if (ws && ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(data));
    return true;
  }
  return false;
}

/**
 * 檢查用戶是否在線
 */
function isUserOnline(userId) {
  const ws = clients.get(userId);
  return ws && ws.readyState === ws.OPEN;
}

module.exports = { initWebSocket, sendToUser, isUserOnline };
