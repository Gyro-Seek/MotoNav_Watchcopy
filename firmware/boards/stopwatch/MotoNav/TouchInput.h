extern int coverSlideDx;
extern int coverFlySpeed;
#pragma once
#include <Arduino.h>
#include "TouchDrvCSTXXX.hpp"
#include "BoardStopWatchInit.h"

// ================= v5.1 来电显示 =================
// 手机来电时整屏显示：上面 “INCOMING CALL”，中间绿色电话图标带往外扩散的波纹，下面是名字（手机渲染好的
// 文字图片，图片栏 2）和号码；接听或挂断后回到原来的画面（地图 / 大箭头 / 首页）
bool callOn = false;
String callNum = "";
unsigned long callAt = 0, callSeenAt = 0;

// v5.2 触屏接电话：按住任意位置 HOLD_MS 毫秒 → 发 "T,A" 给手机（v6.9 800 → 200）
#define HOLD_MS 200
TouchDrvCST816 touch;   // StopWatch：CST820B（chipId 0xB7）属于 CST816 族；微雪 1.75 的 CST9217 才用 CST92xx
bool touchOK = false;
unsigned long touchHoldAt = 0, touchLastSeen = 0;
float touchHold = 0;                 // 0~1 按住的进度
bool callAnswerSent = false;
unsigned long callAnswerAt = 0;
String pendingProf = "";             // v5.8 分步用时
// pendingEvt moved to GlobalConfig.h

// v5.3 触摸芯片一有动静就拉低中断脚；平时只看这个标记，不用一直读 I2C
volatile bool touchIrq = false;
void IRAM_ATTR onTouchIrq() { touchIrq = true; }

void touchInit() {
  StopWatchBoard::tpReset();      // StopWatch：触摸复位在 M5IOE1 上，按官方时序手动来一次
  touch.setPins(TP_RESET, TP_INT);
  touchOK = touch.begin(Wire, 0x15, IIC_SDA, IIC_SCL);   // StopWatch CST820B 地址 0x15（微雪 CST9217 是 0x5A）
  if (!touchOK) {
    // M5IOE1 初始化会把总线提到 400kHz，CST820 保守按 100kHz 跑——降速重试一次（换料批次时留个后手）
    Wire.setClock(100000);
    delay(50);
    StopWatchBoard::tpReset();
    touchOK = touch.begin(Wire, 0x15, IIC_SDA, IIC_SCL);
  }
  Serial.println(touchOK ? "touch ok" : "touch not found");
  if (touchOK) attachInterrupt(TP_INT, onTouchIrq, FALLING);   // v5.3
}

// 执行上一曲 (在任意界面通用)
static void triggerKeyPrevTrack() {
  if (hidMusicMode) {
    if (!hidMediaReady() && !appleMedia.controlReady(0)) {
      musicAck = 7; musicAckUntil = millis() + 2500;
    } else {
      appleMedia.control(0);
    }
  } else {
    pendingEvt = "T,M,P,0,0,0";
    musicAck = 1; musicAckUntil = millis() + 2500;
  }
  if (page == 2) {
    coverFlySpeed = +32;
  }
  CompanionMode::startVibration(120, 45);
  musicDirty = true;
}

// 执行下一曲 (在任意界面通用)
static void triggerKeyNextTrack() {
  if (hidMusicMode) {
    if (!hidMediaReady() && !appleMedia.controlReady(2)) {
      musicAck = 7; musicAckUntil = millis() + 2500;
    } else {
      appleMedia.control(2);
    }
  } else {
    pendingEvt = "T,M,N,0,0,2";
    musicAck = 1; musicAckUntil = millis() + 2500;
  }
  if (page == 2) {
    coverFlySpeed = -32;
  }
  CompanionMode::startVibration(120, 45);
  musicDirty = true;
}

// StopWatch 实体按键交互：
//   面对屏幕看：左侧 KEY A (GPIO 2 / G2)，右侧 KEY B (GPIO 1 / G1)
//   - 长按 KEY A (>= 500ms)：任意界面上一首 (带震动反馈)
//   - 长按 KEY B (>= 500ms)：任意界面下一首 (带震动反馈)
//   - 同时按住 AB 键：切换倾角/G值表 <-> 主界面 (伴侣模式下长按800ms退回主页)
//   - 单按 KEY A / B (松手确认，防长按冲突)：
//       - 伴侣模式：浏览上一个 / 下一个表情
//       - 主页：A 切音乐页(左滑入)，B 切天气页(右滑入)
//       - 其它页：退回主页
void buttonTick() {
  static bool lastA = true, lastB = true;
  static unsigned long aDownAt = 0, bDownAt = 0;
  static bool aHoldFired = false, bHoldFired = false;
  static bool comboActive = false;
  static unsigned long lastActionAt = 0;
  static unsigned long abBothDownAt = 0;
  static bool abHoldTriggered = false;

  bool a = digitalRead(BTN_A);
  bool b = digitalRead(BTN_B);
  unsigned long now = millis();

  // 1. 到达目的地结算界面：按任意实体键立即退出结算返回主页
  if (fxOn) {
    if ((!a && lastA) || (!b && lastB)) {
      stopArriveFx();
      CompanionMode::startVibration(140, 50);
      lastA = a; lastB = b;
      return;
    }
    lastA = a; lastB = b;
    return;
  }

  // 2. 双键同时按下检测（优先级最高）
  if (!a && !b) {
    // 抑制单键短按与单键长按切歌
    aHoldFired = true;
    bHoldFired = true;
    aDownAt = 0;
    bDownAt = 0;

    // 伴侣模式专用：双键长按 800ms 返回主页
    if (page == 4) {
      if (abBothDownAt == 0) abBothDownAt = now;
      if (!abHoldTriggered && now - abBothDownAt >= 800) {
        abHoldTriggered = true;
        CompanionMode::startVibration(180, 70);
        showPageAnimated(0, 0, 1);
      }
      lastA = a; lastB = b;
      return;
    }

    // 非伴侣模式：双键切换倾角/G值表 <-> 主页
    if (!comboActive && (now - lastActionAt > 350)) {
      comboActive = true;
      lastActionAt = now;
      if (!sliding && !callOn && !pairOn && !fxOn) {
        if (page != 3) {
          showPageAnimated(3, 0, -1);
        } else {
          showPageAnimated(0, 0, 1);
        }
      }
    }
    lastA = a; lastB = b;
    return;
  } else {
    abBothDownAt = 0;
    if (a && b) abHoldTriggered = false;
  }

  // 双键均释放时解除双键锁
  if (a && b) {
    comboActive = false;
  }

  // 若双键尚未完全释放，避免残留单键动作
  if (comboActive) {
    lastA = a; lastB = b;
    return;
  }

  // 3. KEY A 状态机 (长按 500ms 上一首，短按松开换页)
  if (!a) {
    if (lastA) {
      // 刚按下
      aDownAt = now;
      aHoldFired = false;
    } else if (aDownAt > 0 && !aHoldFired && (now - aDownAt >= 500)) {
      // 持续按住满 500ms：触发上一首！
      aHoldFired = true;
      triggerKeyPrevTrack();
    }
  } else if (!lastA) {
    // 刚松开
    if (!aHoldFired && aDownAt > 0 && (now - aDownAt < 500) && (now - lastActionAt > 200)) {
      // 短按松手确认：执行原本单按 A 动作
      lastActionAt = now;
      if (page == 4) {
        CompanionMode::noteInteraction();
        CompanionMode::avatar.previous(now);
        CompanionMode::startVibration(125, 35);
      } else if (!sliding && !callOn && !pairOn && !fxOn) {
        if (page == 0) {
          showPageAnimated(2, 1, 0); // 主页 -> 音乐页 (从左滑入)
        } else if (page == 3) {
          showPageAnimated(0, 0, 1); // 倾角页 -> 主页
        } else {
          showPageAnimated(0, page == 2 ? -1 : 1, 0); // 音乐/天气页 -> 主页
        }
      }
    }
    aDownAt = 0;
    aHoldFired = false;
  }

  // 4. KEY B 状态机 (长按 500ms 下一首，短按松开换页)
  if (!b) {
    if (lastB) {
      // 刚按下
      bDownAt = now;
      bHoldFired = false;
    } else if (bDownAt > 0 && !bHoldFired && (now - bDownAt >= 500)) {
      // 持续按住满 500ms：触发下一首！
      bHoldFired = true;
      triggerKeyNextTrack();
    }
  } else if (!lastB) {
    // 刚松开
    if (!bHoldFired && bDownAt > 0 && (now - bDownAt < 500) && (now - lastActionAt > 200)) {
      // 短按松手确认：执行原本单按 B 动作
      lastActionAt = now;
      if (page == 4) {
        CompanionMode::noteInteraction();
        CompanionMode::avatar.next(now);
        CompanionMode::startVibration(125, 35);
      } else if (!sliding && !callOn && !pairOn && !fxOn) {
        if (page == 0) {
          showPageAnimated(1, -1, 0); // 主页 -> 天气页 (从右滑入)
        } else if (page == 3) {
          showPageAnimated(0, 0, 1);  // 倾角页 -> 主页
        } else {
          showPageAnimated(0, page == 2 ? -1 : 1, 0);  // 音乐/天气页 -> 主页
        }
      }
    }
    bDownAt = 0;
    bHoldFired = false;
  }

  lastA = a;
  lastB = b;
}

bool touchDown = false;
int16_t touchX0 = 0, touchY0 = 0, touchX1 = 0, touchY1 = 0;
void dragMove(int dx, int dy, unsigned long now);   // v5.5 跟手换页
int musicButtonAt(int x, int y);
void musicTap(int x, int y);
void dragEnd();
void dragAbort();

// 读触摸：按下 → 报坐标；来电时按住够久 → 接听；拖动 → 跟手换页（v5.5）
// 手指离开超过 0.15 秒才算松开（防止读数偶尔丢一下）
void touchPoll() {
  static unsigned long lastPoll = 0;
  static bool calibTriggered = false;
  unsigned long now = millis();
  if (!touchOK) return;
  if (!touchIrq && !touchDown && !callOn) return;
  if (now - lastPoll < 12) return;
  lastPoll = now;
  touchIrq = false;
  if (callAnswerSent && now - callAnswerAt > 4000) callAnswerSent = false;   // 4 秒还在响：允许再按一次
  int16_t x[5] = {0}, y[5] = {0};
  uint8_t n = touch.getPoint(x, y, 1);
  if (page == 4) {
    if (n > 0) {
      touchDown = true;
      touchLastSeen = now;
      float tdx = x[0] - CX, tdy = y[0] - CX;
      touchVectorToCanvas(tdx, tdy);
      CompanionMode::handleTouch(true, (int16_t)lroundf(CX + tdx), (int16_t)lroundf(CX + tdy));
    } else {
      touchDown = false;
      CompanionMode::handleTouch(false, 0, 0);
    }
    return;
  }
  if (n > 0) {
    if (!touchDown) {
      touchDown = true;
      touchHoldAt = now;
      touchX0 = touchX1 = x[0]; touchY0 = touchY1 = y[0];
      pendingEvt = "T,P," + String(x[0]) + "," + String(y[0]);
      // 导航地图页面：双击按住缩放检测
      if (page == 0 && (inNav || cruiseOn || mapModeActive()) && !callOn && !pairOn && !fxOn) {
        // 双击时间窗口大幅放宽至 650ms，距离容差放宽至 90 像素，从容易按，绝不误触滑动
        if (lastMapTapAt > 0 && (now - lastMapTapAt <= 650) &&
            abs(x[0] - lastMapTapX) <= 90 && abs(y[0] - lastMapTapY) <= 90) {
          mapZoomActive = true;
          touchEat = true;
          mapZoomStartX = x[0];
          mapZoomStartY = y[0];
          mapZoomStartScale = userMapScale;
          mapZoomHintUntil = now + 2500;
          lastMapTapAt = 0;
          CompanionMode::startVibration(70, 30);
        }
      }
      if (page == 2 && !callOn && !pairOn) {
        float tdx = x[0] - CX, tdy = y[0] - CX;
        touchVectorToCanvas(tdx, tdy);
        int cx0 = (int)lroundf(CX + tdx);
        int cy0 = (int)lroundf(CX + tdy);
        // 1. 正左方 9 点钟贴边 VOLUME 与音量轨区域 (X <= 120, |Y - CX| <= 90)
        float distSq = (float)(cx0 - CX) * (cx0 - CX) + (float)(cy0 - CX) * (cy0 - CX);
        if (cx0 <= 120 && abs(cy0 - CX) <= 90 && distSq >= 150.0f * 150.0f) {
          volSliding = true;
          volActiveUntil = now + 2000;
          touchEat = true;
          float a = atan2f((float)(cx0 - CX), (float)(CX - cy0));
          if (a < 0) a += 2.0f * (float)M_PI;
          float p = a / (2.0f * (float)M_PI);
          int newVol = constrain(lroundf((p - 0.68f) / (0.82f - 0.68f) * 100.0f), 0, 100);
          if (newVol != musicVolume) {
            musicVolume = newVol;
            musicDirty = true;
          }
        }
        // 2. 专辑封面区域 (放大至 206x206, X: 120~346, Y: 42~260)
        else if (cx0 >= 120 && cx0 <= 346 && cy0 >= 42 && cy0 <= 260) {
          coverTouchActive = true;
          touchEat = true; // 拦截整页切换滑动
        }
        // 4. 封面之外其它区域：不设 touchEat，正常允许 dragMove 整页拖拽换页！
      }
      if (fxOn && !callOn) {
        stopArriveFx();
        CompanionMode::startVibration(140, 50); // 触屏轻触退出也给予震动反馈
        touchEat = true;
      }          // v7.1 点一下结束到达特效
    }
    touchX1 = x[0]; touchY1 = y[0];
    touchLastSeen = now;

    if (page == 2 && volSliding) {
      float tdx = touchX1 - CX, tdy = touchY1 - CX;
      touchVectorToCanvas(tdx, tdy);
      int cx1 = (int)lroundf(CX + tdx);
      int cy1 = (int)lroundf(CX + tdy);
      float a = atan2f((float)(cx1 - CX), (float)(CX - cy1));
      if (a < 0) a += 2.0f * (float)M_PI;
      float p = a / (2.0f * (float)M_PI);
      int newVol = constrain(lroundf((p - 0.68f) / (0.82f - 0.68f) * 100.0f), 0, 100);
      if (abs(newVol - musicVolume) >= 2) {
        musicVolume = newVol;
        volActiveUntil = now + 2000;
        musicDirty = true;
      }
    }

    if (page == 2 && coverTouchActive && !volSliding) {
      float vx = touchX1 - touchX0, vy = touchY1 - touchY0;
      touchVectorToCanvas(vx, vy);
      int curDx = (int)lroundf(vx);
      int curDy = (int)lroundf(vy);
      if (abs(curDx) > 10 && abs(curDx) > abs(curDy)) {
        coverSlideDx = constrain(curDx, -180, 180);
        musicDirty = true;
      }
    }

    // 倾角仪表页面：校准按钮长按 1.5 秒判定，彻底杜绝骑行轻碰误触
    if (page == 3 && touchDown) {
      float tdx = touchX0 - CX, tdy = touchY0 - CX;
      touchVectorToCanvas(tdx, tdy);
      int cy0 = (int)lroundf(CX + tdy);
      int cx0 = (int)lroundf(CX + tdx);
      if (cy0 >= 340 && abs(cx0 - CX) <= 100) {
        if (now - touchHoldAt >= 1500 && !calibTriggered) {
          calibTriggered = true;
          LeanAngleMeter::calibrateZero();
          #ifdef M5PM1_ADDR
          M5PM1.setVibration(120);
          #endif
          leanDirty = true;
        }
      }
    }

    if (mapZoomActive) {
      touchEat = true;
      float vx = touchX1 - mapZoomStartX;
      float vy = touchY1 - mapZoomStartY;
      touchVectorToCanvas(vx, vy);
      float dy = vy; // 在屏幕画布方向：dy < 0 向上滑放大，dy > 0 向下滑缩小
      // 优化滑动行程灵敏度：每垂直滑动 75 像素对应 1.0x 缩放变化，手指在 466 AMOLED 屏幕内轻松滑至 2.5x/3.0x
      float delta = -dy * (1.0f / 75.0f);
      userMapScale = constrain(mapZoomStartScale + delta, 0.30f, 3.00f);
      mapZoomHintUntil = now + 2000;
      navDirty = true;
    }

    if (callOn || pairOn || touchEat || fxOn) dragAbort();
    else {
      // 导航模式下：若在双击等待窗口期（650ms 内）且位移较小时，优先等待双击缩放，避免误触发切页拖动
      bool inMap = (page == 0 && (inNav || cruiseOn || mapModeActive()));
      if (inMap && lastMapTapAt > 0 && (now - lastMapTapAt <= 650) && abs(touchX1 - touchX0) < 45 && abs(touchY1 - touchY0) < 45) {
        // 暂不触发换页拖动
      } else {
        dragMove(touchX1 - touchX0, touchY1 - touchY0, now);
      }
    }
  } else if (touchDown && now - touchLastSeen > 70) {
    touchDown = false;
    unsigned long pressDuration = now - touchHoldAt;
    touchHoldAt = 0;
    calibTriggered = false;
    if (mapZoomActive) {
      mapZoomActive = false;
      touchEat = true;
      mapZoomSaveAt = now + 1500;
      mapZoomHintUntil = now + 1200;
      CompanionMode::startVibration(90, 35);
      navDirty = true;
    } else if (page == 0 && (inNav || cruiseOn || mapModeActive()) && !callOn && !pairOn && !fxOn) {
      float vx = touchX1 - touchX0, vy = touchY1 - touchY0;
      touchVectorToCanvas(vx, vy);
      // 放宽轻触判定：按压时长放宽至 480ms，位移容差放宽至 48 像素
      if (pressDuration >= 15 && pressDuration < 480 && abs(vx) <= 48 && abs(vy) <= 48) {
        lastMapTapAt = now;
        lastMapTapX = touchX0;
        lastMapTapY = touchY0;
      }
    }
    if (page == 2 && volSliding) {
      volSliding = false;
      volActiveUntil = now + 1500;
      touchEat = true;
      pendingEvt = "T,M,V," + String(musicVolume);
      musicDirty = true;
    }
    if (page == 2 && coverTouchActive) {
      coverTouchActive = false;
      touchEat = true;
      float vx = touchX1 - touchX0, vy = touchY1 - touchY0;
      touchVectorToCanvas(vx, vy);
      int dx = (int)lroundf(vx);
      int dy = (int)lroundf(vy);
      // 1. 明确的左右横向手势切歌 (位移 >= 45 像素，且水平明显大于垂直)
      if (abs(dx) >= 45 && abs(dx) >= (int)(abs(dy) * 1.2f)) {
        coverPendingSingleTap = false;
        lastCoverTapAt = 0;
        if (dx < 0) {
          triggerKeyNextTrack(); // 向左滑 -> 下一曲 (发指令+启动向左飞出动画)
        } else {
          triggerKeyPrevTrack(); // 向右滑 -> 上一曲 (发指令+启动向右飞出动画)
        }
      }
      // 2. 原地轻触判定 (短按点击或位移极小，绝对优先作为点击播放/暂停，绝不误切歌)
      else if ((pressDuration >= 20 && pressDuration < 450) || (abs(dx) <= 35 && abs(dy) <= 35)) {
        coverSlideDx = 0;
        coverFlySpeed = 0;
        float tdx = touchX0 - CX, tdy = touchY0 - CX;
        touchVectorToCanvas(tdx, tdy);
        int cx0 = (int)lroundf(CX + tdx);
        int cy0 = (int)lroundf(CX + tdy);

        int ldx = cx0 - 308, ldy = cy0 - 226;

        if (ldx * ldx + ldy * ldy <= 30 * 30) {
          // 点击封面右下角：切换 Like / Dislike (去除左下角循环模式按钮后，右下角 Like 独立生效)
          coverPendingSingleTap = false;
          lastCoverTapAt = 0;
          musicLiked = !musicLiked;
          pendingEvt = String("T,M,L,") + (musicLiked ? "1" : "0");
          musicAck = 1; musicAckUntil = now + 2500;
          CompanionMode::startVibration(120, 40);
          musicDirty = true;
        } else {
          // 封面中心主体：双击 vs 单击判定播放/暂停
          unsigned long dt = (lastCoverTapAt > 0) ? (now - lastCoverTapAt) : 99999UL;
          if (dt < 140) {
            // 物理抬手抖动或电容屏脱离瞬态毛刺 (< 140ms)：直接过滤丢弃！维持原单击定时器正常判定
          } else if (dt <= 360) {
            // 真正的人类双击 (两次敲击间隔在 140ms ~ 360ms 之间)：触发 Like / Dislike
            coverPendingSingleTap = false;
            lastCoverTapAt = 0;
            musicLiked = !musicLiked;
            pendingEvt = String("T,M,L,") + (musicLiked ? "1" : "0");
            musicAck = 1; musicAckUntil = now + 2500;
            CompanionMode::startVibration(150, 45);
            musicDirty = true;
          } else {
            // 第一次轻触：开启延迟确认，等待是否会有第二次敲击
            coverPendingSingleTap = true;
            lastCoverTapAt = now;
          }
        }
      }
      // 3. 拖拽了但不够切歌阈值：弹性回弹原位
      else {
        if (coverSlideDx != 0) {
          coverFlySpeed = (coverSlideDx > 0) ? -20 : +20;
          musicDirty = true;
        }
      }
    }
    if (callOn || pairOn || touchEat || fxOn) dragAbort();
    else {
      // 统一将硬件物理触摸点按当前屏幕旋转映射至画布坐标系，彻底杜绝旋转后的触控错位！
      float tdx = touchX0 - CX, tdy = touchY0 - CX;
      touchVectorToCanvas(tdx, tdy);
      int canvasX = (int)lroundf(CX + tdx);
      int canvasY = (int)lroundf(CX + tdy);

      if (page == 2 && abs(touchX1 - touchX0) < 36 && abs(touchY1 - touchY0) < 36) musicTap(canvasX, canvasY);
      if (page == 0 && !inNav && abs(touchX1 - touchX0) < 36 && abs(touchY1 - touchY0) < 36) waitingScreenTap(canvasX, canvasY);
      if (page == 1 && abs(touchX1 - touchX0) < 36 && abs(touchY1 - touchY0) < 36) settingsPageTap(canvasX, canvasY);
      if (page == 3 && abs(touchX1 - touchX0) < 36 && abs(touchY1 - touchY0) < 36) leanMeterTap(canvasX, canvasY);
      dragEnd();
    }
    touchEat = false;
    if (musicPressed >= 0) { musicPressed = -1; musicDirty = true; }
  }
  // 来电：按住不动才算（滑动不算）
  bool still = abs(touchX1 - touchX0) < 60 && abs(touchY1 - touchY0) < 60;
  touchHold = (callOn && touchDown && still) ? min(1.0f, (now - touchHoldAt) / (float)HOLD_MS) : 0;
  if (touchHold >= 1 && !callAnswerSent) {
    callAnswerSent = true;
    callAnswerAt = now;
    touchHold = 0;
    pendingEvt = "T,A";
  }
}

// 电话听筒：一段拱形的圆点串当手柄，两头各一个大点当听筒和话筒，整体斜过来（常见的电话图标）
