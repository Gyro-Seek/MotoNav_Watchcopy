#pragma once
#include <Arduino.h>
#include <Preferences.h>
#include "UiModern.h"
#include "LeanAngleMeter.h"

// 设置项全局状态
extern int qspiMHz;
extern int screenRot;
extern void setScreenDeg(int deg, bool save);
extern void setScreenDegFloat(float deg, bool save);

// 1. 亮度设置 (25%, 50%, 75%, 100%)
static const uint8_t brightnessLevels[] = {64, 128, 192, 255};
static const char* const brightnessLabels[] = {"25%", "50%", "75%", "100%"};
static int brightnessIdx = 2; // 默认 75% (192)

// 2. 地图主题样式（精简为与 App 严格一致的 4 款核心主题）
// 1: 罪恶都市(默认), 0: 原版, 5: 极简黑白, 11: 龙珠雷达
static const int supportedThemes[4] = {1, 0, 5, 11};
static const char* const supportedThemeLabels[4] = {"VICE CITY", "CLASSIC", "MINIMAL", "DRAGON"};
extern int themeIdx;

// 3. 屏幕重力旋转随动状态
bool settingsAutoRot = false;
static float autoRotAngleSmoothed = 0.0f;
static unsigned long lastAutoRotCheck = 0;

// 4. 待机休眠时间 (3分钟, 5分钟, 10分钟, 常亮)
static const uint32_t sleepTimeouts[] = {180, 300, 600, 0};
static const char* const sleepLabels[] = {"3 MIN", "5 MIN", "10 MIN", "NEVER"};
static int sleepIdx = 1; // 默认 5 分钟

inline void settingsInit() {
  Preferences pr;
  if (pr.begin("motonav", true)) {
    int b = pr.getInt("brightness", 192);
    for (int i = 0; i < 4; i++) {
      if (abs((int)brightnessLevels[i] - b) < 32) { brightnessIdx = i; break; }
    }
    int s = pr.getInt("autosleep", 300);
    for (int i = 0; i < 4; i++) {
      if (sleepTimeouts[i] == (uint32_t)s) { sleepIdx = i; break; }
    }
    pr.end();
  }
}

// 统一极简冷银白矢量图标 (简约高雅风格)
static void drawSettingsIcon(int id, int cx, int cy, uint16_t color = 0xDEFB) {
  switch (id) {
    case 0: // 太阳 (亮度)
      aaDisc(cx, cy, 4.5f, color);
      for (int a = 0; a < 360; a += 45) {
        float rad = a * (float)M_PI / 180.0f;
        gfx->drawLine((int)lroundf(cx + 7 * cosf(rad)), (int)lroundf(cy + 7 * sinf(rad)),
                      (int)lroundf(cx + 11 * cosf(rad)), (int)lroundf(cy + 11 * sinf(rad)), color);
      }
      break;

    case 1: // 地图图层 (地图风格)
      gfx->drawRoundRect(cx - 10, cy - 8, 20, 16, 2, color);
      gfx->drawLine(cx - 10, cy - 1, cx + 10, cy - 1, color);
      gfx->drawLine(cx - 3, cy - 8, cx - 3, cy + 8, color);
      aaDisc(cx + 4, cy + 3, 2.0f, color);
      break;

    case 2: // 旋转箭头 (屏幕角度/重力旋转)
      gfx->drawCircle(cx, cy, 9, color);
      gfx->drawCircle(cx, cy, 10, color);
      // 右上方开口与小箭头
      gfx->fillRect(cx + 3, cy - 11, 8, 8, C_BLACK);
      gfx->fillTriangle(cx + 2, cy - 11, cx + 10, cy - 11, cx + 6, cy - 5, color);
      break;

    case 3: // 月牙休眠 (待机时间)
      aaDisc(cx, cy, 8.0f, color);
      aaDisc(cx + 4.0f, cy - 3.0f, 7.0f, C_BLACK);
      break;
  }
}

// 获取当前选择的 4 款主题名称
static inline const char* getThemeDisplayLabel() {
  for (int i = 0; i < 4; i++) {
    if (supportedThemes[i] == themeIdx) return supportedThemeLabels[i];
  }
  return "VICE CITY";
}

// 绘制重力感应旋转校准界面（完整保留设置页背景与卡片全貌，实时呈现随动旋转效果，纯白基准十字线呈 90° 相交）
void drawRotationCalibPage() {
  onWaitScreen = false;
  frameIsMap = false;

  // 1. 绘制暗黑主题背景底图
  gfx->fillScreen(C_BLACK);
  drawThemedMapBackground();

  // 绘制 4 张设置卡片（让用户在转动时能实时看到设置界面的真实旋转效果）
  const int cardW = 164, cardH = 108, gapX = 14, gapY = 16;
  const int leftX  = CX - cardW - gapX / 2;
  const int rightX = CX + gapX / 2;
  const int topY   = 94, botY = topY + cardH + gapY;

  // 4 个卡片底座与边框
  drawTranslucentRoundRect(leftX,  topY, cardW, cardH, 16, 0x0000, 180);
  gfx->drawRoundRect(leftX,  topY, cardW, cardH, 16, 0x2965);
  drawTranslucentRoundRect(rightX, topY, cardW, cardH, 16, 0x0000, 180);
  gfx->drawRoundRect(rightX, topY, cardW, cardH, 16, 0x2965);
  drawTranslucentRoundRect(leftX,  botY, cardW, cardH, 16, 0x0000, 180);
  gfx->drawRoundRect(leftX,  botY, cardW, cardH, 16, 0x2965);
  drawTranslucentRoundRect(rightX, botY, cardW, cardH, 16, 0x0000, 180);
  gfx->drawRoundRect(rightX, botY, cardW, cardH, 16, 0x2965);

  // 绘制各卡片图标与文字
  drawSettingsIcon(0, leftX + cardW / 2, topY + 26, 0xDEFB);
  drawAaString(leftX + cardW / 2, topY + 54, "BRIGHTNESS", 1.3f, 0.8f, 9.0f, 0x8C71, true);

  drawSettingsIcon(1, rightX + cardW / 2, topY + 26, 0xDEFB);
  drawAaString(rightX + cardW / 2, topY + 54, "MAP STYLE", 1.3f, 0.8f, 9.0f, 0x8C71, true);

  drawSettingsIcon(2, leftX + cardW / 2, botY + 26, 0xDEFB);
  drawAaString(leftX + cardW / 2, botY + 54, "ROTATION", 1.3f, 0.8f, 9.0f, 0x8C71, true);

  drawSettingsIcon(3, rightX + cardW / 2, botY + 26, 0xDEFB);
  drawAaString(rightX + cardW / 2, botY + 54, "AUTO SLEEP", 1.3f, 0.8f, 9.0f, 0x8C71, true);

  // 2. 纯白基准十字线（白色水平线直径 + 垂直地面垂线半径，90 度垂直相交）
  // 横跨屏幕的水平基准线：长度 466px，贯穿正中心 Y = CX，纯白色，线宽 2px
  gfx->fillRect(0, CX - 1, LCD_WIDTH, 2, C_WHITE);

  // 垂直地面的线：长度 233px，从中心 (CX, CX) 垂直延伸至屏幕底部，纯白色，线宽 2px
  gfx->fillRect(CX - 1, CX, 2, CX, C_WHITE);

  // 中心相交点纯白精致圆点
  aaDisc((float)CX, (float)CX, 4.5f, C_WHITE);
  aaDisc((float)CX, (float)CX, 2.0f, C_BLACK);

  // 3. 旋转角度数字显示：在水平线中间上方（纯白色大号抗锯齿平滑字体，带高对比半透明黑色底衬）
  int curAngle = (int)lroundf(autoRotAngleSmoothed);
  curAngle = ((curAngle % 360) + 360) % 360;
  char degBuf[16];
  snprintf(degBuf, sizeof(degBuf), "%d*", curAngle);
  drawTranslucentRoundRect(CX - 50, CX - 54, 100, 38, 12, 0x0000, 210);
  gfx->drawRoundRect(CX - 50, CX - 54, 100, 38, 12, 0x4A69);
  drawAaString((float)CX, (float)(CX - 35), degBuf, 3.2f, 1.8f, 22.0f, C_WHITE, true);

  // 4. 顶部与底部极简提示
  // 顶部：AUTO ROTATE
  drawTranslucentRoundRect(CX - 72, 44, 144, 28, 14, 0x0000, 200);
  gfx->drawRoundRect(CX - 72, 44, 144, 28, 14, 0x39E7);
  drawAaString((float)CX, 58.0f, "AUTO ROTATE", 1.4f, 0.85f, 9.5f, C_WHITE, true);

  // 底部：TAP ANYWHERE TO LOCK (点击任意位置锁定)
  drawTranslucentRoundRect(CX - 110, 396, 220, 30, 15, 0x0000, 200);
  gfx->drawRoundRect(CX - 110, 396, 220, 30, 15, 0x760D);
  drawAaString((float)CX, 411.0f, "TAP ANYWHERE TO LOCK", 1.3f, 0.8f, 9.0f, 0x760D, true);

  needFlush = true;
}

// 重力感应屏幕旋转动态刷新（浮点级无阶梯顿挫，40 FPS 流体般自然旋转）
inline void settingsUpdateAutoRot() {
  if (!settingsAutoRot || page != 1 || !LeanAngleMeter::available) return;
  unsigned long now = millis();
  if (now - lastAutoRotCheck < 25) return; // 40 FPS 超高频响应
  lastAutoRotCheck = now;

  LeanAngleMeter::imu.getSensorData();
  // 硬件旋转映射：屏幕向右 = +accelY, 屏幕向上 = -accelX
  float ax = LeanAngleMeter::imu.data.accelY;
  float ay = -LeanAngleMeter::imu.data.accelX;
  float aMag = sqrtf(ax * ax + ay * ay);

  // 只要屏幕有适当倾角（非水平平放于桌面上），实时随重力转动
  if (aMag >= 0.15f) {
    float rad = atan2f(ax, ay);
    float deg = rad * (180.0f / (float)M_PI);
    if (deg < 0) deg += 360.0f;

    // 环形平滑插值滤波，消除传感器抖动
    float diff = deg - autoRotAngleSmoothed;
    while (diff > 180.0f) diff -= 360.0f;
    while (diff < -180.0f) diff += 360.0f;

    // 动态平滑跟手：大角度快速跟随，小角度柔和滤除抖动
    float alpha = fabsf(diff) > 25.0f ? 0.40f : 0.22f;
    autoRotAngleSmoothed += diff * alpha;
    while (autoRotAngleSmoothed >= 360.0f) autoRotAngleSmoothed -= 360.0f;
    while (autoRotAngleSmoothed < 0.0f) autoRotAngleSmoothed += 360.0f;

    // 浮点连续旋转推屏，彻底消除整数阶梯卡顿
    setScreenDegFloat(autoRotAngleSmoothed, false);
    drawRotationCalibPage();
  }
}

// 绘制设置页面 (466x466 AMOLED 圆屏极简现代风格)
void drawSettingsPage() {
  onWaitScreen = false;
  frameIsMap = false;

  // 若处于随动旋转模式，直接绘制流体旋转校准视图
  if (settingsAutoRot) {
    drawRotationCalibPage();
    return;
  }

  // 1. 绘制统一沉稳的暗黑磨砂背景
  gfx->fillScreen(C_BLACK);
  drawThemedMapBackground();

  // 2. 顶部极简毛玻璃药丸标题
  const int titleW = 150;
  const int titleH = 32;
  const int titleX = CX - titleW / 2;
  const int titleY = 36;
  drawTranslucentRoundRect(titleX, titleY, titleW, titleH, 16, 0x0000, 205);
  gfx->drawRoundRect(titleX, titleY, titleW, titleH, 16, 0x2965);
  drawAaString(CX, titleY + 16, "SETTINGS", 1.8f, 1.0f, 12.0f, C_WHITE, true);

  // 3. 4 个半透明毛玻璃设置卡片 (极简克制高级配色)
  const int cardW = 164;
  const int cardH = 108;
  const int gapX = 14;
  const int gapY = 16;
  const int leftX  = CX - cardW - gapX / 2; // 62
  const int rightX = CX + gapX / 2;          // 240
  const int topY   = 94;
  const int botY   = topY + cardH + gapY;   // 218

  // 格式化当前锁定的整数角度
  char rotBuf[16];
  snprintf(rotBuf, sizeof(rotBuf), "%d*", screenDeg);

  struct CardConfig {
    int x, y;
    int iconId;
    const char *title;
    const char *val;
  } cards[4] = {
    {leftX,  topY, 0, "BRIGHTNESS", brightnessLabels[brightnessIdx]},
    {rightX, topY, 1, "MAP STYLE",  getThemeDisplayLabel()},
    {leftX,  botY, 2, "ROTATION",   rotBuf},
    {rightX, botY, 3, "AUTO SLEEP", sleepLabels[sleepIdx]}
  };

  for (int i = 0; i < 4; i++) {
    int cx = cards[i].x;
    int cy = cards[i].y;

    // 极简深黑毛玻璃底座
    drawTranslucentRoundRect(cx, cy, cardW, cardH, 16, 0x0000, 190);
    gfx->drawRoundRect(cx, cy, cardW, cardH, 16, 0x2965);

    // 图标 (居中偏上，冷银白)
    drawSettingsIcon(cards[i].iconId, cx + cardW / 2, cy + 26, 0xDEFB);

    // 标题文字 (克制冷灰色，极简抗锯齿字符)
    drawAaString(cx + cardW / 2, cy + 54, cards[i].title, 1.3f, 0.8f, 9.0f, 0x8C71, true);

    // 当前数值底座
    const int valPillW = cardW - 32;
    const int valPillH = 26;
    const int valPillX = cx + 16;
    const int valPillY = cy + 72;
    drawTranslucentRoundRect(valPillX, valPillY, valPillW, valPillH, 13, 0x0000, 160);
    gfx->drawRoundRect(valPillX, valPillY, valPillW, valPillH, 13, 0x31A6);
    drawAaString(cx + cardW / 2, valPillY + 13, cards[i].val, 1.5f, 0.9f, 10.0f, C_WHITE, true);
  }

  // 4. 底部极简操作提示
  drawAaString(CX, 386, "TAP CARD TO CONFIGURE", 1.2f, 0.75f, 8.5f, 0x632C, true);

  // 5. 底部页面指示点
  drawPageDots();
  needFlush = true;
}

// 设置页面点击处理 (接收已按屏幕旋转换算为画布坐标系的 x, y)
void settingsPageTap(int x, int y) {
  if (page != 1 || callOn || pairOn || sliding) return;

  // 在调整角度模式下：用户按屏幕任意位置都立即锁定角度，自然贴合到整数角度
  if (settingsAutoRot) {
    settingsAutoRot = false;
    int finalDeg = (int)lroundf(autoRotAngleSmoothed);
    finalDeg = ((finalDeg % 360) + 360) % 360;
    setScreenDeg(finalDeg, true);
    CompanionMode::startVibration(70, 30);
    drawSettingsPage();
    return;
  }

  const int cardW = 164;
  const int cardH = 108;
  const int gapX = 14;
  const int gapY = 16;
  const int leftX  = CX - cardW - gapX / 2;
  const int rightX = CX + gapX / 2;
  const int topY   = 94;
  const int botY   = topY + cardH + gapY;

  int clickedCard = -1;
  if (x >= leftX && x <= leftX + cardW) {
    if (y >= topY && y <= topY + cardH) clickedCard = 0;       // 亮度
    else if (y >= botY && y <= botY + cardH) clickedCard = 2;  // 旋转
  } else if (x >= rightX && x <= rightX + cardW) {
    if (y >= topY && y <= topY + cardH) clickedCard = 1;       // 地图风格
    else if (y >= botY && y <= botY + cardH) clickedCard = 3;  // 休眠
  }

  if (clickedCard < 0) return;

  // 震动触感反馈
  CompanionMode::startVibration(50, 20);

  switch (clickedCard) {
    case 0: { // 亮度调节 (25% -> 50% -> 75% -> 100%)
      brightnessIdx = (brightnessIdx + 1) % 4;
      uint8_t b = brightnessLevels[brightnessIdx];
      panel->setBrightness(b);
      Preferences pr;
      if (pr.begin("motonav", false)) {
        pr.putInt("brightness", b);
        pr.end();
      }
      break;
    }
    case 1: { // 地图风格切换（在 App 的 4 款核心主题中循环：罪恶都市 -> 原版 -> 极简黑白 -> 龙珠雷达）
      int curPos = 0;
      for (int i = 0; i < 4; i++) {
        if (supportedThemes[i] == themeIdx) { curPos = i; break; }
      }
      curPos = (curPos + 1) % 4;
      themeIdx = supportedThemes[curPos];

      Preferences pr;
      if (pr.begin("motonav", false)) {
        pr.putInt("maptheme", themeIdx);
        pr.end();
      }
      // 通知手机端同步地图风格
      if (bleConnected) {
        pendingEvt = "T,SET_THEME," + String(themeIdx);
      }
      break;
    }
    case 2: { // 点击进入重力旋转随动校准模式
      settingsAutoRot = true;
      autoRotAngleSmoothed = (float)screenDeg;
      lastAutoRotCheck = 0;
      drawRotationCalibPage();
      return;
    }
    case 3: { // 待机休眠
      sleepIdx = (sleepIdx + 1) % 4;
      uint32_t s = sleepTimeouts[sleepIdx];
      Preferences pr;
      if (pr.begin("motonav", false)) {
        pr.putInt("autosleep", s);
        pr.end();
      }
      break;
    }
  }

  drawSettingsPage();
}
