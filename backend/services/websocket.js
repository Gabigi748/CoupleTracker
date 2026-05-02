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
    case 'sos':
      await handleSOS(userId, data);
      break;
    case 'screen_status':
      await handleScreenStatus(userId, data);
      break;
    case 'geofence_event':
      await handleGeofenceEvent(userId, data);
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
  const { lat, lng, accuracy, battery, timestamp, in_china } = data;

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
      in_china: !!in_china,
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
    'INSERT INTO messages (sender_id, receiver_id, text, type) VALUES (?, ?, ?, ?)',
    [userId, user.partner_id, text.trim(), 'text']
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
 * 處理 SOS 緊急求助（透過 WebSocket）
 * - 存入 DB
 * - 轉發給配對對象
 * - 對方離線時發推播
 */
async function handleSOS(userId, data) {
  const { lat, lng, timestamp } = data;

  try {
    // 取得用戶和配對對象資訊
    const [users] = await db.query(
      `SELECT u.id, u.name, u.email, u.partner_id, p.device_token AS partner_device_token
       FROM users u
       LEFT JOIN users p ON u.partner_id = p.id
       WHERE u.id = ?`,
      [userId]
    );

    const user = users[0];
    if (!user?.partner_id) {
      sendToUser(userId, { type: 'error', error: '尚未配對，無法發送 SOS' });
      return;
    }

    // 存入 SOS 記錄
    await db.query(
      'INSERT INTO sos_alerts (sender_id, lat, lng) VALUES (?, ?, ?)',
      [userId, lat || null, lng || null]
    );

    const senderName = user.name || user.email;

    // 轉發給配對對象
    const delivered = sendToUser(user.partner_id, {
      type: 'sos',
      sender_id: userId,
      sender_name: senderName,
      lat: lat || null,
      lng: lng || null,
      timestamp: timestamp || new Date().toISOString(),
    });

    // 回傳確認給發送者
    sendToUser(userId, { type: 'sos_ack', timestamp: Date.now() });

    // 對方不在線，發推播
    if (!delivered) {
      await sendPush(
        user.partner_device_token,
        '🆘 緊急求救！',
        `${senderName} 發送了 SOS 求救信號！`,
        { type: 'sos', sender_id: userId, lat: lat || null, lng: lng || null }
      );
    }
  } catch (err) {
    console.error(`[WS] SOS 處理錯誤 (用戶 ${userId}):`, err.message);
  }
}

// 螢幕狀態節流：記錄每個用戶最後一次轉發的螢幕狀態時間
const lastScreenForward = new Map();
const SCREEN_FORWARD_INTERVAL = 60 * 1000; // 60 秒

/**
 * 處理螢幕開關狀態
 * - 轉發給配對對象
 * - 一分鐘內同類型事件不重複轉發
 */
async function handleScreenStatus(userId, data) {
  const { screen_on, status, timestamp } = data;

  // 支援兩種格式：screen_on (bool) 或 status ("on"/"off")
  let isOn;
  if (status != null) {
    isOn = status === 'on';
  } else if (screen_on != null) {
    isOn = !!screen_on;
  } else {
    return;
  }

  // 節流：同一用戶同一狀態 60 秒內不重複轉發
  const key = `${userId}_${isOn ? 'on' : 'off'}`;
  const now = Date.now();
  const lastForward = lastScreenForward.get(key) || 0;

  if (now - lastForward < SCREEN_FORWARD_INTERVAL) {
    return; // 節流中，不轉發
  }
  lastScreenForward.set(key, now);

  try {
    // 取得配對對象
    const [users] = await db.query(
      `SELECT u.partner_id, u.name, u.email, p.device_token AS partner_device_token
       FROM users u
       LEFT JOIN users p ON u.partner_id = p.id
       WHERE u.id = ?`,
      [userId]
    );

    const partnerId = users[0]?.partner_id;
    if (!partnerId) return;

    const senderName = users[0].name || users[0].email;
    const actionText = isOn ? '開啟了螢幕' : '關閉了螢幕';
    const systemText = `${senderName} ${actionText}`;

    // 存入 messages 表（type='system'）
    const [result] = await db.query(
      'INSERT INTO messages (sender_id, receiver_id, text, type) VALUES (?, ?, ?, ?)',
      [userId, partnerId, systemText, 'system']
    );

    // 轉發給配對對象
    const delivered = sendToUser(partnerId, {
      type: 'screen_status',
      user_id: userId,
      sender_name: senderName,
      screen_on: isOn,
      timestamp: timestamp || new Date().toISOString(),
      // 同時附帶聊天訊息格式，讓 App 可以直接顯示在聊天框
      message_id: result.insertId,
      text: systemText,
    });

    // 對方不在線時，發推播通知
    if (!delivered) {
      const title = isOn ? '📱 螢幕開啟' : '📴 螢幕關閉';
      const body = systemText;

      if (users[0].partner_device_token) {
        await sendPush(users[0].partner_device_token, title, body, {
          type: 'screen_status',
          sender_id: userId,
          screen_on: isOn,
        });
      }
    }
  } catch (err) {
    console.error(`[WS] 螢幕狀態處理錯誤 (用戶 ${userId}):`, err.message);
  }
}

/**
 * 處理地理圍欄事件
 * - 存入 messages 表（type='system'）
 * - 轉發給配對對象
 * - 對方離線時發推播
 */
async function handleGeofenceEvent(userId, data) {
  const { zone_name, event } = data;

  if (!zone_name || !event) return;

  try {
    // 取得配對對象
    const [users] = await db.query(
      `SELECT u.partner_id, u.name, u.email, p.device_token AS partner_device_token
       FROM users u
       LEFT JOIN users p ON u.partner_id = p.id
       WHERE u.id = ?`,
      [userId]
    );

    const partnerId = users[0]?.partner_id;
    if (!partnerId) return;

    const senderName = users[0].name || users[0].email;
    const actionText = event === 'exit' ? '離開了' : '到達了';
    const systemText = `${senderName} ${actionText} ${zone_name}`;

    // 存入 messages 表（type='system'）
    const [result] = await db.query(
      'INSERT INTO messages (sender_id, receiver_id, text, type) VALUES (?, ?, ?, ?)',
      [userId, partnerId, systemText, 'system']
    );

    // 轉發給配對對象
    const delivered = sendToUser(partnerId, {
      type: 'geofence_event',
      user_id: userId,
      sender_name: senderName,
      zone_name,
      event,
      timestamp: new Date().toISOString(),
      // 附帶聊天訊息格式
      message_id: result.insertId,
      text: systemText,
    });

    // 對方不在線時，發推播通知
    if (!delivered) {
      const emoji = event === 'exit' ? '🚶' : '📍';
      const title = `${emoji} 圍欄通知`;

      if (users[0].partner_device_token) {
        await sendPush(users[0].partner_device_token, title, systemText, {
          type: 'geofence_event',
          sender_id: userId,
          zone_name,
          event,
        });
      }
    }
  } catch (err) {
    console.error(`[WS] 圍欄事件處理錯誤 (用戶 ${userId}):`, err.message);
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
