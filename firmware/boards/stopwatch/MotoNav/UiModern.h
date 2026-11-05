#pragma once
#include <Arduino.h>

// =========================================================================
// MotoNav Modern UI Framework (Glassmorphism & Anti-Aliased Vector Primitives)
// 为 M5Stopwatch 打造的现代毛玻璃与抗锯齿矢量 UI 渲染引擎
// =========================================================================

// 1. 半透明毛玻璃圆角矩形 (带有磨砂玻璃质感与边缘微光)
static inline void drawTranslucentRoundRect(int rx, int ry, int rw, int rh, int radius, uint16_t tintColor = 0x0000, uint8_t alpha = 185) {
  uint16_t *fb = gfx->getFramebuffer();
  if (!fb) return;
  const int W = LCD_WIDTH;
  const int H = LCD_HEIGHT;
  int invA = 256 - alpha;
  uint32_t tintRB = (tintColor & 0xF81F) * alpha;
  uint32_t tintG  = (tintColor & 0x07E0) * alpha;

  int y0 = max(0, ry);
  int y1 = min(H - 1, ry + rh - 1);
  int r2 = radius * radius;

  for (int y = y0; y <= y1; y++) {
    int dy = 0;
    if (y < ry + radius) dy = (ry + radius) - y;
    else if (y > ry + rh - 1 - radius) dy = y - (ry + rh - 1 - radius);

    int cornerInset = 0;
    if (dy > 0 && radius > 0) {
      int span = (int)sqrtf((float)max(0, r2 - dy * dy));
      cornerInset = radius - span;
    }

    int x0 = max(0, rx + cornerInset);
    int x1 = min(W - 1, rx + rw - 1 - cornerInset);
    if (x0 > x1) continue;

    uint16_t *row = &fb[y * W];
    for (int x = x0; x <= x1; x++) {
      uint16_t c = row[x];
      uint32_t rb = (c & 0xF81F) * invA + tintRB;
      uint32_t g  = (c & 0x07E0) * invA + tintG;
      row[x] = (uint16_t)(((rb >> 8) & 0xF81F) | ((g >> 8) & 0x07E0));
    }
  }
}

// 2. 半透明毛玻璃圆形底座
static inline void drawTranslucentCircle(int cx, int cy, int r, uint16_t tintColor = 0x0000, uint8_t alpha = 140) {
  uint16_t *fb = gfx->getFramebuffer();
  if (!fb) return;
  const int W = LCD_WIDTH;
  const int H = LCD_HEIGHT;
  int invA = 256 - alpha;
  uint32_t tintRB = (tintColor & 0xF81F) * alpha;
  uint32_t tintG  = (tintColor & 0x07E0) * alpha;

  int y0 = max(0, cy - r);
  int y1 = min(H - 1, cy + r);
  for (int y = y0; y <= y1; y++) {
    int dy = y - cy;
    int maxDx = (int)sqrtf((float)(r * r - dy * dy));
    int x0 = max(0, cx - maxDx);
    int x1 = min(W - 1, cx + maxDx);
    uint16_t *row = &fb[y * W];
    for (int x = x0; x <= x1; x++) {
      uint16_t c = row[x];
      uint32_t rb = (c & 0xF81F) * invA + tintRB;
      uint32_t g  = (c & 0x07E0) * invA + tintG;
      row[x] = (uint16_t)(((rb >> 8) & 0xF81F) | ((g >> 8) & 0x07E0));
    }
  }
}

// =========================================================================
// 现代 5x7 矢量抗锯齿字模库 (完全告别锯齿方块点阵)
// 支持 0-9, A-Z, :, %, -, +, ., 空格
// =========================================================================

static const uint8_t aaGlyphDigits[10][5] = {
  {0x3E, 0x51, 0x49, 0x45, 0x3E}, // 0
  {0x00, 0x42, 0x7F, 0x40, 0x00}, // 1
  {0x42, 0x61, 0x51, 0x49, 0x46}, // 2
  {0x21, 0x41, 0x45, 0x4B, 0x31}, // 3
  {0x18, 0x14, 0x12, 0x7F, 0x10}, // 4
  {0x27, 0x45, 0x45, 0x45, 0x39}, // 5
  {0x3C, 0x4A, 0x49, 0x49, 0x30}, // 6
  {0x01, 0x71, 0x09, 0x05, 0x03}, // 7
  {0x36, 0x49, 0x49, 0x49, 0x36}, // 8
  {0x06, 0x49, 0x49, 0x29, 0x1E}  // 9
};

static const uint8_t aaGlyphLetters[26][5] = {
  {0x7C, 0x12, 0x11, 0x12, 0x7C}, // A
  {0x7F, 0x49, 0x49, 0x49, 0x36}, // B
  {0x3E, 0x41, 0x41, 0x41, 0x22}, // C
  {0x7F, 0x41, 0x41, 0x22, 0x1C}, // D
  {0x7F, 0x49, 0x49, 0x49, 0x41}, // E
  {0x7F, 0x09, 0x09, 0x09, 0x01}, // F
  {0x3E, 0x41, 0x49, 0x49, 0x7A}, // G
  {0x7F, 0x08, 0x08, 0x08, 0x7F}, // H
  {0x00, 0x41, 0x7F, 0x41, 0x00}, // I
  {0x20, 0x40, 0x41, 0x3F, 0x01}, // J
  {0x7F, 0x08, 0x14, 0x22, 0x41}, // K
  {0x7F, 0x40, 0x40, 0x40, 0x40}, // L
  {0x7F, 0x02, 0x0C, 0x02, 0x7F}, // M
  {0x7F, 0x04, 0x08, 0x10, 0x7F}, // N
  {0x3E, 0x41, 0x41, 0x41, 0x3E}, // O
  {0x7F, 0x09, 0x09, 0x09, 0x06}, // P
  {0x3E, 0x41, 0x51, 0x21, 0x5E}, // Q
  {0x7F, 0x09, 0x19, 0x29, 0x46}, // R
  {0x46, 0x49, 0x49, 0x49, 0x31}, // S
  {0x01, 0x01, 0x7F, 0x01, 0x01}, // T
  {0x3F, 0x40, 0x40, 0x40, 0x3F}, // U
  {0x1F, 0x20, 0x40, 0x20, 0x1F}, // V
  {0x7F, 0x20, 0x18, 0x20, 0x7F}, // W
  {0x63, 0x14, 0x08, 0x14, 0x63}, // X
  {0x07, 0x08, 0x70, 0x08, 0x07}, // Y
  {0x61, 0x51, 0x49, 0x45, 0x43}  // Z
};

static const uint8_t aaGlyphColon[5]   = {0x00, 0x36, 0x36, 0x00, 0x00}; // :
static const uint8_t aaGlyphPercent[5] = {0x63, 0x33, 0x18, 0x0C, 0x66}; // %
static const uint8_t aaGlyphMinus[5]   = {0x08, 0x08, 0x08, 0x08, 0x08}; // -
static const uint8_t aaGlyphPlus[5]    = {0x08, 0x08, 0x3E, 0x08, 0x08}; // +
static const uint8_t aaGlyphDot[5]     = {0x00, 0x60, 0x60, 0x00, 0x00}; // .
static const uint8_t aaGlyphDegree[5]  = {0x00, 0x06, 0x09, 0x06, 0x00}; // * or °

static inline const uint8_t* getAaGlyph(char c) {
  if (c >= '0' && c <= '9') return aaGlyphDigits[c - '0'];
  if (c >= 'A' && c <= 'Z') return aaGlyphLetters[c - 'A'];
  if (c >= 'a' && c <= 'z') return aaGlyphLetters[c - 'a'];
  if (c == ':') return aaGlyphColon;
  if (c == '%') return aaGlyphPercent;
  if (c == '-') return aaGlyphMinus;
  if (c == '+') return aaGlyphPlus;
  if (c == '.') return aaGlyphDot;
  if (c == '*' || c == '^') return aaGlyphDegree;
  return nullptr;
}

// 绘制单个抗锯齿矢量字符 (以 cx, cy 为中心)
static inline void drawAaChar(float cx, float cy, const uint8_t bmp[5], float scale, float dotR, uint16_t color) {
  if (!bmp) return;
  for (int col = 0; col < 5; col++) {
    uint8_t b = bmp[col];
    for (int row = 0; row < 7; row++) {
      if ((b >> row) & 1) {
        float px = cx + (col - 2.0f) * scale;
        float py = cy + (row - 3.0f) * scale;
        aaDisc(px, py, dotR, color);
      }
    }
  }
}

// 绘制抗锯齿字符串 (支持居中或左对齐，完全告别锯齿方块点阵)
static inline void drawAaString(float cx, float cy, const char *str, float scale, float dotR, float spacing, uint16_t color, bool center = true) {
  if (!str) return;
  int len = strlen(str);
  if (len == 0) return;
  float totalW = (len - 1) * spacing;
  float startX = center ? (cx - totalW / 2.0f) : cx;

  for (int i = 0; i < len; i++) {
    char ch = str[i];
    if (ch == ' ') continue;
    const uint8_t *bmp = getAaGlyph(ch);
    if (bmp) {
      drawAaChar(startX + i * spacing, cy, bmp, scale, dotR, color);
    }
  }
}

// 3. 经典 Rockstar (R星) 风格五角星绘制函数
// cx, cy: 中心坐标, outerR: 外顶点半径, innerR: 内凹点半径
static inline void drawRockstarStar(int cx, int cy, float outerR, float innerR, uint16_t fillColor, uint16_t outlineColor) {
  float ptsX[10];
  float ptsY[10];
  for (int i = 0; i < 10; i++) {
    float angle = (-90.0f + i * 36.0f) * (float)M_PI / 180.0f;
    float r = (i % 2 == 0) ? outerR : innerR;
    ptsX[i] = cx + r * cosf(angle);
    ptsY[i] = cy + r * sinf(angle);
  }

  // 扇形三角形拼合填充五角星实心内部
  for (int i = 0; i < 10; i++) {
    int next = (i + 1) % 10;
    gfx->fillTriangle((int)lroundf(ptsX[i]), (int)lroundf(ptsY[i]),
                      (int)lroundf(ptsX[next]), (int)lroundf(ptsY[next]),
                      cx, cy, fillColor);
  }

  // 轮廓线条平滑描边
  for (int i = 0; i < 10; i++) {
    int next = (i + 1) % 10;
    gfx->drawLine((int)lroundf(ptsX[i]), (int)lroundf(ptsY[i]),
                  (int)lroundf(ptsX[next]), (int)lroundf(ptsY[next]), outlineColor);
  }
  // 5 个外顶点抗锯齿平滑小圆点加固
  for (int i = 0; i < 10; i += 2) {
    aaDisc(ptsX[i], ptsY[i], 1.2f, outlineColor);
  }
}

// 4. 动态主题地图背景生成 (根据用户选择的地图主题 themeIdx 和 nightOn，动态呈现对应风格的精美地图底图)
static inline void drawThemedMapBackground() {
  uint16_t *fb = gfx->getFramebuffer();
  if (!fb) return;
  const int W = LCD_WIDTH;  // 466
  const int H = LCD_HEIGHT; // 466

  int tid = constrain(themeIdx, 0, THEME_N - 1);
  const MapTheme &th = (nightOn ? THEMES_NIGHT : THEMES)[tid];

  uint16_t c_block = th.block;
  uint16_t c_road  = th.road;
  uint16_t c_park  = th.park;
  uint16_t c_water = th.water;
  uint16_t c_route = th.route;
  uint16_t c_node  = th.route2 ? th.route2 : th.route;
  uint16_t c_blip  = th.blip ? th.blip : C_WHITE;

  // 1. 基础地面底色填充
  gfx->fillScreen(c_block);

  // 特殊主题附加几何元素
  if (tid == ST_DRAGON) {
    // 龙珠雷达：绿色同心网格圆与十字基准线
    uint16_t gridCol = 0x04A0;
    gfx->drawCircle(CX, CX, 72, gridCol);
    gfx->drawCircle(CX, CX, 142, gridCol);
    gfx->drawCircle(CX, CX, 206, gridCol);
    gfx->drawFastHLine(0, CX, W, gridCol);
    gfx->drawFastVLine(CX, 0, H, gridCol);
    aaDisc((float)(CX + 62), (float)(CX - 56), 6.5f, 0xFFE0);
    aaDisc((float)(CX - 78), (float)(CX + 48), 6.5f, 0xFFE0);
  } else if (tid == ST_BLUEPRINT) {
    // 蓝图：工程图纸微细白色方格
    for (int x = 22; x < W; x += 26) gfx->drawFastVLine(x, 0, H, 0x1A94);
    for (int y = 22; y < H; y += 26) gfx->drawFastHLine(0, y, W, 0x1A94);
  } else if (tid == ST_RADAR) {
    // 雷达模式：极坐标同心刻度圆
    uint16_t rCol = 0x0B80;
    gfx->drawCircle(CX, CX, 75, rCol);
    gfx->drawCircle(CX, CX, 150, rCol);
    gfx->drawCircle(CX, CX, 210, rCol);
  }

  // 2. 左侧蜿蜒水面 / 河流 (仅在主题具有独立水体色且非零时绘制)
  if (c_water != 0 && c_water != c_block) {
    for (int y = 0; y < H; y++) {
      float ny = (float)y / 466.0f;
      int wx = (int)(78 + 32.0f * sinf(ny * 3.14159f * 1.5f));
      int x0 = max(0, wx - 22);
      int x1 = min(W - 1, wx + 22);
      for (int x = x0; x <= x1; x++) {
        fb[y * W + x] = c_water;
      }
    }
  }

  // 3. 街区公园绿地 (仅在主题具有独立绿地色且非零时绘制)
  if (c_park != 0 && c_park != c_block && c_park != c_water) {
    gfx->fillRect(140, 70, 52, 44, c_park);
    gfx->fillRect(276, 268, 64, 52, c_park);
    gfx->fillRect(160, 360, 48, 38, c_park);
  }

  // 4. 纵横深色街道网格 (线宽 4px)
  if (c_road != 0 && c_road != c_block) {
    for (int x = 42; x < W; x += 48) {
      gfx->fillRect(x - 2, 0, 4, H, c_road);
    }
    for (int y = 42; y < H; y += 48) {
      gfx->fillRect(0, y - 2, W, 4, c_road);
    }
  }

  // 5. 导航行车历史轨迹 (深灰色线 / 主题次要路线)
  uint16_t c_trail = th.done ? th.done : 0x4208;
  gfx->fillRect(CX - 1, 280, 3, 140, c_trail);

  // 6. 导航路线 (使用当前主题指定的 route 颜色与 node 颜色，线宽 6px，路口直角转弯)
  if (c_route != 0) {
    // 纵向段：从 Y=280 向上延伸至 Y=186
    gfx->fillRect(CX - 3, 186, 6, 94, c_route);
    // 横向段：从 X=233 向右延伸至 X=378
    gfx->fillRect(CX - 3, 183, 148, 6, c_route);
    // 转弯路口外圈小圆环节点
    aaDisc((float)CX, 186.0f, 6.0f, c_node);
    aaDisc((float)CX, 186.0f, 3.0f, c_route);
  }

  // 7. 自车定位航向箭头 (Blip：采用主题专属车标色与黑色外框，朝向路线前方)
  const int blipX = CX;
  const int blipY = 276;
  gfx->fillTriangle(blipX, blipY - 14, blipX - 8, blipY + 6, blipX + 8, blipY + 6, C_BLACK);
  gfx->fillTriangle(blipX, blipY - 11, blipX - 6, blipY + 4, blipX + 6, blipY + 4, c_blip);
  gfx->fillTriangle(blipX, blipY - 1, blipX - 4, blipY + 4, blipX + 4, blipY + 4, C_BLACK);

  // 8. 半透明暗化与暗角融合 (针对不同明暗底色自适应，外圈平滑暗角)
  uint32_t r_b = (c_block >> 11) & 0x1F;
  uint32_t g_b = (c_block >> 5) & 0x3F;
  uint32_t b_b = c_block & 0x1F;
  uint32_t lum = r_b * 8 + g_b * 4 + b_b * 8; // 0 ~ 500
  uint32_t baseRatio = (lum > 180) ? 118 : 205; // 亮色底暗化至 46%，深色底保留 80%

  for (int y = 0; y < H; y++) {
    int dy = y - H / 2;
    uint16_t *row = &fb[y * W];
    for (int x = 0; x < W; x++) {
      int dx = x - W / 2;
      int r2 = dx * dx + dy * dy;

      uint16_t c = row[x];
      uint32_t ratio = baseRatio;

      // 圆屏边缘 175px 外渐变黑色暗角晕轮 (Vignette)
      if (r2 > 175 * 175) {
        int dist = (int)sqrtf((float)r2) - 175;
        int vignette = max(0, (int)baseRatio - dist * 3);
        ratio = (uint32_t)vignette;
      }

      // 安全分离 RGB565 三通道独立缩放，彻底杜绝位移重叠导致的纯蓝色偏！
      uint32_t r = ((c >> 11) & 0x1F) * ratio >> 8;
      uint32_t g = ((c >> 5)  & 0x3F) * ratio >> 8;
      uint32_t b = (c & 0x1F)         * ratio >> 8;
      row[x] = (uint16_t)((r << 11) | (g << 5) | b);
    }
  }
}

// 兼容别名
static inline void drawViceCityBackground() {
  drawThemedMapBackground();
}

