#pragma once
#include <Arduino.h>
#include "LeanAngleMeter.h"
#include "UiModern.h"

extern bool dragging;

// 现代车规级柔和奢华科技配色定义
#define LEAN_COLOR_SAFE   0x4ECB  // 柔和薄荷青绿 (优雅清爽不刺眼)
#define LEAN_COLOR_WARN   0xFB65  // 落日暖金柔橙
#define LEAN_COLOR_ALERT  0xFA68  // 柔和珊瑚红
#define LEAN_RING_05G     0x1908  // 0.5G 柔和深暗环
#define LEAN_RING_10G     0x29CE  // 1.0G 标准临界环
#define LEAN_RING_15G     0x3A32  // 1.5G 极限边界环
#define LEAN_CROSSHAIR    0x2106  // 十字准星柔和暗青灰

void drawLeanMeter() {
  onWaitScreen = false;
  frameIsMap = false;
  gfx->fillScreen(C_BLACK);

  // 1. 顶部状态栏：优雅小圆点
  aaDisc(CX - 150, 28, 4.0f, bleConnected ? LEAN_COLOR_SAFE : 0x632C);

  const int CY = CX; // 466x466 圆屏中心 (233, 233)
  const float CX_DIAL = (float)CX;
  const float CY_DIAL = (float)CY;

  // ==========================================
  // 2. 外层环形：倾角扇形与加粗加大刻度盘 (R: 154 ~ 206)
  // ==========================================
  const float R_OUT = 206.0f;
  const float R_IN  = 154.0f;

  float curLean = LeanAngleMeter::leanAngle;
  float absCurLean = fabsf(curLean);

  // 扇形实心色彩填充 (微四边形网格光栅化，柔和优雅配色)
  if (absCurLean >= 1.0f) {
    float a1 = 270.0f;
    float a2 = 270.0f + curLean;
    if (a1 > a2) { float tmp = a1; a1 = a2; a2 = tmp; }

    uint16_t sectorColor;
    if (absCurLean <= 35.0f) sectorColor = LEAN_COLOR_SAFE;
    else if (absCurLean <= 50.0f) sectorColor = LEAN_COLOR_WARN;
    else sectorColor = LEAN_COLOR_ALERT;

    const float STEP = 0.5f;
    for (float a = a1; a < a2; a += STEP) {
      float nextA = a + STEP;
      if (nextA > a2) nextA = a2;

      float rad1 = a * (float)M_PI / 180.0f;
      float rad2 = nextA * (float)M_PI / 180.0f;

      float cos1 = cosf(rad1), sin1 = sinf(rad1);
      float cos2 = cosf(rad2), sin2 = sinf(rad2);

      int x_in1  = (int)lroundf(CX_DIAL + R_IN * cos1);
      int y_in1  = (int)lroundf(CY_DIAL + R_IN * sin1);
      int x_out1 = (int)lroundf(CX_DIAL + R_OUT * cos1);
      int y_out1 = (int)lroundf(CY_DIAL + R_OUT * sin1);

      int x_in2  = (int)lroundf(CX_DIAL + R_IN * cos2);
      int y_in2  = (int)lroundf(CY_DIAL + R_IN * sin2);
      int x_out2 = (int)lroundf(CX_DIAL + R_OUT * cos2);
      int y_out2 = (int)lroundf(CY_DIAL + R_OUT * sin2);

      gfx->fillTriangle(x_in1, y_in1, x_out1, y_out1, x_out2, y_out2, sectorColor);
      gfx->fillTriangle(x_in1, y_in1, x_out2, y_out2, x_in2, y_in2, sectorColor);
    }

    // 扇面当前倾角边缘指针 (加粗纯白线)
    float curRad = (270.0f + curLean) * (float)M_PI / 180.0f;
    float cCos = cosf(curRad), cSin = sinf(curRad);
    int px1 = (int)lroundf(CX_DIAL + (R_IN - 4) * cCos), py1 = (int)lroundf(CY_DIAL + (R_IN - 4) * cSin);
    int px2 = (int)lroundf(CX_DIAL + (R_OUT + 4) * cCos), py2 = (int)lroundf(CY_DIAL + (R_OUT + 4) * cSin);
    gfx->drawLine(px1, py1, px2, py2, C_WHITE);
    gfx->drawLine(px1 + 1, py1, px2 + 1, py2, C_WHITE);
    gfx->drawLine(px1 - 1, py1, px2 - 1, py2, C_WHITE);
  }

  // 覆盖放射状刻度盘 (-60° 到 +60°)
  for (int a = -60; a <= 60; a += 2) {
    float rad = (270.0f + a) * (float)M_PI / 180.0f;
    float cosA = cosf(rad), sinA = sinf(rad);
    int absA = abs(a);

    float len = (absA % 30 == 0) ? 26.0f : ((absA % 10 == 0) ? 16.0f : ((absA % 5 == 0) ? 8.0f : 0.0f));
    if (len == 0.0f) continue;

    uint16_t c;
    if (absA == 0) {
      c = C_WHITE;
    } else if (absA <= 35) {
      c = (absA % 30 == 0) ? LEAN_COLOR_SAFE : 0x2446;
    } else if (absA <= 50) {
      c = (absA % 10 == 0) ? LEAN_COLOR_WARN : 0x6320;
    } else {
      c = (absA % 10 == 0) ? LEAN_COLOR_ALERT : 0x59A0;
    }

    int x1 = (int)lroundf(CX_DIAL + (R_OUT - len) * cosA);
    int y1 = (int)lroundf(CY_DIAL + (R_OUT - len) * sinA);
    int x2 = (int)lroundf(CX_DIAL + R_OUT * cosA);
    int y2 = (int)lroundf(CY_DIAL + R_OUT * sinA);
    gfx->drawLine(x1, y1, x2, y2, c);

    if (absA % 30 == 0) {
      gfx->drawLine(x1 + 1, y1, x2 + 1, y2, c);
      gfx->drawLine(x1 - 1, y1, x2 - 1, y2, c);
    } else if (absA % 10 == 0) {
      gfx->drawLine(x1 + 1, y1, x2 + 1, y2, c);
    }
  }

  // 0° 正上方中线强化
  gfx->drawLine((int)CX_DIAL - 1, (int)(CY_DIAL - R_OUT), (int)CX_DIAL - 1, (int)(CY_DIAL - R_OUT + 28), C_WHITE);
  gfx->drawLine((int)CX_DIAL,     (int)(CY_DIAL - R_OUT), (int)CX_DIAL,     (int)(CY_DIAL - R_OUT + 28), C_WHITE);
  gfx->drawLine((int)CX_DIAL + 1, (int)(CY_DIAL - R_OUT), (int)CX_DIAL + 1, (int)(CY_DIAL - R_OUT + 28), C_WHITE);

  // 刻度值数字 (全部改用抗锯齿平滑字符，彻底去像素化)
  drawAaString((float)CX_DIAL, (float)(CY_DIAL - R_OUT - 12), "0", 1.8f, 1.0f, 10.0f, C_WHITE, true);

  float rad30 = 300.0f * (float)M_PI / 180.0f;
  float radM30 = 240.0f * (float)M_PI / 180.0f;
  drawAaString(CX_DIAL + (R_OUT + 15) * cosf(rad30), CY_DIAL + (R_OUT + 15) * sinf(rad30), "30", 1.6f, 0.95f, 10.0f, LEAN_COLOR_SAFE, true);
  drawAaString(CX_DIAL + (R_OUT + 16) * cosf(radM30), CY_DIAL + (R_OUT + 16) * sinf(radM30), "-30", 1.6f, 0.95f, 10.0f, LEAN_COLOR_SAFE, true);

  float rad60 = 330.0f * (float)M_PI / 180.0f;
  float radM60 = 210.0f * (float)M_PI / 180.0f;
  drawAaString(CX_DIAL + (R_OUT + 15) * cosf(rad60), CY_DIAL + (R_OUT + 15) * sinf(rad60), "60", 1.6f, 0.95f, 10.0f, LEAN_COLOR_ALERT, true);
  drawAaString(CX_DIAL + (R_OUT + 16) * cosf(radM60), CY_DIAL + (R_OUT + 16) * sinf(radM60), "-60", 1.6f, 0.95f, 10.0f, LEAN_COLOR_ALERT, true);

  // ==========================================
  // 3. 准备实时倾角动态数值与颜色
  // ==========================================
  char leanStr[16];
  if (absCurLean < 0.5f) {
    snprintf(leanStr, sizeof(leanStr), "0*");
  } else if (curLean < 0) {
    snprintf(leanStr, sizeof(leanStr), "-%d*", (int)lroundf(absCurLean));
  } else {
    snprintf(leanStr, sizeof(leanStr), "+%d*", (int)lroundf(absCurLean));
  }

  uint16_t leanColor = (absCurLean < 0.5f) ? C_WHITE :
                       ((absCurLean <= 35.0f) ? LEAN_COLOR_SAFE :
                       ((absCurLean <= 50.0f) ? LEAN_COLOR_WARN : LEAN_COLOR_ALERT));

  // ==========================================
  // 4. G 值表圆圈与多层同心标尺 (0.5G / 1.0G / 1.5G)
  // ==========================================
  const int GR = 104;
  const float MAX_G = 1.5f;

  gfx->drawCircle(CX, CY, 35, LEAN_RING_05G);
  gfx->drawCircle(CX, CY, 70, LEAN_RING_10G);
  gfx->drawCircle(CX, CY, GR, LEAN_RING_15G);

  // 十字准星 (中心留空)
  gfx->drawLine(CX - GR, CY, CX - 8, CY, LEAN_CROSSHAIR);
  gfx->drawLine(CX + 8, CY, CX + GR, CY, LEAN_CROSSHAIR);
  gfx->drawLine(CX, CY - GR, CX, CY - 8, LEAN_CROSSHAIR);
  gfx->drawLine(CX, CY + 8, CX, CY + GR, LEAN_CROSSHAIR);

  // 十字端点平滑抗锯齿微注
  drawAaString(CX, CY - GR + 12, "^ ACC", 1.1f, 0.7f, 8.0f, 0x7BEF, true);
  drawAaString(CX, CY + GR - 12, "v BRK", 1.1f, 0.7f, 8.0f, 0x7BEF, true);

  // 动态大光圈小球
  const float MOVE_R = (float)(GR - 13);
  float normLong = LeanAngleMeter::gLongitudinal / MAX_G;
  float normLat  = LeanAngleMeter::gLateral / MAX_G;
  float dx = normLat * MOVE_R;
  float dy = -normLong * MOVE_R;

  float dist = sqrtf(dx * dx + dy * dy);
  if (dist > MOVE_R) {
    dx = (dx / dist) * MOVE_R;
    dy = (dy / dist) * MOVE_R;
  }

  int bx = (int)lroundf(CX_DIAL + dx);
  int by = (int)lroundf(CY_DIAL + dy);

  // 柔和微光小球 (中心高亮，外围薄荷青圆弧)
  aaDisc((float)bx, (float)by, 8.5f, 0x1A29);
  gfx->drawCircle(bx, by, 8, LEAN_COLOR_SAFE);
  aaDisc((float)bx, (float)by, 3.5f, C_WHITE);

  // 实时综合 G 值读数 (平滑滤波，位于圆心下方)
  static float dispG = 0.0f;
  float targetG = LeanAngleMeter::gTotal;
  if (fabsf(targetG - dispG) > 0.015f) {
    dispG += 0.10f * (targetG - dispG);
  }
  if (dispG < 0.02f) dispG = 0.0f;

  char gNumBuf[16];
  snprintf(gNumBuf, sizeof(gNumBuf), "%.2f G", dispG);
  drawAaString(CX, CY + 52, gNumBuf, 2.2f, 1.25f, 14.0f, LEAN_COLOR_SAFE, true);

  // ==========================================
  // 5. 屏幕两侧半透明毛玻璃胶囊：MAX L 与 MAX R
  // ==========================================
  const int SIDE_W = 86;
  const int SIDE_H = 42;
  const int SIDE_OFFSET = 169;
  const int SIDE_L_X = CX - SIDE_OFFSET - SIDE_W / 2;
  const int SIDE_R_X = CX + SIDE_OFFSET - SIDE_W / 2;
  const int SIDE_Y   = CY - SIDE_H / 2;

  // 左侧胶囊: MAX L (毛玻璃半透明)
  drawTranslucentRoundRect(SIDE_L_X, SIDE_Y, SIDE_W, SIDE_H, 14, 0x0000, 185);
  gfx->drawRoundRect(SIDE_L_X, SIDE_Y, SIDE_W, SIDE_H, 14, 0x31A6);

  char maxLStr[16];
  snprintf(maxLStr, sizeof(maxLStr), "-%d*", (int)lroundf(LeanAngleMeter::maxLeftLean));
  drawAaString(SIDE_L_X + SIDE_W / 2, SIDE_Y + 11, "MAX L", 1.2f, 0.75f, 8.5f, 0x7BEF, true);
  drawAaString(SIDE_L_X + SIDE_W / 2, SIDE_Y + 28, maxLStr, 1.8f, 1.05f, 11.5f, C_WHITE, true);

  // 右侧胶囊: MAX R (毛玻璃半透明)
  drawTranslucentRoundRect(SIDE_R_X, SIDE_Y, SIDE_W, SIDE_H, 14, 0x0000, 185);
  gfx->drawRoundRect(SIDE_R_X, SIDE_Y, SIDE_W, SIDE_H, 14, 0x31A6);

  char maxRStr[16];
  snprintf(maxRStr, sizeof(maxRStr), "+%d*", (int)lroundf(LeanAngleMeter::maxRightLean));
  drawAaString(SIDE_R_X + SIDE_W / 2, SIDE_Y + 11, "MAX R", 1.2f, 0.75f, 8.5f, 0x7BEF, true);
  drawAaString(SIDE_R_X + SIDE_W / 2, SIDE_Y + 28, maxRStr, 1.8f, 1.05f, 11.5f, C_WHITE, true);

  // ==========================================
  // 6. 底部第 1 行: MAX G 半透明胶囊卡片 (Y = 346)
  // ==========================================
  const int CAP1_Y = 346;
  const int CAP1_W = 186;
  const int CAP1_H = 30;
  const int CAP1_X = CX - CAP1_W / 2;

  bool justCalib = millis() < LeanAngleMeter::calibSuccessUntil;
  if (justCalib) {
    drawTranslucentRoundRect(CAP1_X, CAP1_Y, CAP1_W, CAP1_H, 15, LEAN_COLOR_SAFE, 220);
    gfx->drawRoundRect(CAP1_X, CAP1_Y, CAP1_W, CAP1_H, 15, LEAN_COLOR_SAFE);
    drawAaString(CX, CAP1_Y + 15, "CALIBRATED OK", 1.6f, 0.95f, 11.0f, C_BLACK, true);
  } else {
    drawTranslucentRoundRect(CAP1_X, CAP1_Y, CAP1_W, CAP1_H, 15, 0x0000, 185);
    gfx->drawRoundRect(CAP1_X, CAP1_Y, CAP1_W, CAP1_H, 15, 0x31A6);

    char maxGBuf[16];
    snprintf(maxGBuf, sizeof(maxGBuf), "%.2f G", LeanAngleMeter::maxG);
    drawAaString(CX - 42, CAP1_Y + 15, "MAX G", 1.3f, 0.8f, 9.0f, 0x7BEF, true);
    drawAaString(CX + 34, CAP1_Y + 15, maxGBuf, 1.7f, 1.0f, 11.0f, LEAN_COLOR_SAFE, true);
  }

  // ==========================================
  // 7. 底部第 2 行: 实时倾角数字毛玻璃胶囊卡片 (Y = 382)
  // ==========================================
  const int CAP2_Y = 382;
  const int CAP2_W = 186;
  const int CAP2_H = 30;
  const int CAP2_X = CX - CAP2_W / 2;

  drawTranslucentRoundRect(CAP2_X, CAP2_Y, CAP2_W, CAP2_H, 15, 0x0000, 185);
  gfx->drawRoundRect(CAP2_X, CAP2_Y, CAP2_W, CAP2_H, 15, 0x31A6);

  drawAaString(CX - 42, CAP2_Y + 15, "LEAN", 1.3f, 0.8f, 9.0f, 0x7BEF, true);
  drawAaString(CX + 34, CAP2_Y + 15, leanStr, 1.9f, 1.15f, 12.0f, leanColor, true);

  // 零位校准提示 (底部平滑微字)
  drawAaString(CX, 418, "HOLD TO CALIBRATE", 1.2f, 0.75f, 8.5f, 0x4A69, true);

  // 8. 底部页面指示点
  drawPageDots();
  needFlush = true;
}

void leanMeterTap(int x, int y) {
  if (dragging || page != 3 || callOn || pairOn) return;
  float dx = x - CX, dy = y - CX;
  touchVectorToCanvas(dx, dy);
  x = (int)lroundf(CX + dx); y = (int)lroundf(CX + dy);

  static unsigned long lastTapAt = 0;
  unsigned long now = millis();
  bool isDouble = (now - lastTapAt < 400);
  lastTapAt = now;

  // 双击屏幕重置极值统计
  if (isDouble) {
    CompanionMode::startVibration(40, 20);
    LeanAngleMeter::resetStats();
    leanDirty = true;
  }
}
