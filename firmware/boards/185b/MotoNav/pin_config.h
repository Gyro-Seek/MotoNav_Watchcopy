#pragma once

// 微雪 ESP32-S3-Touch-LCD-1.85B Rev1.1，引脚与普通 1.85/1.75 不通用。
#define LCD_SDIO0 46
#define LCD_SDIO1 45
#define LCD_SDIO2 42
#define LCD_SDIO3 41
#define LCD_SCLK 40
#define LCD_CS 21
#define LCD_RESET 3
#define LCD_BL 5
#define LCD_TE 18
#define PANEL_WIDTH 360
#define PANEL_HEIGHT 360
// 逻辑画布保留完整原布局，统一缩放到物理面板，不裁剪 HUD 或地图。
#define LCD_WIDTH 466
#define LCD_HEIGHT 466
#define LCD_INIT_VARIANT 0   // 0=读面板 ID 自动选择；1/2=指定官方初始化序列

#define IIC_SDA 11
#define IIC_SCL 10
#define TP_INT 4
#define TP_RESET 1
#define BOARD_TOUCH_FLIP_X 0
#define BOARD_TOUCH_FLIP_Y 0

#define I2S_MCK_IO 2
#define I2S_BCK_IO 48
#define I2S_DI_IO 39
#define I2S_WS_IO 38
#define I2S_DO_IO 47
#define PA 9
const int SDMMC_CLK=15;
const int SDMMC_CMD=14;
const int SDMMC_DATA=16;
const int SDMMC_CS=-1;
