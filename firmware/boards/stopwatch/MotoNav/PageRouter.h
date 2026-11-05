#pragma once
#include <Arduino.h>

// 拖动状态
bool dragging = false;
int dragTarget = 0, dragSign = 1;
bool dragHoriz = true;
float dragP = 0, dragV = 0;                 // 新页面已经进来多少像素；速度（像素/毫秒）
unsigned long dragT = 0;

uint16_t *shownFrame() {
  if (fbBuf[1] && flushSrc) return flushSrc;
  return gfx->getFramebuffer();
}

static inline uint16_t dim565(uint16_t c, uint32_t k) {   // k: 0~32，32 = 原样
  uint32_t r = (c >> 11) & 31, g = (c >> 5) & 63, b = c & 31;
  return (uint16_t)(((r * k >> 5) << 11) | ((g * k >> 5) << 5) | (b * k >> 5));
}

// 画一个页面到画布（不改当前页）
void renderPage(int p) {
  int keep = page;
  bool ks = sliding;
  page = p; sliding = false;
  if (p == 2) drawMusic();
  else if (p == 1) drawSettingsPage();
  else if (p == 3) drawLeanMeter();
  else if (p == 4) CompanionMode::drawInitialFrame();
  else if (inNav) drawNavFrame();
  else drawWaiting(bleConnected ? WAIT_READY : WAIT_NOLINK);
  page = keep; sliding = ks;
}

// 准备滑动：存下屏幕上的旧画面，在画布上画好目标页面存起来
bool slidePrepare(int target) {
  const size_t BYTES = (size_t)LCD_WIDTH * LCD_HEIGHT * 2;
  if (!slideOld) slideOld = (uint16_t *)heap_caps_malloc(BYTES, MALLOC_CAP_SPIRAM);
  if (!slideNew) slideNew = (uint16_t *)heap_caps_malloc(BYTES, MALLOC_CAP_SPIRAM);
  if (!slideOld || !slideNew) return false;
  if (!chordReady) {
    for (int y = 0; y < LCD_HEIGHT; y++) {
      float d = y + 0.5f - LCD_HEIGHT / 2.0f, r = LCD_WIDTH / 2.0f + 1;
      chordHalf[y] = d * d < r * r ? (int16_t)ceilf(sqrtf(r * r - d * d)) : 0;
    }
    chordReady = true;
  }
  if (fbBuf[1]) { flushWait(); xSemaphoreGive(flushDone); }   // 等正在推的那帧推完，旧画面才完整
  memcpy(slideOld, shownFrame(), BYTES);
  renderPage(target);
  memcpy(slideNew, gfx->getFramebuffer(), BYTES);
  sliding = true;
  needFlush = false; frameIsMap = false;
  return true;
}

// 合成一帧：全采用纯 32 位整块高速 memcpy 进行物理平移对接（Push-Slide），彻底杜绝逐像素 SPIRAM 运算与灰色裂痕
void slideCompose(int p) {
  const int W = LCD_WIDTH, H = LCD_HEIGHT;
  if (p < 0) p = 0;
  if (p > (dragHoriz ? W : H)) p = dragHoriz ? W : H;
  uint16_t *fb = gfx->getFramebuffer();

  if (dragHoriz) {
    for (int y = 0; y < H; y++) {
      int h = chordHalf[y];
      if (!h) continue;
      int xa = max(0, W / 2 - h), xb = min(W, W / 2 + h);
      uint16_t *row = fb + (size_t)y * W;
      const uint16_t *o = slideOld + (size_t)y * W;
      const uint16_t *n = slideNew + (size_t)y * W;

      if (dragSign > 0) { // 新页面从左向右推进来 (向右平移)
        // 新页面占据 [0, p)，取自 slideNew 的 [W - p, W)
        int a1 = xa, b1 = min(p, xb);
        if (b1 > a1) memcpy(row + a1, n + (W - p) + a1, (b1 - a1) * 2);

        // 旧页面占据 [p, W)，取自 slideOld 的 [0, W - p)
        int a2 = max(p, xa), b2 = xb;
        if (b2 > a2) memcpy(row + a2, o + (a2 - p), (b2 - a2) * 2);
      } else {            // 新页面从右向左推进来 (向左平移)
        // 旧页面占据 [0, W - p)，取自 slideOld 的 [p, W)
        int a1 = xa, b1 = min(W - p, xb);
        if (b1 > a1) memcpy(row + a1, o + p + a1, (b1 - a1) * 2);

        // 新页面占据 [W - p, W)，取自 slideNew 的 [0, p)
        int a2 = max(W - p, xa), b2 = xb;
        if (b2 > a2) memcpy(row + a2, n + (a2 - (W - p)), (b2 - a2) * 2);
      }
    }
  } else {
    // 纵向物理平移 (整行极速拷贝)
    for (int y = 0; y < H; y++) {
      int h = chordHalf[y];
      if (!h) continue;
      int xa = max(0, W / 2 - h), xb = min(W, W / 2 + h);
      uint16_t *row = fb + (size_t)y * W;

      if (dragSign > 0) { // 新页面从上向下滑入
        if (y < p) {
          int sy = y + (H - p);
          memcpy(row + xa, slideNew + (size_t)sy * W + xa, (xb - xa) * 2);
        } else {
          int sy = y - p;
          memcpy(row + xa, slideOld + (size_t)sy * W + xa, (xb - xa) * 2);
        }
      } else {            // 新页面从下向上滑入
        if (y < H - p) {
          int sy = y + p;
          memcpy(row + xa, slideOld + (size_t)sy * W + xa, (xb - xa) * 2);
        } else {
          int sy = y - (H - p);
          memcpy(row + xa, slideNew + (size_t)sy * W + xa, (xb - xa) * 2);
        }
      }
    }
  }
  flushAsync();
  needFlush = false; frameIsMap = false;
}

// 换页完成
void slideCommit() {
  const size_t BYTES = (size_t)LCD_WIDTH * LCD_HEIGHT * 2;
  sliding = false; dragging = false;
  page = dragTarget;
  pageAt = millis();
  memcpy(gfx->getFramebuffer(), slideNew, BYTES);
  needFlush = true; frameIsMap = false;
  if (page == 2) {
    onWaitScreen = false; musicDirty = true; pendingEvt = "T,M,Q";
  } else if (page == 1) {
    lastSlideSx = dragHoriz ? dragSign : 0; lastSlideSy = dragHoriz ? 0 : dragSign;
    onWaitScreen = false;
    settingsDirty = true;
  } else if (page == 3) {
    onWaitScreen = false;
    leanDirty = true;
  } else if (page == 4) {
    onWaitScreen = false;
    CompanionMode::enter();
  } else {
    if (inNav) navDirty = true;
    else { onWaitScreen = true; }
  }
}

// 没换成：回到原页面
void slideCancel() {
  sliding = false; dragging = false;
  renderPage(page);
  if (page == 2) musicDirty = true;
  else if (page == 1) settingsDirty = false;
  else if (page == 3) leanDirty = true;
  else if (page == 4) { onWaitScreen = false; CompanionMode::drawInitialFrame(); }
  else if (inNav) navDirty = true;
  else { onWaitScreen = true; }
  needFlush = true;
}

// 丝滑二次减速曲线（Ease-Out Quad），起步迅捷，收尾自然吸附，结合推屏流水线稳定输出
void slideAnimate(float p0, float p1, int ms) {
  unsigned long t0 = millis();
  for (;;) {
    unsigned long now = millis();
    float t = (now - t0) / (float)ms;
    if (t >= 1.0f) break;
    float e = t * (2.0f - t);
    slideCompose((int)lroundf(p0 + (p1 - p0) * e));
    delay(1);
  }
  slideCompose((int)lroundf(p1));
}

// 触摸向量统一换算：先修正芯片坐标的镜像，再按刷屏的逆旋转映射到画布。
void touchVectorToCanvas(float &dx, float &dy) {
  if (TOUCH_FLIP_X) dx = -dx;
  if (TOUCH_FLIP_Y) dy = -dy;
  float ox = dx, oy = dy;
  if (rotFree) { dx = ox * rotCosF + oy * rotSinF; dy = -ox * rotSinF + oy * rotCosF; }
  else if (screenRot == 1) { dx = oy; dy = -ox; }
  else if (screenRot == 2) { dx = -ox; dy = -oy; }
  else if (screenRot == 3) { dx = -oy; dy = ox; }
}

// 手指在拖：(dx, dy) = 从按下到现在的位移
void dragMove(int dx, int dy, unsigned long now) {
  float vx = dx, vy = dy;
  touchVectorToCanvas(vx, vy);
  dx = (int)lroundf(vx); dy = (int)lroundf(vy);
  if (!dragging) {
    int threshold = page == 2 ? 36 : DRAG_START;
    if (abs(dx) < threshold && abs(dy) < threshold) return;
    dragHoriz = abs(dx) >= abs(dy);
    int d = dragHoriz ? dx : dy;
    dragSign = d > 0 ? 1 : -1;
    if (page == 2) { if (!dragHoriz || dragSign > 0) return; dragTarget = 0; }
    else if (page == 1) { if (!dragHoriz || dragSign < 0) return; dragTarget = 0; }
    else if (page == 3) {
      // 倾角仪表在主界面下方：如果垂直向下滑动 (dy > 0, dragSign > 0)，返回主页 0
      if (dragHoriz || dragSign < 0) return;
      dragTarget = 0;
    }
    else if (page == 4) {
      // 伴侣模式在屏幕上方：由于长按 AB 键返回，这里不进行常规滑动换页，避免与表情互动冲突
      return;
    }
    else if (dragHoriz) dragTarget = dragSign < 0 ? 1 : 2;
    else dragTarget = dragSign < 0 ? 3 : 4; // 手指上滑 dy < 0 进入 page 3(倾角)，从上往下滑动 dy > 0 进入 page 4(伴侣模式)
    if (!slidePrepare(dragTarget)) return;
    dragging = true;
    dragP = 0; dragV = 0; dragT = now;
  }
  float p = (dragHoriz ? dx : dy) * dragSign;
  if (p < 0) p = 0;
  float dt = now - dragT;
  if (dt > 0) dragV = dragV * 0.5f + ((p - dragP) / dt) * 0.5f;
  dragP = p; dragT = now;
  slideCompose((int)p);
}

// 松手：拖过 30% 或者往前甩出去 → 顺势滑完；否则弹回
void dragEnd() {
  if (!dragging) return;
  int full = dragHoriz ? LCD_WIDTH : LCD_HEIGHT;
  bool go = dragP > full * 0.3f || (dragV > 0.35f && dragP > 24);
  if (dragV < -0.35f) go = false;                       // 往回甩：取消
  float target = go ? full : 0;
  float left = fabsf(target - dragP);
  int ms = 90 + (int)(130.0f * left / full);
  if (go && dragV > 0.5f) ms = max(90, (int)(ms * 0.75f));
  slideAnimate(dragP, target, ms);
  if (go) slideCommit(); else slideCancel();
}

// 来电等情况：直接放弃拖动
void dragAbort() {
  if (!dragging) return;
  sliding = false; dragging = false;
  if (page == 2) musicDirty = true; else if (page == 1) settingsDirty = true; else if (page == 3) leanDirty = true; else if (inNav) navDirty = true;
}

// 将触摸点换算到画布坐标，按钮使用较大的点按范围 (0:上一曲, 1:播放暂停, 2:下一曲, 3:循环模式, 4:Like红心)
int musicButtonAt(int x, int y) {
  return -1;
}

void musicTap(int x, int y) {
  // 音乐页点按全部在 TouchInput 统一处理 (封面滑动切歌/轻触播放暂停/Like红心)
}

void showPageAnimated(int target, int sx, int sy) {
  if (page == target) return;
  extern bool settingsAutoRot;
  if (page == 1 && settingsAutoRot) {
    settingsAutoRot = false;
    setScreenDeg(screenDeg, true);
  }
  dragHoriz = sx != 0 || sy == 0;
  dragSign = dragHoriz ? (sx ? sx : 1) : sy;
  dragTarget = target;
  if (!slidePrepare(target)) { page = target; renderPage(target); needFlush = true; return; }
  dragging = true;
  slideAnimate(0, dragHoriz ? LCD_WIDTH : LCD_HEIGHT, 220); // 优化为黄金 220ms，利落丝滑
  slideCommit();
}

// 音乐页在路口前回导航，其余时候保持显示，便于连续切歌。
void musicTick() {
  if (musicAckUntil && (long)(millis() - musicAckUntil) >= 0) {
    if (musicAck == 1) { musicAck = 4; musicAckUntil = millis() + 2500; }
    else { musicAck = 0; musicAckUntil = 0; }
    musicDirty = true;
  }
  if (page != 2 || callOn || pairOn || sliding) return;
  if (inNav && !cruiseOn && navDir != "S" && navDir.length() && navDist > 0 && navDist < 200 && millis() - pageAt > 3000) {
    showPageAnimated(0, -1, 0);
    return;
  }
  static unsigned long lastMusicSecTick = 0;
  if (musicPlaying && musicDuration > 0 && millis() - lastMusicSecTick >= 1000) {
    lastMusicSecTick = millis();
    musicDirty = true;
  }
  // 封面切歌离开动画帧驱动 (每 20ms 一帧，滑动离开屏幕)
  static unsigned long lastCoverAnimTick = 0;
  if (coverFlySpeed != 0 && millis() - lastCoverAnimTick >= 20) {
    lastCoverAnimTick = millis();
    coverSlideDx += coverFlySpeed;
    if (coverFlySpeed < 0 && coverSlideDx <= -220) {
      // 向左离开完成
      coverFlySpeed = 0;
      coverSlideDx = 0;
    } else if (coverFlySpeed > 0 && coverSlideDx >= 220) {
      // 向右离开完成
      coverFlySpeed = 0;
      coverSlideDx = 0;
    } else if (abs(coverFlySpeed) < 30) {
      // 只有在主动回弹模式 (coverFlySpeed = +/-20) 时才判断回弹归位
      if ((coverFlySpeed < 0 && coverSlideDx <= 0) || (coverFlySpeed > 0 && coverSlideDx >= 0)) {
        coverSlideDx = 0;
        coverFlySpeed = 0;
      }
    }
    musicDirty = true;
  }

  if (coverPendingSingleTap && (long)(millis() - lastCoverTapAt) > 300) {
    coverPendingSingleTap = false;
    lastCoverTapAt = 0;
    static unsigned long lastPlayPauseSentAt = 0;
    if (millis() - lastPlayPauseSentAt >= 500) {
      lastPlayPauseSentAt = millis();
      if (hidMusicMode) {
        if (!hidMediaReady() && !appleMedia.controlReady(1)) {
          musicAck = 7; musicAckUntil = millis() + 2500;
        } else {
          appleMedia.control(1);
        }
      } else {
        pendingEvt = "T,M,T,0,0,1";
        // 状态完全由手机 #Z 真实上报驱动，固件不进行伪反转，避免双向打架
        musicAck = 1; musicAckUntil = millis() + 2500;
      }
      CompanionMode::startVibration(80, 30);
      musicDirty = true;
    }
  }
  static bool lastVolShowing = false;
  bool nowVolShowing = volSliding || (millis() < volActiveUntil);
  if (lastVolShowing != nowVolShowing) {
    lastVolShowing = nowVolShowing;
    musicDirty = true;
  }
  if (musicDirty) { musicDirty = false; drawMusic(); }
}

// 每圈调用：设置页要不要重画
void settingsTick() {
  if (page != 1 || callOn || pairOn || sliding) return;
  if (settingsDirty) { settingsDirty = false; drawSettingsPage(); }
}

// 每圈调用：倾角与 G 值刷新
void leanTick() {
  LeanAngleMeter::update();
  if (page != 3 || callOn || pairOn || sliding) return;
  static unsigned long lastLeanDraw = 0;
  if (millis() - lastLeanDraw >= 33 || leanDirty) {
    lastLeanDraw = millis();
    leanDirty = false;
    drawLeanMeter();
  }
}

void drawStaleOverlay() {
  drawRedRing();
  printCentered("NO DATA", CX, 412, 3, C_RED);
  needFlush = true;
}

