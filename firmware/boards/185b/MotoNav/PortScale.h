#pragma once
#include <stdint.h>

/** RGB565 画布完整缩放，物理坐标与触摸使用同一个像素中心映射。 */
class PortScale {
public:
  static constexpr int LOGICAL=466, PHYSICAL=360;
  int32_t axis[PHYSICAL];
  PortScale() {
    for(int p=0;p<PHYSICAL;p++)axis[p]=(int32_t)(((int64_t)(2*p+1)*LOGICAL*32768)/PHYSICAL-32768);
  }
  static int touch(int raw) {
    if(raw<0)raw=0;if(raw>=PHYSICAL)raw=PHYSICAL-1;
    return ((2*raw+1)*LOGICAL)/(2*PHYSICAL);
  }
  static uint32_t spread(uint16_t c) {return ((uint32_t)c|((uint32_t)c<<16))&0x07E0F81Fu;}
  uint16_t pixel(const uint16_t* source,int x,int y,int rotation,bool freeRotation,int32_t cosine,int32_t sine) const {
    int32_t fx=axis[x],fy=axis[y];constexpr int32_t center=(LOGICAL-1)*32768;
    if(freeRotation) {
      int32_t dx=fx-center,dy=fy-center;
      fx=(int32_t)(((int64_t)dx*cosine+(int64_t)dy*sine)>>16)+center;
      fy=(int32_t)((-(int64_t)dx*sine+(int64_t)dy*cosine)>>16)+center;
    }else if(rotation==1){int32_t a=fx;fx=fy;fy=2*center-a;}
    else if(rotation==2){fx=2*center-fx;fy=2*center-fy;}
    else if(rotation==3){int32_t a=fx;fx=2*center-fy;fy=a;}
    int sx=fx>>16,sy=fy>>16;
    if((unsigned)sx>=LOGICAL-1 || (unsigned)sy>=LOGICAL-1) {
      int nx=(fx+32768)>>16,ny=(fy+32768)>>16;
      return (unsigned)nx<LOGICAL && (unsigned)ny<LOGICAL?source[ny*LOGICAL+nx]:0;
    }
    const uint16_t* a=source+sy*LOGICAL+sx;
    uint32_t ax=(fx>>11)&31,ay=(fy>>11)&31;
    uint32_t top=((spread(a[0])*(32-ax)+spread(a[1])*ax)>>5)&0x07E0F81Fu;
    uint32_t bottom=((spread(a[LOGICAL])*(32-ax)+spread(a[LOGICAL+1])*ax)>>5)&0x07E0F81Fu;
    uint32_t result=((top*(32-ay)+bottom*ay)>>5)&0x07E0F81Fu;
    return (uint16_t)(result|(result>>16));
  }
};
