设备为 微雪esp32-s3 1.75
使用SOP:
1. 打开workbuddy，注册账号
2. 将该仓库地址直接给workbuddy，告知它3件事：
   2.1. 安装esp32依赖
   2.2. 设备为微雪esp32-s3 1.75，我用的电脑是Mac/Windows，生成一键烧录
   2.3. 我的手机是iPhone，生成ipa（安卓手机的话，让workbuddy把代码拉下来，并点击一键打包.bat）
3. 前往[高德开放平台](https://console.amap.com/)登录账号
4. 连接微雪esp32，打开一键烧录，出现开机画面就成功了。不成功找workbuddy。
***5. ios:下载Sideloadly，用Sideloadly安装ipa，注意提前安装iTunes和iCloud。开启开发者模式和信任作者；Andorid：手机直接安装apk
6. ios:打开软件，使用软件上显示的bundle id，在高德开放平台生成key，并把key填入软件中。因为ios需要每7天签名一次，所以记好bundle id
   Android: output/Application-info中有SHA1和Package Name，在高德开放平台生成key，并把key填入软件中。
7. 剩下的你就玩吧，自己摸索。一定要做好备份！！！

***对于第5步的更新：由于ios每7天要打开电脑重新签名一次，过于麻烦，以下是曲线救国的方法：
1. 电脑安装iloader，用iloader为iPhone安装Sidestore
2. iPhone下载安装LocalDevVPN
3. 打开Sidestore，开启LocalDevVPN，Sidestore登录apple id
4. 如果登陆不了，Sidestore做如下设置：
   <img width="924" height="624" alt="1630139841" src="https://github.com/user-attachments/assets/f3468a40-f4eb-4651-b8da-3fcf21084e14" />
<img width="1072" height="708" alt="857736394" src="https://github.com/user-attachments/assets/e351ccb7-354a-4b27-912d-cb526674b389" />
5. 使用iloader安装ipa
6. 将ipa拖入iCloud
7. 在Sidestore My Apps中添加该ipa
8. 设置苹果的自动化，定义每周的某几天的几点（这个点最好是你一定会连着wifi的点），自动开启LocalDevVPN，Sidestore refresh all apps，然后关闭VPN

-----------------------------------------------------------------------------------------------------------------------
以下为原作者内容，感谢原作者开源，郑重感谢！！！跪拜不止！！！
# MotoNav for M5Stack Stopwatch

本项目是专为 **M5Stack Stopwatch**（1.75 英寸 466×466 AMOLED 圆屏设备）深度适配与独立维护的摩托车/自行车骑行导航仪系统。

> **维护说明**：鉴于上游原项目已停止更新，本仓库已正式改造成**专门针对 M5Stopwatch 硬件**独立演进的专版，不再向上游提交代码。  
> **硬件兼容声明**：本仓库**仅保证对 M5Stack M5Stopwatch 的兼容与深度优化**；针对原 MotoNav 项目所支持的微雪（Waveshare）1.75 / 1.85B 及其他圆屏设备，本分支未做兼容性维护与测试，其他设备用户请按需参考或自行适配。

---

## 快速上手与固件获取

### 1. 固件烧录（推荐 M5Burner）
- **推荐方式**：本项目固件已发布至 **[M5Burner](https://burner.m5stack.com)**，在 M5Burner 中搜索 `MotoNav` 或 `Stopwatch` 即可一键下载并烧录到 M5Stopwatch。
- **开发者源码编译**：本项目固件使用 PlatformIO 开发，环境为 ESP32-S3：
  ```bash
  pio run -e stopwatch -t upload
  ```

### 2. 手机端配套 App 说明

烧录固件后，Stopwatch 需要配合手机端 App 协同工作（手机负责高德导航算路、音乐媒体信息抓取及 BLE 蓝牙传输）。

#### 安卓端（Android）—— 推荐使用，持续维护中
仓库提供了完整全自动构建体系，无需安装庞大的 Android Studio，Windows 用户仅需双击脚本即可全自动打包专属于您自己的 APK：

1. **一键打包**：直接双击根目录的 `一键打包.bat`（或在 PowerShell 中执行 `.\Build-Personal.ps1`）；
2. **自动生成**：脚本全自动下载所需编译环境，并为您自动生成专属随机包名与专属数字证书，编译产物位于 `output/MotoNav-standard-release.apk`；
3. **申请高德 Key**：按照打包输出的 `output/Application-info.txt` 中显示的**包名**和**SHA1 安全码**，前往[高德开放平台](https://console.amap.com/)免费申请一个 Android 平台 Key，在手机 App 启动后的“地图 Key”设置页填入即可正常使用导航；
4. **升级备份**：后续升级前，请妥善备份生成的 `android/standard/personal.properties` 与 `android/standard/keystore/`，以便覆盖安装时保持包名和签名一致。

#### 苹果端（iOS）—— 诚寻社区贡献者！
- **现状说明**：仓库维护者**没有 iOS 开发经验，亦缺乏 iOS 真机调试资源**，因此当前 iOS 端 App 版本相对落后，尚未完成针对 Stopwatch 的专属适配。
- **后续计划**：维护者后续可能会尝试借助 Coding Agent 同步 iOS 端的通用功能代码，但由于无法进行实机编译与路测，**无法保证 iOS 端的实际运行效果**。
- **开源共建**：非常欢迎熟悉 iOS / Swift 开发、手头有设备的网友与开发者参与进来！如果您有能力改造或完善 iOS 端 App，**极其欢迎向本仓库提交 Pull Request（PR）**，帮助更多骑行爱好者完善苹果生态体验。

---

## M5Stopwatch 专属特性与交互操作

针对 M5Stopwatch 的 466×466 AMOLED 圆屏、实体双按键及内置高精度姿态传感器，本版本深度定制了现代极简毛玻璃与抗锯齿矢量 UI：

### 1. 待机主页（Waiting Dashboard）
- **罪恶都市微光地图背景**：程序化渲染深黑霓虹道路网络与渐晕街区底图，现代感十足；
- **大号平滑抗锯齿矢量时钟**：告别锯齿方块点阵，基于亚像素平滑引擎渲染无衬线数字时钟与日期（`NOV 03 TUE`）；
- **Rockstar 风格五角星与目的地抽屉**：
  - 点击屏幕下方的 R星五角星按钮（★），呼出半透明毛玻璃目的地抽屉；
  - 自动展示手机端同步过来的**常用收藏地点**与**历史导航目的地**，点击卡片即可直接向手机发起路线规划并导航。

### 2. 圆屏专属设置（Settings Page）
主界面向左滑动直接进入圆屏专属设置页，无需掏出手机即可即时调整设备参数：
- **屏幕亮度**：轻触在 `25%`、`50%`、`75%`、`100%` 档位循环切换，即时生效并保存到 NVS；
- **地图风格**：轻触在 `VICE`（罪恶都市）、`DARK`（标准暗黑）、`CLEAN`（极简白线）、`RADAR`（龙珠雷达）循环切换，并联动手机端；
- **屏幕旋转**：轻触在 `0°`、`90°`、`180°`、`270°` 循环旋转屏幕，完美适应各种支架安装方向；
- **待机休眠**：轻触切换 `3 MIN`、`5 MIN`、`10 MIN` 与 `NEVER`（常亮）。

### 3. 音乐播放器界面（Music Player）
- **滑动封面切歌**：在专辑封面区域向左滑切换下一曲、向右滑切换上一曲，伴随物理飞出切歌动效与黑胶底托展示；
- **轻触封面播放/暂停**：轻触封面中心精准切换播放/暂停（内置 140ms 物理触控抗抖动滤波，绝不误触）；
- **快速双击封面点赞（Like）**：连续快速双击封面中心或点击右下角 Like 按钮，切换喜欢状态。点赞底座采用纯黑磨砂玻璃质感，点亮为红宝石心形图标，背景纯粹干净；
- **iPhone 风格中央毛玻璃音量 HUD**：
  - 手指在屏幕 9 点钟位置触摸上下滑动即可调节音量；
  - 屏幕正中央浮现精致小巧的毛玻璃半透明卡片，显示纯白矢量喇叭、动态声波、iOS 胶囊滑动条及抗锯齿平滑数字，静音时呈现利落的纯白斜杠，停止操作 1.5 秒后自动淡出。

### 4. 实体双按键全局操作
- **长按左键（KEY A / GPIO 2，≥ 500ms）**：全局上一曲（带触感震动反馈，任意界面均可触发）；
- **长按右键（KEY B / GPIO 1，≥ 500ms）**：全局下一曲（带触感震动反馈，任意界面均可触发）；
- **短按左键（KEY A）**：主页下向左滑入音乐播放页；其他页面快速返回主界面；
- **短按右键（KEY B）**：主页下向右滑入圆屏设置页；其他页面快速返回主界面；
- **双键同时长按（KEY A + B，≥ 800ms）**：快速切换【主导航界面】与【倾角 / G值仪表盘界面】；在伴侣模式下快速退出。

### 5. 车身姿态与 G 值仪表（Lean & G-Meter）
- **车规级奢华柔和配色**：安全区间采用柔和薄荷青绿（`0x4ECB`）、预警区间采用落日暖金柔橙（`0xFB65`）、极限区间采用柔和珊瑚红（`0xFA68`）；
- **全面去像素化**：刻度数字、G 值读数、MAX L/R 胶囊与实时角度全部重塑为平滑抗锯齿矢量字体，告别粗糙点阵；
- 借助板载 **BMI270 6轴姿态传感器**，高刷新率实时显示压弯倾角及加减速/转向 G 值矢量轨迹球，支持长按零点校准与双击重置极值。

### 6. 专属伴侣模式（Companion Mode）
- 提供丰富生动的互动表情与情绪反馈，支持触控抚摸反馈与马达震动；
- 断连 2 分钟自动进入伴侣表情，5 分钟无互动通过 M5PM1 彻底关机断电；
- 导航途中无操作 1 分钟自动切回导航，确保骑行安全。

---

## 交通安全与免责声明

1. **安全第一**：行驶过程中请勿长时间凝视或手动操作圆屏及手机，路线设置与记录查看请务必在车辆安全停稳后进行；
2. **现场为准**：任何程序展示的道路、转弯提示及天气信息均不能代替现场实际交通标志与交警指挥，请严格遵守交通法规；
3. **风险自担**：本程序按开源非商业原则提供，使用者已知悉并自愿承担骑行及使用过程中可能存在的一切软硬件及交通安全风险。

---

## 社区贡献与特别鸣谢

### 社区 PR 贡献
非常感谢社区开发者向本专版仓库提交的 Pull Request：

- **[vanddccd](https://github.com/vanddccd)**（PR [#1](https://github.com/nongxl/MotoNav_stopwatch/pull/1)）：
  - **StopWatch 硬件级真关机支持**：实现无 BLE 连接持续满 2 分钟时自动调用 M5PM1 电源芯片 `shutdown()` 进行彻底切断电源的硬件级真关机，同时兼顾 USB 供电接入与伴侣模式的豁免判定，大幅改善了离线放置时的待机功耗。

### 实车路测与反馈特别鸣谢
- **清野**：
  - 热情参与实车道路骑行路测，针对导航转弯旋转响应灵敏度、双击地图缩放手势体验、重力感应随动旋转与视觉参考等核心功能提出宝贵的实测反馈与修改意见，极大助力了 Stopwatch 专版的实用度与骑行交互品质打磨！

---

## 依赖与开源协议说明

### 核心项目与第三方依赖致谢
- **[zyn950929/MotoNav](https://github.com/zyn950929/MotoNav)**：奠定了 MotoNav 优秀的骑行导航核心体系；
- **[Trentct/m5stack-stopwatch-avatar](https://github.com/Trentct/m5stack-stopwatch-avatar)**：提供了 M5Stopwatch 上出色的“KK” 60fps 动态程序化表情角色引擎，本项目的伴侣模式（Companion Mode）基于该项目移植适配；
- **[M5Stack](https://m5stack.com/)**：提供了 M5Stopwatch 硬件及相关驱动支持。

### 开源许可证合规声明
1. **原创代码与导航体系**：本仓库中项目权利人有权授权的原创自研逻辑、脚本及文档遵循根目录 [LICENSE.md](LICENSE.md)，仅供个人非商业学习交流与骑行体验，严禁用于任何商业兜售及代刷获利行为；
2. **伴侣模式（Avatar 角色引擎）**：固件中的 `AvatarEngine.h` 与 `AvatarEngine.cpp` 源自 [Trentct/m5stack-stopwatch-avatar](https://github.com/Trentct/m5stack-stopwatch-avatar)，遵循 **[GNU Affero General Public License v3.0 (AGPL-3.0-or-later)](licenses/LICENSE-AGPL-3.0.txt)** 开源许可。根据 AGPL-3.0 要求，本仓库保持完整公开全部源代码，任何包含该组件的代码衍生与分发均保留原有版权声明与许可文本；
3. **第三方库与工具**：本项目所引用的第三方库（如 Arduino GFX、SensorLib 等）分别遵循其原作者的开源许可证协议（详见 `licenses/` 目录）。
