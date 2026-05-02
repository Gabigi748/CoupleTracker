/**
 * APNs 推播工具
 * 使用 @parse/node-apn 發送 iOS 推播通知
 */
const apn = require('@parse/node-apn');
const path = require('path');

let apnProvider = null;

/**
 * 初始化 APNs Provider
 * 只在有設定 key 的情況下才初始化
 */
function initAPNs() {
  if (!process.env.APNS_KEY_PATH || !process.env.APNS_KEY_ID || !process.env.APNS_TEAM_ID) {
    console.log('[APNs] 未設定 APNs 金鑰，推播功能停用');
    return;
  }

  try {
    apnProvider = new apn.Provider({
      token: {
        key: path.resolve(process.env.APNS_KEY_PATH),
        keyId: process.env.APNS_KEY_ID,
        teamId: process.env.APNS_TEAM_ID,
      },
      production: process.env.APNS_PRODUCTION === 'true',
    });
    console.log('[APNs] 推播服務已初始化');
  } catch (err) {
    console.error('[APNs] 初始化失敗:', err.message);
  }
}

/**
 * 發送推播通知
 * @param {string} deviceToken - 裝置 Token
 * @param {string} title - 通知標題
 * @param {string} body - 通知內容
 * @param {object} payload - 額外資料
 */
async function sendPush(deviceToken, title, body, payload = {}) {
  if (!apnProvider) {
    console.log('[APNs] Provider 未初始化，跳過推播');
    return null;
  }

  if (!deviceToken) {
    console.log('[APNs] 無裝置 Token，跳過推播');
    return null;
  }

  const notification = new apn.Notification();
  notification.alert = { title, body };
  notification.sound = 'default';
  notification.badge = 1;
  notification.topic = process.env.APNS_BUNDLE_ID || 'com.coupletracker.app';
  notification.payload = payload;

  try {
    const result = await apnProvider.send(notification, deviceToken);
    if (result.failed.length > 0) {
      console.error('[APNs] 推播失敗:', result.failed[0].response);
    }
    return result;
  } catch (err) {
    console.error('[APNs] 發送錯誤:', err.message);
    return null;
  }
}

/**
 * 關閉 APNs 連線
 */
function shutdownAPNs() {
  if (apnProvider) {
    apnProvider.shutdown();
    console.log('[APNs] 已關閉');
  }
}

module.exports = { initAPNs, sendPush, shutdownAPNs };
