/**
 * CoupleTracker 後端入口
 * 情侶位置共享 App 的 API 伺服器
 */
require('dotenv').config();

const express = require('express');
const http = require('http');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

// 路由
const authRoutes = require('./routes/auth');
const pairRoutes = require('./routes/pair');
const locationRoutes = require('./routes/locations');
const geofenceRoutes = require('./routes/geofences');
const chatRoutes = require('./routes/chat');
const sosRoutes = require('./routes/sos');

// 服務
const { initWebSocket } = require('./services/websocket');
const { initAPNs, shutdownAPNs } = require('./utils/apns');

const app = express();
const server = http.createServer(app);

// ===== 中介層 =====

// 安全標頭
app.use(helmet());

// CORS 設定
app.use(cors({
  origin: '*',           // 正式環境請限制來源
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// 解析 JSON body
app.use(express.json({ limit: '1mb' }));

// API 速率限制（每個 IP 每 15 分鐘最多 200 次請求）
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: '請求過於頻繁，請稍後再試' },
});
app.use('/api/', apiLimiter);

// ===== 路由 =====

app.use('/api/auth', authRoutes);
app.use('/api/pair', pairRoutes);
app.use('/api/locations', locationRoutes);
app.use('/api/geofences', geofenceRoutes);
app.use('/api/chat', chatRoutes);
app.use('/api/sos', sosRoutes);

// 健康檢查
app.get('/health', (req, res) => {
  res.json({ success: true, data: { status: 'ok', uptime: process.uptime() } });
});

// 404 處理
app.use((req, res) => {
  res.status(404).json({ success: false, error: '找不到此路由' });
});

// 全域錯誤處理
app.use((err, req, res, _next) => {
  console.error('[Server] 未捕獲錯誤:', err);
  res.status(500).json({ success: false, error: '伺服器內部錯誤' });
});

// ===== 啟動伺服器 =====

const PORT = process.env.PORT || 3100;

// 初始化 APNs 推播服務
initAPNs();

// 初始化 WebSocket
initWebSocket(server);

server.listen(PORT, () => {
  console.log(`[Server] CoupleTracker 後端已啟動，Port: ${PORT}`);
  console.log(`[Server] API: http://localhost:${PORT}/api`);
  console.log(`[Server] WebSocket: ws://localhost:${PORT}/ws`);
});

// ===== 優雅關閉 =====

function gracefulShutdown(signal) {
  console.log(`\n[Server] 收到 ${signal}，正在關閉...`);
  shutdownAPNs();
  server.close(() => {
    console.log('[Server] 已關閉');
    process.exit(0);
  });
  // 5 秒後強制關閉
  setTimeout(() => {
    console.error('[Server] 強制關閉');
    process.exit(1);
  }, 5000);
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
