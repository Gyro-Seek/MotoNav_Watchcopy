#pragma once
#include <Arduino.h>
#include <time.h>
#include "UiModern.h"
#include "DestHistory.h"

// 全局变量定义
DestItem destItems[MAX_DEST_ITEMS];
int destItemCount = 0;
bool destSheetOpen = false;
int destScrollOffset = 0;

bool onWaitScreen = false;
bool sliding = false;
int waitSt = 0;

// 页面分配：
// 0 = 导航 / 待机主页
// 1 = 圆屏设置 (SettingsPage)
// 2 = 音乐播放 (MusicPage)
// 3 = 倾角与 G 值仪表 (PageLeanMeter)
// 4 = 伴侣模式 (CompanionMode)
int page = 0;
unsigned long pageAt = 0;
bool leanDirty = false;
bool settingsDirty = false;

void drawLeanMeter();
void leanMeterTap(int x, int y);
void drawSettingsPage();
void settingsPageTap(int x, int y);
void drawMusic();
void musicTap(int x, int y);

// 绘制页面位置指示点 (圆屏底部/顶部现代微光圆点)
void drawPageDots() {
  if (page == 0 && inNav) return;
  // 横向三页：音乐在左(2)，主页居中(0)，设置在右(1)
  const int pageOrder[] = {2, 0, 1};
  for (int i = 0; i < 3; i++) {
    aaDisc(CX + (i - 1) * 18, 436, 3.5f, page == pageOrder[i] ? C_WHITE : 0x31A6);
  }
  // 底部第4点：倾角与G值仪表在下方(3)
  aaDisc(CX, 451, 3.5f, page == 3 ? C_WHITE : 0x31A6);
  // 顶部第5点：伴侣模式在上方(4)
  aaDisc(CX, 10, 3.5f, page == 4 ? C_WHITE : 0x31A6);
}

// 格式化月份缩写
static inline const char* getMonthStr(int m) {
  static const char* const months[] = {"JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"};
  if (m >= 1 && m <= 12) return months[m - 1];
  return "NOV";
}

// 格式化星期缩写
static inline const char* getWdayStr(int w) {
  static const char* const wdays[] = {"SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"};
  if (w >= 0 && w <= 6) return wdays[w];
  return "TUE";
}

// 绘制地点与导航历史毛玻璃抽屉浮层
static void drawDestinationsSheet() {
  const int sheetW = 380;
  const int sheetH = 340;
  const int sheetX = CX - sheetW / 2; // 43
  const int sheetY = CX - sheetH / 2; // 63

  // 1. 半透明毛玻璃暗黑圆角底座 (92% 纯黑磨砂)
  drawTranslucentRoundRect(sheetX, sheetY, sheetW, sheetH, 22, 0x0000, 235);
  gfx->drawRoundRect(sheetX, sheetY, sheetW, sheetH, 22, 0x39E7);

  // 2. 顶部标题栏
  drawRockstarStar(sheetX + 26, sheetY + 28, 9.0f, 4.0f, 0xFDE0, 0xFDE0);
  drawAaString(sheetX + 115, sheetY + 28, "DESTINATIONS", 1.8f, 1.0f, 12.0f, C_WHITE, true);

  // 右上角关闭按钮 (✕)
  drawTranslucentCircle(sheetX + sheetW - 28, sheetY + 28, 14, 0x2124, 160);
  gfx->drawCircle(sheetX + sheetW - 28, sheetY + 28, 14, 0x4A69);
  gfx->drawLine(sheetX + sheetW - 32, sheetY + 24, sheetX + sheetW - 24, sheetY + 32, C_WHITE);
  gfx->drawLine(sheetX + sheetW - 24, sheetY + 24, sheetX + sheetW - 32, sheetY + 32, C_WHITE);

  // 分隔线
  gfx->drawLine(sheetX + 18, sheetY + 52, sheetX + sheetW - 18, sheetY + 52, 0x2945);

  // 3. 地点卡片列表 (显示常用地点与历史记录，最多 4 项)
  destInitDefaults();
  int showCount = min(destItemCount, 4);
  const int itemW = sheetW - 32; // 348
  const int itemH = 56;
  const int itemX = sheetX + 16;
  int startY = sheetY + 64;

  for (int i = 0; i < showCount; i++) {
    int curY = startY + i * (itemH + 10);
    // 卡片背景
    drawTranslucentRoundRect(itemX, curY, itemW, itemH, 12, 0x10A2, 160);
    gfx->drawRoundRect(itemX, curY, itemW, itemH, 12, 0x31A6);

    // 左侧图标：收藏显示金色五角星，历史显示青色定位针
    if (destItems[i].type == 0) {
      drawRockstarStar(itemX + 24, curY + itemH / 2, 8.0f, 3.5f, 0xFDE0, 0xFDE0);
    } else {
      aaDisc(itemX + 24, curY + itemH / 2 - 3, 5.0f, C_CYAN);
      gfx->fillTriangle(itemX + 20, curY + itemH / 2 - 2,
                        itemX + 28, curY + itemH / 2 - 2,
                        itemX + 24, curY + itemH / 2 + 7, C_CYAN);
      aaDisc(itemX + 24, curY + itemH / 2 - 3, 2.0f, C_BLACK);
    }

    // 地点名称与地址
    const char *name = destItems[i].name[0] ? destItems[i].name : "Unknown Location";
    const char *addr = destItems[i].addr[0] ? destItems[i].addr : "Tap to route";
    drawAaString(itemX + 54, curY + 18, name, 1.8f, 1.0f, 12.0f, C_WHITE, false);
    drawAaString(itemX + 54, curY + 38, addr, 1.3f, 0.8f, 9.0f, 0x7BEF, false);

    // 右侧导航箭头 (>)
    drawAaString(itemX + itemW - 18, curY + itemH / 2, ">", 1.8f, 1.0f, 10.0f, 0x4A69, true);
  }

  // 底部提示
  drawAaString(CX, sheetY + sheetH - 18, "TAP ITEM TO START ROUTE", 1.2f, 0.75f, 8.5f, 0x4A69, true);
}

// 待机主页面完整重绘
void drawWaiting(int st) {
  waitSt = st;
  if (sliding) return;

  if (page == 2) { onWaitScreen = false; musicDirty = true; return; }
  if (page == 1) { onWaitScreen = false; settingsDirty = true; return; }
  if (page == 3) { onWaitScreen = false; leanDirty = true; return; }
  if (page == 4) { onWaitScreen = false; return; }

  onWaitScreen = true;

  // 1. 绘制正宗罪恶都市风格地图背景 (暖沙色街区、青绿水面、公园绿地、粉紫路线与车标，半透明暗化)
  drawThemedMapBackground();

  // 2. 顶部大号原生电池图标 (彻底恢复 Stopwatch 52x24 经典原版样式，内嵌电量数字，充电带闪电)
  extern void drawBattery(int x0, int y0, bool backing = false);
  drawBattery(CX - 28, 20, true);

  // 3. 原生经典连接状态提示 (居中醒目大字号，彻底告别细小微型胶囊)
  if (st == WAIT_READY || (bleConnected && bleAuthed)) {
    // 采用与罪恶都市地图一致的高雅柔和绿 0x760D
    aaDisc((float)(CX - 38), 58.0f, 4.5f, 0x760D);
    drawAaString(CX + 6, 58, "READY", 1.8f, 1.05f, 11.5f, 0x760D, true);
  } else if (st == WAIT_NOLINK || !bleConnected) {
    aaDisc((float)(CX - 42), 58.0f, 4.5f, C_GREY);
    drawAaString(CX + 6, 58, "NO LINK", 1.8f, 1.05f, 11.5f, C_GREY, true);
  } else {
    aaDisc((float)(CX - 48), 58.0f, 4.5f, C_RED);
    drawAaString(CX + 6, 58, "LINK LOST", 1.8f, 1.05f, 11.5f, C_RED, true);
  }

  // 4. 获取实时系统时间
  time_t nowSec = time(NULL);
  struct tm *t = localtime(&nowSec);
  int hour = t ? t->tm_hour : 12;
  int min  = t ? t->tm_min  : 0;
  int mon  = t ? (t->tm_mon + 1) : 11;
  int mday = t ? t->tm_mday : 3;
  int wday = t ? t->tm_wday : 2;

  // 5. 居中大时钟与日期毛玻璃半透明卡片 (136px~226px，高对比度磨砂底座，文字清晰优雅)
  drawTranslucentRoundRect(CX - 120, 136, 240, 90, 18, 0x0000, 200);
  gfx->drawRoundRect(CX - 120, 136, 240, 90, 18, 0x39E7);

  char clockBuf[12];
  snprintf(clockBuf, sizeof(clockBuf), "%02d:%02d", hour, min);
  drawAaString(CX, 168, clockBuf, 4.0f, 2.3f, 30.0f, C_WHITE, true);

  char dateBuf[24];
  snprintf(dateBuf, sizeof(dateBuf), "%s %02d  %s", getMonthStr(mon), mday, getWdayStr(wday));
  drawAaString(CX, 206, dateBuf, 1.8f, 1.05f, 12.0f, 0xAFBD, true);

  // 6. 经典 Rockstar (R星) 风格五角星按钮 (CX=233, Y=316)
  const int btnCY = 316;
  // 半透明磨砂纯黑底座 (毛玻璃质感，边缘柔和微光)
  drawTranslucentCircle(CX, btnCY, 32, 0x0000, 180);
  gfx->drawCircle(CX, btnCY, 32, 0x4A69);
  gfx->drawCircle(CX, btnCY, 33, 0x2124);

  // R星五角星：纯白实心填充，硬朗金黄轮廓描边
  drawRockstarStar(CX, btnCY, 18.0f, 7.5f, C_WHITE, 0xFDE0);

  // 按钮下方文字标签
  drawAaString(CX, btnCY + 44, "DESTINATIONS", 1.4f, 0.85f, 9.5f, 0x7BEF, true);

  // 7. 如果用户点击打开了目的地抽屉浮层，则覆盖绘制
  if (destSheetOpen) {
    drawDestinationsSheet();
  }

  // 8. 底部页面指示点
  drawPageDots();
  needFlush = true;
}

// 待机主页面点击处理 (在 TouchInput 中路由)
inline bool waitingScreenTap(int x, int y) {
  if (page != 0 || inNav) return false;

  // 如果目的地抽屉浮层已展开
  if (destSheetOpen) {
    const int sheetW = 380;
    const int sheetH = 340;
    const int sheetX = CX - sheetW / 2;
    const int sheetY = CX - sheetH / 2;

    // 点击右上角关闭按钮 (✕) 或卡片外部空白区域：关闭浮层
    int closeX = sheetX + sheetW - 28;
    int closeY = sheetY + 28;
    if ((x - closeX) * (x - closeX) + (y - closeY) * (y - closeY) <= 24 * 24 ||
        x < sheetX || x > sheetX + sheetW || y < sheetY || y > sheetY + sheetH) {
      destSheetOpen = false;
      drawWaiting(waitSt);
      return true;
    }

    // 检查是否点击了某个地点卡片项
    int showCount = min(destItemCount, 4);
    const int itemW = sheetW - 32;
    const int itemH = 56;
    const int itemX = sheetX + 16;
    int startY = sheetY + 64;

    for (int i = 0; i < showCount; i++) {
      int curY = startY + i * (itemH + 10);
      if (x >= itemX && x <= itemX + itemW && y >= curY && y <= curY + itemH) {
        // 触发微震反馈
        CompanionMode::startVibration(60, 25);
        // 发送启动导航规划指令给手机端
        pendingEvt = "T,DEST_GO," + String(i);
        destSheetOpen = false;
        drawWaiting(waitSt);
        return true;
      }
    }
    return true;
  }

  // 未展开浮层时：检查是否点击了 R星五角星按钮 (CX=233, btnCY=322, 半径 38)
  int dx = x - CX;
  int dy = y - 322;
  if (dx * dx + dy * dy <= 38 * 38) {
    CompanionMode::startVibration(50, 20);
    destSheetOpen = true;
    // 向手机请求最新的常用地点和历史
    if (bleConnected) {
      pendingEvt = "T,DEST_Q";
    }
    drawWaiting(waitSt);
    return true;
  }

  return false;
}
