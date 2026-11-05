#pragma once
#include <Arduino.h>

#define MAX_DEST_ITEMS 8

struct DestItem {
  uint8_t type;  // 0 = 常用收藏 (Star), 1 = 导航历史 (Pin)
  char name[32]; // 名称 (如 "Home", "Work", "Mall")
  char addr[32]; // 简短地址
  bool valid;
};

extern DestItem destItems[MAX_DEST_ITEMS];
extern int destItemCount;
extern bool destSheetOpen;
extern int destScrollOffset;

inline void destItemsClear() {
  destItemCount = 0;
  for (int i = 0; i < MAX_DEST_ITEMS; i++) {
    destItems[i].valid = false;
    destItems[i].name[0] = '\0';
    destItems[i].addr[0] = '\0';
  }
}

inline void destItemAdd(uint8_t type, const char* name, const char* addr) {
  if (destItemCount >= MAX_DEST_ITEMS) return;
  int idx = destItemCount++;
  destItems[idx].type = type;
  strncpy(destItems[idx].name, name ? name : "", sizeof(destItems[idx].name) - 1);
  destItems[idx].name[sizeof(destItems[idx].name) - 1] = '\0';
  strncpy(destItems[idx].addr, addr ? addr : "", sizeof(destItems[idx].addr) - 1);
  destItems[idx].addr[sizeof(destItems[idx].addr) - 1] = '\0';
  destItems[idx].valid = true;
}

// 默认填充两项常用地点 (防止未连接手机时界面空白)
inline void destInitDefaults() {
  if (destItemCount > 0) return;
  destItemAdd(0, "HOME", "Favorite Place");
  destItemAdd(0, "WORK", "Favorite Place");
}

