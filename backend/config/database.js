/**
 * MySQL 資料庫連線設定
 * 使用連線池管理資料庫連線
 */
const mysql = require('mysql2/promise');

const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'couple_tracker',
  waitForConnections: true,
  connectionLimit: 20,       // 最大連線數
  queueLimit: 0,             // 無限排隊
  enableKeepAlive: true,     // 保持連線活躍
  keepAliveInitialDelay: 10000,
  charset: 'utf8mb4',
});

module.exports = pool;
