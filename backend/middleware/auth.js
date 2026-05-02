/**
 * JWT 認證中介層
 * 驗證請求中的 Bearer Token
 */
const jwt = require('jsonwebtoken');

function authMiddleware(req, res, next) {
  const header = req.headers.authorization;

  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, error: '未提供認證 Token' });
  }

  const token = header.slice(7);

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.userId = decoded.userId;
    next();
  } catch (err) {
    return res.status(401).json({ success: false, error: 'Token 無效或已過期' });
  }
}

module.exports = authMiddleware;
