import SwiftUI
import CoreLocation
import AVFoundation
import Combine
import ObjectiveC
import UIKit

/// 版本：跟随 App 版本（见 Config.swift）
///
/// 主界面（苹果地图式层级）：全屏地图 + 右上悬浮控件 + 底部搜索面板；
/// 原来 dock 里的 4 个页面全部收进搜索条右侧的齿轮设置中心。
/// （保留罪恶都市风深色配色）
struct ContentView: View {
    @ObservedObject var ble = BleLink.shared
    @ObservedObject var navi = NaviBridge.shared
    @ObservedObject var independent = WebMotorSession.shared
    @ObservedObject var search = SearchService.shared
    @ObservedObject var settings = Settings.shared
    @ObservedObject var weather = Weather.shared
    @ObservedObject var map = MapFeeder.shared
    @ObservedObject var history = History.shared
    @ObservedObject var favorites = Favorites.shared
    @State private var showWebMotor = false
    @State private var independentMode: IndependentMode = .motorcycle
    @State private var showRides = false
    @State private var showSettings = false            // 齿轮：所有设置的统一入口
    @AppStorage("voice_rate") private var voiceRate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @AppStorage("voice_pitch") private var voicePitch = 1.0
    @AppStorage("voice_id") private var voiceID = ""
    @AppStorage("map_appearance") private var mapAppearance = 0   // 0 自动 / 1 标准 / 2 夜间 / 3 卫星

    @State private var query = ""
    @State private var dest: SearchService.Place?
    @State private var showNavi = false
    @State private var showDebug = false
    @State private var showKeys = false                 // iOS v0.7 填写地图 Key 页面
    @State private var showPlate = false                // 车牌 / 限行设置页
    private static var keyPrompted = false              // 这次打开 App 已经提醒过填 key 了
    @State private var shareBusy = false
    @State private var shareStatus = ""
    @State private var autoStartNavi = false        // 分享进来的地点：路线算好就自动开始导航
    @State private var autoPickResult = false       // 只有地名时：搜索结果回来自动选第一条
    @State private var cruiseNote = ""
    @State private var addingVia = false               // 正在搜途经点
    @State private var viaManager = false              // 途经点管理面板（增删 / 拖动排序）
    @State private var viaEditMode = EditMode.active   // 途经点列表常显拖拽手柄
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastHandledShare = ""        // 去重：onOpenURL 和前台自动消费可能同时到
    @State private var sheetExpanded = false         // 首页底部搜索抽屉：上滑展开更多入口
    @State private var homeStage: HomeStage = .idle  // 首页流程：搜索 → 地点 → 路线
    @State private var homeFocus: CLLocationCoordinate2D? = nil   // 选中的地点（地图相机目标）
    @State private var focusToken = 0                  // 每选一次地点 +1，触发地图定位
    @State private var recenterToken = 0               // 右下角「回到定位」按钮
    @State private var overviewToken = 0               // 路线算好后自动缩放到全路线
    @State private var pendingSearchSubmit = false     // 按了「搜索」但结果还没回来
    @State private var suppressAutoSearch = false      // 程序化改 query 时不触发实时检索
    @State private var searchWork: DispatchWorkItem? = nil
    @State private var keyboardHeight: CGFloat = 0     // 键盘高度：把搜索面板顶到键盘上方

    // 设置中心自己的弹层：和首页弹层分属不同视图层级，避免 sheet 套 sheet 被系统吞掉
    @State private var hubPlate = false
    @State private var hubKeys = false
    @State private var hubRides = false
    @State private var hubWeb = false
    @State private var hubMode: IndependentMode = .motorcycle

    static let bg = Color(red: 0.055, green: 0.04, blue: 0.08)
    static let card = Color(red: 0.10, green: 0.08, blue: 0.14)
    static let stroke = Color(red: 0.17, green: 0.14, blue: 0.22)
    static let pink = Color(red: 1.0, green: 0.31, blue: 0.71)
    static let cyan = Color(red: 0.26, green: 0.88, blue: 0.94)
    static let sub = Color(red: 0.62, green: 0.58, blue: 0.67)

    var body: some View {
        VStack(spacing: 0) {
            activeNavigationBanner
            homePage
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(ContentView.bg.ignoresSafeArea())
        .fullScreenCover(isPresented: $showWebMotor) { WebMotorView(mode: independentMode) }
        .sheet(isPresented: $showRides) { NavigationView { RideHistoryView() } }
        .fullScreenCover(isPresented: $showNavi) { NaviScreen() }
        .sheet(isPresented: $showKeys) { KeySetupView() }
        .sheet(isPresented: $showPlate) { PlateSetupView() }
        .sheet(isPresented: $showSettings) { settingsHub }
        .onAppear {                                    // iOS v0.7 打开 App 时，高德 key 没填就提醒一次
            if !ContentView.keyPrompted && settings.keysMissing {
                ContentView.keyPrompted = true
                showKeys = true
            }
            // 冷启动时通知可能比界面先到，补一次
            suppressAutoSearch = false
            flushPendingShare()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { flushPendingShare() }
        }
        // 输入即检索：350ms 防抖，SearchService 自带关键词缓存，避免每个字母都请求高德
        .onChange(of: query) { t in
            guard !suppressAutoSearch else { suppressAutoSearch = false; return }
            if homeStage != .idle { backToSearch() }
            scheduleAutoSearch(t)
        }
        // 路线算好后自动把地图缩放到能看全所有路线
        .onChange(of: navi.routeOptions.count) { n in
            guard homeStage == .routes, n > 0 else { return }
            overviewToken += 1
        }
        // 用户点了分享扩展发的本地通知：内容直接随通知带过来，不用读剪贴板
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.shareNotification)) { note in
            guard let t = note.object as? String else { return }
            deliverShare(t)
        }
        .onOpenURL { url in                            // 高德 / 苹果地图「分享到 MotoNav」：motonav://share?t=
            guard url.scheme == "motonav",
                  let t = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "t" })?.value
            else { return }
            deliverShare(t)
        }
        // 只有地名时，等搜索结果回来自动选第一条；手动按「搜索」但结果还没回来时同理
        .onReceive(search.$results) { rs in
            if autoPickResult, !rs.isEmpty {
                autoPickResult = false
                choose(rs[0], autoPlan: true)
                return
            }
            if pendingSearchSubmit, let first = rs.first {
                pendingSearchSubmit = false
                choose(first)
            }
        }
        // 分享进来的地点 / 路线：规划完成立刻开始导航，不用再手点「开始导航」
        .onChange(of: navi.routeReady) { ready in
            guard ready, autoStartNavi else { return }
            autoStartNavi = false
            navi.start(emulate: false)
            showNavi = true
        }
        // 键盘弹起：把底部搜索面板顶到键盘上沿，并显示「取消 / 点空白收起」
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            guard let f = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            withAnimation(.easeOut(duration: 0.2)) { keyboardHeight = f.height }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardHeight = 0 }
        }
    }

    private var activeNavigationBanner: some View {
        Group {
            if navi.navigating || independent.running {
                HStack {
                    VStack(alignment:.leading,spacing:3) {
                        Text("导航继续运行中").bold()
                        Text(independent.running ? independent.instruction : "\(navi.uiDir) · \(navi.uiDist) 米")
                            .font(.caption).lineLimit(1)
                    }
                    Spacer()
                    Button("回到导航") {
                        if independent.running { showWebMotor=true } else { showNavi=true }
                    }.foregroundColor(Self.pink)
                }.padding(12).background(Self.card).foregroundColor(.white)
            }
        }
    }

    // MARK: 标题
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MotoNav")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .italic()
                .foregroundStyle(LinearGradient(colors: [ContentView.pink, ContentView.cyan], startPoint: .leading, endPoint: .trailing))
            Text("圆屏导航 · \(APP_VERSION)").font(.caption).foregroundColor(ContentView.sub)
        }
        .padding(.top, 8)
    }

    // MARK: 圆屏状态
    private var statusCard: some View {
        CardView {
            HStack {
                Circle().fill(ble.isReady ? Color.green : Color.orange).frame(width: 10, height: 10)
                Text("圆屏").foregroundColor(.white).bold()
                Spacer()
                Button(ble.isReady ? "断开" : "连接") { ble.isReady ? ble.disconnect() : ble.connect() }
                    .foregroundColor(ContentView.cyan)
            }
            Text(ble.status).font(.footnote).foregroundColor(ContentView.sub)
            // iOS v0.6 圆屏画小地图时每 2 秒回报一次帧率
            if ble.isReady, Date().timeIntervalSince(ble.statAt) < 10, !ble.screenFps.isEmpty {
                Text("小地图 \(ble.screenFps) 帧/秒").font(.footnote).foregroundColor(ContentView.sub)
            }
            if navi.navigating {
                Text("导航中：\(navi.uiDir) \(navi.uiDist) 米 · \(navi.uiSpeed) km/h").font(.footnote).foregroundColor(ContentView.cyan)
                if navi.uiRemainM > 0 {
                    Text("剩余 \(NaviBridge.distText(navi.uiRemainM)) · 约 \(NaviBridge.durText(navi.uiRemainS)) · \(ContentView.etaText(navi.uiRemainS)) 到达")
                        .font(.footnote).foregroundColor(.white)
                }
                Button("回到导航画面") { showNavi = true }.foregroundColor(ContentView.pink)
            }
            Text("小地图：\(map.shortStatus) · 高德 · \(Settings.themeName(settings.theme))")
                .font(.caption).foregroundColor(ContentView.sub)
        }
    }

    // MARK: 首页搜索条（苹果地图式：底部浮层里的圆角搜索框，键盘「搜索」提交）
    private var homeSearchBar: some View {
        HStack(spacing: 8) {
            if addingVia {
                Button { cancelViaSearch() } label: {
                    Image(systemName: "chevron.left").font(.subheadline)
                        .foregroundColor(ContentView.cyan)
                        .frame(width: 22, height: 32)
                }
            }
            Image(systemName: "magnifyingglass").foregroundColor(Self.sub)
            TextField(addingVia ? "搜索途经点（比如加油站）" : "搜索地点、地址", text: $query)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .submitLabel(.search)
                .onSubmit { submitSearch() }
            if !query.isEmpty || homeStage != .idle {
                Button { resetHome() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Self.sub)
                }
            }
            if keyboardHeight > 0 {
                Button("取消") { hideKeyboard() }
                    .font(.subheadline).foregroundColor(ContentView.cyan)
            }
            Button { hideKeyboard(); showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Self.stroke.opacity(0.95)))
            }
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(Self.bg))
    }

    // MARK: 首页抽屉内容：按「搜索 / 地点 / 路线」三个阶段切换

    /// 搜索态有没有内容要展示（决定空闲时抽屉的高度）
    private var hasSearchContent: Bool {
        !search.results.isEmpty || !search.status.isEmpty || !shareStatus.isEmpty
    }

    /// 搜索态：只放实时检索结果；最近去过改到 recentSection，上滑才出现
    @ViewBuilder
    private var searchResultSection: some View {
        if !shareStatus.isEmpty { Text(shareStatus).font(.footnote).foregroundColor(ContentView.sub) }
        if !search.status.isEmpty { Text(search.status).font(.footnote).foregroundColor(ContentView.sub) }
        if shareBusy { Text("正在识别分享内容…").font(.footnote).foregroundColor(ContentView.sub) }
        ForEach(search.results.prefix(8)) { p in
            Button { choose(p) } label: {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).foregroundColor(.white)
                        Text(p.address).font(.caption).foregroundColor(ContentView.sub).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let d = distanceTo(p) { Text(d).font(.caption).foregroundColor(ContentView.cyan) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }
            Divider().background(ContentView.stroke)
        }
    }

    /// 最近去过：左滑单条删除；只在抽屉上滑展开 / 搜途经点时出现
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(addingVia ? "从最近去过里选途经点" : "最近去过")
                    .font(.caption).foregroundColor(ContentView.sub)
                Spacer()
                if !history.places.isEmpty {
                    Button("清除记录") { history.clear() }
                        .font(.caption).foregroundColor(ContentView.sub)
                }
            }
            if history.places.isEmpty {
                Text("暂无记录").font(.caption2).foregroundColor(ContentView.sub)
            } else {
                recentList
            }
        }
    }

    /// 只有 List 的行支持系统 swipeActions；固定高度避免和外层 ScrollView 抢滚动
    private var recentList: some View {
        let rows: [SearchService.Place] = Array(history.places.prefix(8))
        let h: CGFloat = CGFloat(rows.count) * 54
        return List {
            ForEach(rows) { p in recentRow(p) }
        }
        .listStyle(.plain)
        .background(ContentView.bg)
        .frame(height: h)
    }

    private func recentRow(_ p: SearchService.Place) -> some View {
        Button { choose(p) } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).foregroundColor(.white).lineLimit(1)
                    if !p.address.isEmpty {
                        Text(p.address).font(.caption).foregroundColor(ContentView.sub).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let d = distanceTo(p) { Text(d).font(.caption).foregroundColor(ContentView.cyan) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .listRowBackground(ContentView.card)
        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { history.remove(p) } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    /// 途经点管理页顶栏：左「返回」+ 标题 + 右「完成」
    private var viaManagerBar: some View {
        HStack(spacing: 8) {
            Button { closeViaManager() } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                    Text("返回")
                }
                .font(.subheadline).foregroundColor(ContentView.cyan)
            }
            Spacer()
            Text("途经点").font(.headline).foregroundColor(.white)
            Spacer()
            Button("完成") { closeViaManager() }
                .font(.subheadline).foregroundColor(ContentView.pink)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// 途经点管理页：起点 / 途经点（可单删、可拖动排序）/ 终点 / 添加
    private var viaManagerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardView {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill").foregroundColor(ContentView.cyan)
                    Text("我的位置").foregroundColor(.white).font(.subheadline)
                    Spacer()
                    Text("起点").font(.caption2).foregroundColor(ContentView.sub)
                }
            }
            viaEditList
            CardView {
                HStack(spacing: 8) {
                    Image(systemName: "flag.fill").foregroundColor(ContentView.pink)
                    Text(dest?.name ?? "目的地").foregroundColor(.white).font(.subheadline).lineLimit(1)
                    Spacer()
                    Text("终点").font(.caption2).foregroundColor(ContentView.sub)
                }
            }
            HStack(spacing: 12) {
                Button { openViaSearch() } label: {
                    Label("添加途经点", systemImage: "plus.circle.fill")
                        .font(.subheadline).foregroundColor(ContentView.cyan)
                }
                .disabled(navi.vias.count >= 3 || navi.shareRoute != nil)
                Spacer()
                if !navi.vias.isEmpty {
                    Button("清空") { navi.clearVias() }
                        .font(.caption).foregroundColor(ContentView.sub)
                }
            }
            Text(navi.vias.isEmpty ? "还没有途经点" : "最多 3 个；拖动右侧手柄调序，改动后自动重新规划")
                .font(.caption2).foregroundColor(ContentView.sub)
        }
    }

    /// 途经点列表：系统 onMove 拖拽排序 + 每行单独删除按钮
    private var viaEditList: some View {
        let h: CGFloat = CGFloat(navi.vias.count) * 50
        return List {
            ForEach(navi.vias) { v in viaRow(v) }
                .onMove { src, dst in
                    if let i = src.first { navi.moveVia(from: i, to: dst) }
                }
        }
        .environment(\.editMode, $viaEditMode)
        .listStyle(.plain)
        .background(ContentView.bg)
        .frame(height: max(h, 8))
    }

    private func viaRow(_ v: NaviBridge.Via) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundColor(ContentView.cyan)
            Text(v.name).foregroundColor(.white).font(.subheadline).lineLimit(1)
            Spacer(minLength: 4)
            Button { navi.removeVia(id: v.id) } label: {
                Image(systemName: "minus.circle.fill").foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .listRowBackground(ContentView.card)
        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
    }

    /// 地点态（苹果地图式地点卡）：大标题 + 地址 + 底部主要动作
    private var placeCard: some View {
        SheetBlock {
            if let d = dest {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(d.name).font(.title3.bold()).foregroundColor(.white).lineLimit(2)
                        if !d.address.isEmpty {
                            Text(d.address).font(.footnote).foregroundColor(ContentView.sub).lineLimit(2)
                        }
                        if let dist = distanceTo(d) {
                            Text(dist).font(.caption2).foregroundColor(ContentView.sub)
                        }
                    }
                    Spacer(minLength: 8)
                    Button { resetHome() } label: {
                        Image(systemName: "xmark").font(.caption).foregroundColor(ContentView.sub)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(ContentView.bg))
                    }
                }
                HStack(spacing: 10) {
                    Button { favorites.add(d) } label: {
                        Label("收藏", systemImage: "star")
                            .font(.subheadline).foregroundColor(ContentView.cyan)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(RoundedRectangle(cornerRadius: 12).fill(ContentView.bg))
                    }
                    Button { startRoutePlanning() } label: {
                        Label("路线", systemImage: "arrow.triangle.turn.up.right.diamond")
                            .font(.headline).foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Capsule().fill(ContentView.pink))
                    }
                }
            }
        }
    }

    /// 路线态（苹果地图式路线表）：出行方式 → 路线卡 → 途经 / 避让 → 开始导航
    private var routePanel: some View {
        SheetBlock {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dest?.name ?? "路线").font(.title3.bold()).foregroundColor(.white).lineLimit(1)
                    Text("驾车 · 高德导航").font(.caption).foregroundColor(ContentView.sub)
                }
                Spacer(minLength: 8)
                Button { resetHome() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(ContentView.sub)
                }
            }
            routeModeChips
            if let sr = navi.shareRoute {
                Text("按高德分享的\(sr.kind)路线走（\(NaviBridge.distText(Int(sr.total)))）")
                    .font(.caption).foregroundColor(.orange)
                if !navi.shareMatch.isEmpty { Text(navi.shareMatch).font(.caption).foregroundColor(ContentView.sub) }
            }
            if !navi.routeOptions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(navi.routeOptions) { o in
                            RouteCard(option: o, selected: o.id == navi.selectedRouteID)
                                .frame(width: 140)
                                .onTapGesture { navi.select(routeID: o.id) }
                        }
                    }
                }
            } else {
                Text(navi.calculating ? "正在规划路线…" : (navi.planFailed ? "路线规划失败" : navi.info))
                    .font(.footnote).foregroundColor(ContentView.sub)
            }
            if navi.planFailed && !navi.calculating {
                Button { navi.replan() } label: {
                    Label("重新规划", systemImage: "arrow.clockwise").font(.subheadline).foregroundColor(ContentView.cyan)
                }
            }
            if navi.shareRoute == nil {
                HStack(spacing: 10) {
                    Text(viaSummary)
                        .font(.caption).foregroundColor(ContentView.sub).lineLimit(2)
                    Spacer(minLength: 4)
                    Button { openViaManager() } label: {
                        Label(navi.vias.isEmpty ? "添加途经点" : "途经点管理",
                              systemImage: navi.vias.isEmpty ? "plus.circle" : "ellipsis.circle")
                            .font(.caption).foregroundColor(ContentView.cyan)
                    }
                }
            }
            HStack(spacing: 12) {
                Toggle("不走高速", isOn: $settings.avoidHighway)
                    .font(.caption).foregroundColor(.white).tint(ContentView.pink)
                    .onChange(of: settings.avoidHighway) { _ in navi.replan() }
                Spacer(minLength: 4)
            }
            plateRow
            PillButton(title: "开始导航", color: ContentView.pink, enabled: navi.routeReady) {
                navi.start(emulate: false); showNavi = true
            }
            HStack {
                Spacer()
                Button("模拟导航") { navi.start(emulate: true); showNavi = true }
                    .font(.caption2).foregroundColor(ContentView.sub)
                    .disabled(!navi.routeReady)
            }
        }
    }

    /// 出行方式：驾车留在本地高德导航，摩托车 / 自行车跳到独立路线规划
    private var routeModeChips: some View {
        HStack(spacing: 8) {
            Label("驾车", systemImage: "car.fill")
                .font(.caption).foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(ContentView.pink.opacity(0.85)))
            Button { openWebMotor(.motorcycle) } label: {
                Label("摩托车", systemImage: "flag.fill").font(.caption).foregroundColor(ContentView.cyan)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(ContentView.bg))
            }
            Button { openWebMotor(.bicycle) } label: {
                Label("自行车", systemImage: "bicycle").font(.caption).foregroundColor(ContentView.cyan)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(ContentView.bg))
            }
            Spacer(minLength: 0)
        }
    }

    /// 路线面板里的车牌 / 限行状态：点一下去设置，改完立刻按新车牌重算
    private var plateRow: some View {
        Button { showPlate = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "car.fill").font(.caption)
                    .foregroundColor(settings.restrictionActive ? ContentView.cyan : ContentView.sub)
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.restrictionActive ? "已避开限行" : "添加车牌，避开限行")
                        .font(.caption).foregroundColor(.white)
                    Text(settings.plateSummary).font(.caption2).foregroundColor(ContentView.sub)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(ContentView.sub)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 程序化改搜索框文字：值真的变了才压住下一次实时检索，避免抑制标记残留
    private func setQuery(_ new: String) {
        if query != new { suppressAutoSearch = true }
        query = new
    }

    /// 输入实时检索：350ms 防抖 + 至少 2 个字；SearchService 自带关键词缓存
    private func scheduleAutoSearch(_ raw: String) {
        searchWork?.cancel()
        pendingSearchSubmit = false      // 用户继续打字，就别再自动选「按搜索」那条结果了
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2, !settings.amapKeyInUse.isEmpty else { return }
        let work = DispatchWorkItem { SearchService.shared.search(t) }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// 按「搜索」：直接按当前词查一次（命中缓存不额外花额度），结果回来自动选第一条。
    /// 不直接取 search.results，是因为 350ms 防抖可能还没跑完，那里可能是上一个词的结果。
    private func submitSearch() {
        suppressAutoSearch = false
        hideKeyboard()
        searchWork?.cancel()
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        pendingSearchSubmit = true
        guard !needAmapKey() else { pendingSearchSubmit = false; return }
        SearchService.shared.search(t)
    }

    /// 用户重新输入：退出地点 / 路线态，回到搜索态（不动 query，避免递归触发 onChange）
    private func backToSearch() {
        navi.clearPlan()
        dest = nil; homeFocus = nil; homeStage = .idle
        sheetExpanded = false; addingVia = false; viaManager = false
        pendingSearchSubmit = false; autoStartNavi = false
    }

    /// 关闭按钮：完全回到首页空闲态
    private func resetHome() {
        setQuery("")
        search.clear()
        backToSearch()
        shareStatus = ""
    }

    /// 点「路线」：这时才真正调高德算路
    private func startRoutePlanning() {
        guard let d = dest else { return }
        homeStage = .routes
        guard !needAmapKey() else { return }
        navi.plan(toLat: d.lat, lng: d.lng)
    }

    /// 打开途经点管理面板（参考高德：起点 / 途经点可增删可排序 / 终点）
    private func openViaManager() {
        hideKeyboard()
        addingVia = false
        viaManager = true
        homeStage = .routes
        sheetExpanded = false
    }

    /// 管理页点「+ 添加途经点」→ 进入搜索（搜索条自带返回按钮）
    private func openViaSearch() {
        guard navi.vias.count < 3, navi.shareRoute == nil else { return }
        viaManager = false
        addingVia = true
        homeStage = .idle
        sheetExpanded = false
        setQuery("")
        search.clear()
    }

    /// 途经点搜索页「返回」：回到管理页
    private func cancelViaSearch() {
        hideKeyboard()
        searchWork?.cancel()
        addingVia = false
        setQuery("")
        search.clear()
        viaManager = true
        homeStage = .routes
    }

    /// 管理页「返回 / 完成」：回到路线面板
    private func closeViaManager() {
        viaManager = false
        addingVia = false
        homeStage = .routes
        sheetExpanded = false
        overviewToken += 1
    }

    /// 离现在位置的直线距离（搜索结果、最近去过右边显示）
    private func distanceTo(_ p: SearchService.Place) -> String? {
        guard let me = navi.myPosition() else { return nil }
        let d = Int(NaviBridge.distM(me.lat, me.lng, p.lat, p.lng))
        return d >= 1000 ? String(format: "%.1f 公里", Double(d) / 1000) : "\(d) 米"
    }

    /// 剩余秒数 → 到达时间“18:52”
    static func etaText(_ remainS: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: Date().addingTimeInterval(TimeInterval(remainS)))
    }

    /// 点了搜索结果 / 自动检索结果：地图定位到该地点并出「路线」按钮。
    /// autoPlan = true 只给「分享后自动导航」用，选中即算路并自动开始导航。
    private func choose(_ p: SearchService.Place, autoPlan: Bool = false) {
        showSettings = false          // 从设置中心的「常用目的地」选点时，先回到地图
        guard !navi.navigating else { shareStatus = "导航仍在运行；如需更换目的地，请先结束导航"; return }
        guard !WebMotorSession.shared.running else { shareStatus = "请先结束网页导航"; return }
        searchWork?.cancel()
        pendingSearchSubmit = false
        search.clear()
        hideKeyboard()
        if addingVia {
            addingVia = false
            setQuery(dest?.name ?? "")
            if !needAmapKey() { navi.addVia(name: p.name, lat: p.lat, lng: p.lng) }
            History.shared.add(p)
            viaManager = true          // 加完回管理页，可继续增删 / 排序
            homeStage = .routes
            overviewToken += 1
            return
        }
        dest = p
        setQuery(p.name)
        shareStatus = ""
        History.shared.add(p)
        homeFocus = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)
        focusToken += 1
        sheetExpanded = false
        if autoPlan {
            homeStage = .routes
            if !needAmapKey() { navi.plan(toLat: p.lat, lng: p.lng) }
        } else {
            homeStage = .place
            navi.clearPlan()
        }
    }

    /// AppDelegate 收到通知但界面还没起来时，先暂存；界面出现 / 回到前台再补一次。
    private func flushPendingShare() {
        guard let t = AppDelegate.pendingShareText, !t.isEmpty else { return }
        AppDelegate.pendingShareText = nil
        deliverShare(t)
    }

    /// 自动路径统一入口：URL Scheme 或通知都带着分享正文，
    /// 完全不需要读系统剪贴板，因此不会触发 iOS 16+ 的「允许粘贴」弹窗。
    private func deliverShare(_ raw: String) {
        let t = SharePlace.strip(raw)
        guard !t.isEmpty, t != lastHandledShare, !shareBusy else { return }
        lastHandledShare = t
        UIPasteboard.general.string = ""      // 只写不读：清掉扩展留的暂存，避免按钮重复导入
        handleShare(t)
    }

    /// 分享统一入口：URL Scheme（onOpenURL）、前台自动消费、剪贴板按钮都走这里
    private func handleShare(_ raw: String) {
        let t = SharePlace.strip(raw)
        guard !t.isEmpty else { shareStatus = "分享内容为空"; return }
        if navi.navigating || WebMotorSession.shared.running {
            shareStatus = "正在导航：先退出导航，再导入分享内容"
            return
        }
        addingVia = false
        hideKeyboard()
        search.clear()

        // 只有高德「路线分享」才走原来的整条路线还原；高德地点分享直接按地点处理
        let looksLikeRoute = t.contains("shareParam") || t.contains("__r=") || t.contains("/navigation/")
            || t.contains("daddr=") || t.contains("saddr=") || t.contains("uri.amap.com/navigation")
        if AmapShare.findUrl(t) != nil && looksLikeRoute {
            importRouteShare(t)
        } else {
            importPlaceShare(t)
        }
    }

    /// 原来的高德路线还原。高德网页内部接口一改版就会失效，这里失败自动降级成「按分享里的终点导航」
    private func importRouteShare(_ t: String) {
        shareBusy = true
        shareStatus = "正在读取高德分享的路线…"
        DispatchQueue.global(qos: .userInitiated).async {
            let res = Result { try AmapShare.load(t) }
            DispatchQueue.main.async {
                shareBusy = false
                guard !navi.navigating, !WebMotorSession.shared.running else {
                    shareStatus = "导航已开始，请结束后重新导入"; return
                }
                switch res {
                case .success(let r):
                    shareStatus = "已读取：\(r.kind)路线 \(NaviBridge.distText(r.distance > 0 ? r.distance : Int(r.total)))" +
                        (r.timeS > 0 ? "，约 \(NaviBridge.durText(r.timeS))" : "") +
                        (r.restored ? "" : "（高德没能原样还原，可能和分享的稍有不同）")
                    let name = r.endName.isEmpty ? "分享的目的地" : r.endName
                    dest = SearchService.Place(name: name, address: "高德分享的\(r.kind)路线", lat: r.endLat, lng: r.endLng)
                    History.shared.add(SearchService.Place(name: name, address: "", lat: r.endLat, lng: r.endLng))
                    setQuery(name)
                    search.clear()
                    homeFocus = CLLocationCoordinate2D(latitude: r.endLat, longitude: r.endLng)
                    focusToken += 1
                    homeStage = .routes
                    sheetExpanded = false
                    if r.kind == "自行车" {
                        navi.clearPlan()
                        WebMotorSession.shared.route = MotorRoutes.fromShare(r)
                        independentMode = .bicycle
                        showWebMotor = true
                    } else if !needAmapKey() {
                        autoStartNavi = true
                        navi.plan(toLat: r.endLat, lng: r.endLng, share: r)
                    }
                case .failure(let e):
                    shareStatus = "高德路线还原失败（\(e.localizedDescription)），改用分享里的终点直接导航…"
                    importPlaceShare(t)
                }
            }
        }
    }

    /// 地点分享：解析 → 设目的地 → 规划 → 算好自动开始导航
    private func importPlaceShare(_ t: String) {
        shareBusy = true
        shareStatus = "正在识别分享的地点…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = SharePlace.resolve(t)
            DispatchQueue.main.async {
                shareBusy = false
                guard !navi.navigating, !WebMotorSession.shared.running else {
                    shareStatus = "导航已开始，请结束后重新导入"; return
                }
                switch result {
                case .place(let p):
                    applyPlace(p)
                case .needSearch(let name):
                    setQuery(name)
                    shareStatus = "分享里只有地名「\(name)」，正在用高德搜索…"
                    guard !needAmapKey() else { return }
                    autoPickResult = true
                    autoStartNavi = true
                    search.search(name)
                case .none:
                    shareStatus = "没认出分享内容里的地点。请在地图里点「分享」→「MotoNav」，或复制含链接 / 经纬度的文本后重试"
                }
            }
        }
    }

    /// 拿到 GCJ-02 坐标后设置目的地；routeReady 变 true 时会自动开始导航
    private func applyPlace(_ p: SharePlace.Place) {
        let place = SearchService.Place(name: p.name, address: "来自\(p.source)分享", lat: p.lat, lng: p.lng)
        dest = place
        setQuery(p.name)
        search.clear()
        History.shared.add(place)
        homeFocus = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)
        focusToken += 1
        homeStage = .routes
        sheetExpanded = false
        let coordText = String(format: "%.5f, %.5f", p.lat, p.lng)
        shareStatus = "已收到\(p.source)分享的地点：\(p.name)（\(coordText)），正在规划…"
        guard !needAmapKey() else { return }
        autoStartNavi = true
        // 规划失败时别让这个标记一直挂着，避免以后手动规划也被强制自动开始
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { if autoStartNavi { autoStartNavi = false } }
        navi.plan(toLat: p.lat, lng: p.lng)
    }

    /// 途经点文字：单独算，别塞进 ViewBuilder 里让类型检查器猜
    private var viaSummary: String {
        if navi.vias.isEmpty { return "途经：无" }
        let names: [String] = navi.vias.map { $0.name }
        return "途经：" + names.joined(separator: " → ")
    }

    /// 分享原路线的折线（橙色虚线）
    private var shareGhost: [CLLocationCoordinate2D] {
        guard let r = navi.shareRoute else { return [] }
        return r.pts.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    /// 途经点坐标
    private var viaCoords: [CLLocationCoordinate2D] {
        navi.vias.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    // MARK: 首页：全屏地图 + 悬浮控件 + 底部搜索面板（苹果地图式层级）
    private var homePage: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ZStack(alignment: .topTrailing) {
                    HomeMapView(
                        night: mapNight,
                        satellite: mapSatellite,
                        focus: homeFocus,
                        focusToken: focusToken,
                        recenterToken: recenterToken,
                        overviewToken: overviewToken,
                        routes: (homeStage == .routes || addingVia) ? navi.routeOptions : [],
                        selectedRouteID: navi.selectedRouteID,
                        ghost: shareGhost,
                        dest: (homeStage == .routes || addingVia) ? navi.destCoord : nil,
                        vias: viaCoords,
                        bottomInset: panelHeight(geo) + keyboardHeight
                    )
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // 键盘弹出时：点地图空白处收起键盘（只在键盘可见时盖一层透明视图）
                    if keyboardHeight > 0 {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { hideKeyboard() }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    mapControls
                        .padding(.top, 14)
                        .padding(.trailing, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    recenterButton
                        .padding(.trailing, 16)
                        .padding(.bottom, panelHeight(geo) + keyboardHeight + 14)
                }
                homeDrawer(height: panelHeight(geo))
            }
        }
    }

    /// 地图右上角悬浮控件（苹果地图式圆钮）
    private var mapControls: some View {
        VStack(spacing: 10) {
            Menu {
                Button { mapAppearance = 0 } label: { Label("自动（跟随昼夜）", systemImage: "clock") }
                Button { mapAppearance = 1 } label: { Label("标准地图", systemImage: "sun.max") }
                Button { mapAppearance = 2 } label: { Label("夜间地图", systemImage: "moon") }
                Button { mapAppearance = 3 } label: { Label("卫星图", systemImage: "globe") }
            } label: {
                MapGlassButton(icon: "map", active: mapAppearance != 0)
            }
            Button {
                if navi.cruising { navi.stopCruise() }
                else if !needAmapKey() { cruiseNote = navi.startCruise() ?? "" }
            } label: {
                MapGlassButton(icon: "binoculars.fill", active: navi.cruising)
            }
            Button {
                if ble.isReady { ble.disconnect() } else { ble.connect() }
            } label: {
                MapGlassButton(icon: "dot.radiowaves.left.and.right", active: ble.isReady, tint: Color.green)
            }
        }
    }

    /// 地图外观：0 自动跟昼夜 / 1 标准 / 2 夜间 / 3 卫星
    private var mapNight: Bool {
        switch mapAppearance {
        case 1: return false
        case 2: return true
        case 3: return false
        default: return settings.paletteNight
        }
    }
    private var mapSatellite: Bool { mapAppearance == 3 }

    /// 右下角：回到我的定位位置（苹果地图式玻璃圆钮）
    private var recenterButton: some View {
        Button { recenterToken += 1 } label: {
            MapGlassButton(icon: "location.fill")
        }
        .accessibilityLabel("回到定位位置")
    }

    /// 面板高度跟着阶段走；键盘弹起时收窄，保证搜索框始终看得见
    private func panelHeight(_ geo: GeometryProxy) -> CGFloat {
        let raw: CGFloat
        if sheetExpanded { raw = min(geo.size.height * 0.82, 640) }
        else if viaManager { raw = min(geo.size.height * 0.64, 480) }
        else if addingVia { raw = min(geo.size.height * 0.52, 400) }
        else if homeStage == .place { raw = 200 }
        else if homeStage == .routes { raw = min(geo.size.height * 0.52, 400) }
        else { raw = hasSearchContent ? min(geo.size.height * 0.52, 400) : 122 }
        let avail = geo.size.height - keyboardHeight - 20
        return min(raw, max(122, avail))
    }

    /// 抽屉：抓手 + 搜索框固定；上滑展开最近去过 / 常用目的地 / 快捷功能
    private func homeDrawer(height: CGFloat) -> some View {
        let showList = sheetExpanded || viaManager || addingVia || homeStage != .idle || hasSearchContent
        return VStack(spacing: 0) {
            if !showList { Spacer(minLength: 0) }

            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.32)).frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSheet() }
                if viaManager {
                    viaManagerBar
                } else {
                    homeSearchBar.padding(.horizontal, 14).padding(.bottom, 10)
                }
            }
            // 手势只加在「抓手 + 搜索框」区域，避免和下面列表滚动打架
            .gesture(DragGesture(minimumDistance: 24).onEnded { v in
                if v.translation.height < -45 { setSheet(true) }
                else if v.translation.height > 45 { setSheet(false) }
            })

            if showList {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if viaManager {
                            viaManagerPanel
                        } else {
                            if homeStage == .idle {
                                searchResultSection
                            } else if homeStage == .place {
                                placeCard
                            } else {
                                routePanel
                            }
                            if addingVia || sheetExpanded { recentSection }
                            if sheetExpanded {
                                quickActions
                                favoritesCard
                            }
                            if !shareStatus.isEmpty && homeStage != .idle {
                                Text(shareStatus).font(.caption2).foregroundColor(ContentView.sub)
                            }
                        }
                        Color.clear.frame(height: 6)
                    }
                    .padding(.horizontal, 14).padding(.bottom, 18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear.frame(height: 30)     // 底部留白，避开 home indicator
                    .contentShape(Rectangle())
                    .onTapGesture { hideKeyboard() }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Self.card.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Self.stroke, lineWidth: 1))
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: homeStage)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: sheetExpanded)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: hasSearchContent)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: viaManager)
        .padding(.bottom, keyboardHeight)        // 键盘弹起时把搜索框顶到键盘上沿
    }

    private func setSheet(_ v: Bool) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { sheetExpanded = v }
    }

    private func toggleSheet() {
        hideKeyboard()                    // 点抓手也算「点空白处」，先把键盘收掉
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { sheetExpanded.toggle() }
    }

    /// 快捷功能：苹果地图式横向胶囊，点一下直接进功能，不用翻设置
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快捷功能").font(.caption).foregroundColor(ContentView.sub)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickChip(navi.cruising ? "结束巡航" : "巡航模式", "binoculars.fill", navi.cruising) {
                        if navi.cruising { navi.stopCruise() }
                        else if !needAmapKey() { cruiseNote = navi.startCruise() ?? "" }
                    }
                    quickChip("摩托车路线", "flag.fill", false) { openWebMotor(.motorcycle) }
                    quickChip("自行车路线", "bicycle", false) { openWebMotor(.bicycle) }
                    quickChip("骑行轨迹", "map", false) { showRides = true }
                    quickChip("车牌与限行", "car.fill", settings.restrictionActive) { showPlate = true }
                    quickChip("全部设置", "gearshape", false) { showSettings = true }
                }
            }
        }
    }

    private func quickChip(_ title: String, _ icon: String, _ active: Bool,
                           _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption).foregroundColor(active ? .white : ContentView.cyan)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Capsule().fill(active ? ContentView.pink.opacity(0.85) : ContentView.bg))
                .overlay(Capsule().stroke(ContentView.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func openWebMotor(_ mode: IndependentMode) {
        if !independent.running { independent.arrived = false }
        independentMode = mode
        showWebMotor = true
    }

    // MARK: 设置中心（齿轮）：原 dock 的 4 页 + 全部功能，苹果式分组列表
    private var settingsHub: some View {
        NavigationView {
            List {
                Section(header: Text("导航与路线")) {
                    Button { hubPlate = true } label: {
                        settingsRow("车牌与限行", settings.plateSummary, "car.fill", ContentView.cyan)
                    }
                    Button { hubKeys = true } label: {
                        settingsRow("地图 Key", Settings.mask(settings.amapKeyInUse), "key.fill", ContentView.cyan)
                    }
                    NavigationLink(destination: AnyView(settingsDetail(.voice))) {
                        settingsRow("导航语音", "音色 · 语速 · 播报", "speaker.wave.2", ContentView.pink)
                    }
                    NavigationLink(destination: AnyView(settingsDetail(.favorites))) {
                        settingsRow("常用目的地", "\(favorites.places.count) 个地点", "star.fill", ContentView.pink)
                    }
                    Button { hubRides = true } label: {
                        settingsRow("骑行轨迹", "历史行程", "map", ContentView.cyan)
                    }
                }
                Section(header: Text("骑行功能")) {
                    NavigationLink(destination: AnyView(settingsDetail(.cruise))) {
                        settingsRow("巡航模式", navi.cruising ? "进行中" : "测速 / 电子眼 / 急弯提醒", "binoculars.fill", ContentView.cyan)
                    }
                    NavigationLink(destination: AnyView(settingsDetail(.routeModes))) {
                        settingsRow("路线规划", "摩托车 / 自行车独立算路", "flag.fill", ContentView.pink)
                    }
                }
                Section(header: Text("圆屏")) {
                    NavigationLink(destination: AnyView(settingsDetail(.screen))) {
                        settingsRow("圆屏设置", ble.isReady ? ble.status : "未连接", "gearshape", ContentView.cyan)
                    }
                    NavigationLink(destination: AnyView(settingsDetail(.display))) {
                        settingsRow("圆屏显示", Settings.themeName(settings.theme), "circle.dashed", ContentView.pink)
                    }
                    NavigationLink(destination: AnyView(settingsDetail(.debug))) {
                        settingsRow("调试信息", "连接与导航日志", "doc.text", ContentView.sub)
                    }
                }
                Section(header: Text("关于")) {
                    NavigationLink(destination: AnyView(settingsDetail(.about))) {
                        settingsRow("MotoNav", "圆屏导航 · \(APP_VERSION)", "info.circle", ContentView.sub)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { showSettings = false }.foregroundColor(ContentView.pink)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $hubPlate) { PlateSetupView() }
        .sheet(isPresented: $hubKeys) { KeySetupView() }
        .sheet(isPresented: $hubRides) { NavigationView { RideHistoryView() } }
        .fullScreenCover(isPresented: $hubWeb) { WebMotorView(mode: hubMode) }
    }

    private func settingsRow(_ title: String, _ sub: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.subheadline).foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundColor(.white)
                if !sub.isEmpty { Text(sub).font(.caption2).foregroundColor(ContentView.sub).lineLimit(1) }
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 3)
        .listRowBackground(ContentView.card)
    }

    @ViewBuilder
    private func settingsDetail(_ p: SettingsPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch p {
                case .display:
                    displayCard
                case .voice:
                    voiceCard
                case .screen:
                    VStack(spacing: 16) { statusCard; settingsCard }
                case .cruise:
                    cruiseCard
                case .debug:
                    debugCard
                case .favorites:
                    favoritesCard
                case .routeModes:
                    independentRouteCard
                case .about:
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        keyCard
                        Text(weather.detail).font(.caption).foregroundColor(ContentView.sub)
                    }
                }
            }
            .padding(16)
        }
        .background(ContentView.bg.ignoresSafeArea())
        .navigationTitle(p.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var independentRouteCard: some View {
        CardView {
            Text("独立路线规划").foregroundColor(.white).bold()
            Text("摩托车 / 自行车用网页版算路，不走高德驾车导航，也不受车牌限行设置影响。")
                .font(.caption).foregroundColor(ContentView.sub)
            Button { openHubWebMotor(.motorcycle) } label: {
                Label("摩托车路线规划", systemImage: "flag.fill")
                    .font(.subheadline).foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ContentView.pink.opacity(0.85)))
            }
            Button { openHubWebMotor(.bicycle) } label: {
                Label("自行车路线规划", systemImage: "bicycle")
                    .font(.subheadline).foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ContentView.cyan.opacity(0.8)))
            }
        }
    }

    private func openHubWebMotor(_ mode: IndependentMode) {
        if !independent.running { independent.arrived = false }
        hubMode = mode
        hubWeb = true
    }

    /// Key 设置：首页弹首页的、设置中心弹设置中心的，互不抢同一层 sheet
    private func openKeySetup() {
        if showSettings { hubKeys = true } else { showKeys = true }
    }

    // MARK: 巡航
    private var cruiseCard: some View {
        CardView {
            HStack {
                Text("巡航模式").foregroundColor(.white).bold()
                Spacer()
                if navi.cruising { Text("进行中 · \(navi.uiSpeed) km/h").font(.caption).foregroundColor(ContentView.cyan) }
            }
            Text("不设目的地：骑车时提醒前方测速、电子眼和急弯、学校、事故多发等道路安全提示，圆屏照常显示小地图")
                .font(.caption).foregroundColor(ContentView.sub)
            if navi.cruising { Text(navi.info).font(.footnote).foregroundColor(ContentView.sub) }
            PillButton(title: navi.cruising ? "结束巡航" : "开始巡航", color: navi.cruising ? Color.gray : ContentView.cyan.opacity(0.8),
                       enabled: !navi.navigating && !WebMotorSession.shared.running) {
                cruiseNote = ""
                if navi.cruising { navi.stopCruise() }
                else if !needAmapKey(), let err = navi.startCruise() { cruiseNote = err }
            }
            if !cruiseNote.isEmpty { Text(cruiseNote).font(.caption).foregroundColor(Color.orange) }
        }
    }

    // MARK: 圆屏设置
    private var settingsCard: some View {
        CardView {
            Text("圆屏设置").foregroundColor(.white).bold()
            Picker("开机动画", selection: $settings.bootBrand) {
                ForEach(Settings.bootBrands.indices, id: \.self) { i in Text(Settings.bootBrands[i]).tag(i) }
            }.tint(ContentView.cyan)
            Text(settings.bootStatus).font(.caption).foregroundColor(ContentView.sub)
            Toggle("蓝牙媒体按键（QQ 音乐等）", isOn: $settings.musicHID).foregroundColor(.white).tint(ContentView.pink)
            if settings.musicHID {
                Text(ble.mediaHIDSupported
                     ? (ble.mediaHIDReady && ble.mediaHIDMode ? "媒体按键已就绪" : ble.mediaAMSControls > 0 && ble.mediaHIDMode ? "AMS 媒体控制已就绪，HID 当前不可用" : "请在 iPhone 设置 → 蓝牙中配对 MotoNav；按圆屏配对码提示完成")
                     : "需要圆屏 HID 固件 v7.9.0 或更新版，连接后自动同步")
                    .font(.caption).foregroundColor(ContentView.sub)
                if !ble.mediaSongInfo.isEmpty {
                    Text(ble.mediaSongInfo).font(.caption).foregroundColor(ContentView.cyan)
                }
                Toggle("显示逐句歌词", isOn: $settings.musicLyrics).foregroundColor(.white).tint(ContentView.pink)
                Text("默认关闭，上方歌名、下方歌手。开启后按歌曲信息从 LRCLIB 匹配歌词，歌词显示在歌手下方；未匹配到时保留歌名和歌手。")
                    .font(.caption).foregroundColor(ContentView.sub)
                if !settings.musicLyrics && ble.mediaLyricsActive { Text("正在关闭圆屏歌词…").font(.caption).foregroundColor(ContentView.sub) }
                if settings.musicLyrics {
                    Text(ble.mediaLyricsSupported ? ble.mediaLyricsStatus : "需要圆屏固件 v7.11.0 或更新版")
                        .font(.caption).foregroundColor(ContentView.cyan)
                }
                Text("先在网易云或 QQ 音乐开始播放，再用圆屏控制。新固件通过 iPhone AMS 显示歌名、歌手和状态，信息取决于当前播放器提供的内容。HID SENT 表示按键已发送。")
                    .font(.caption).foregroundColor(ContentView.sub)
            } else {
                Button("授权 Apple Music 圆屏控制") { MusicBridge.shared.authorize() }
                    .foregroundColor(ContentView.cyan)
            }
            Text("关闭蓝牙媒体按键后，改用系统音乐 App 控制。不读取来电号码。巡航连续停车 10 分钟自动结束。")
                .font(.caption).foregroundColor(ContentView.sub)
            Text("圆屏方向").foregroundColor(.white).padding(.top, 6)
            RotationDial(degrees: $settings.rotationDeg)      // iOS v0.5.1 按住圆盘转动调角度
            Text("按住圆盘转动（顺时针为正），粉色指针是画面上方在圆屏上朝的方向，圆屏会跟着实时转。转到 0°/90°/180°/270° 附近会吸住。任意角度要圆屏固件 v7.10.1；旧固件会转到最接近的 90°")
                .font(.caption2).foregroundColor(ContentView.sub)
            // iOS v0.6 屏幕刷新速度、快速刷屏（圆屏存起来并自动重启；当前值来自圆屏的帧率回报）
            Text("刷新速度").foregroundColor(.white).padding(.top, 6)
            Picker("刷新速度", selection: Binding(get: { ble.screenMHz }, set: { ble.setScreenMHz($0) })) {
                Text("40 标准").tag(40); Text("60").tag(60); Text("80").tag(80)
            }
            .pickerStyle(.segmented)
            .disabled(!ble.isReady)
            Toggle("快速刷屏", isOn: Binding(get: { ble.screenFast == 1 }, set: { ble.setScreenFast($0) }))
                .foregroundColor(.white).tint(ContentView.pink)
                .disabled(!ble.isReady)
            Text(ble.screenMHz < 0
                 ? "越快画面撕裂越轻；花屏就切回 40、关掉快速刷屏。切换后圆屏会自动重启。现在的值要等圆屏显示过小地图才知道"
                 : "越快画面撕裂越轻；花屏就切回 40、关掉快速刷屏。切换后圆屏会自动重启")
                .font(.caption2).foregroundColor(ContentView.sub)
            Toggle("亮度跟着昼夜自动调", isOn: $settings.brightAuto).foregroundColor(.white).tint(ContentView.pink)
            if settings.brightAuto {
                HStack {
                    Text("白天").foregroundColor(.white)
                    Slider(value: $settings.brightDay, in: 5...255, step: 5).tint(ContentView.pink)
                    Text("\(Int(settings.brightDay))").font(.caption).foregroundColor(ContentView.sub).frame(width: 34)
                }
                HStack {
                    Text("夜间").foregroundColor(.white)
                    Slider(value: $settings.brightNight, in: 5...255, step: 5).tint(ContentView.pink)
                    Text("\(Int(settings.brightNight))").font(.caption).foregroundColor(ContentView.sub).frame(width: 34)
                }
                if !settings.brightDesc.isEmpty { Text(settings.brightDesc).font(.caption2).foregroundColor(ContentView.sub) }
            } else {
                HStack {
                    Text("亮度").foregroundColor(.white)
                    Slider(value: $settings.brightness, in: 5...255, step: 5).tint(ContentView.pink)
                    Text("\(Int(settings.brightness))").font(.caption).foregroundColor(ContentView.sub).frame(width: 34)
                }
            }
        }
    }

    private var displayCard: some View {
        CardView {
            Text("圆屏显示").foregroundColor(.white).bold()
            Toggle("路程进度环", isOn: $settings.progressRing).foregroundColor(.white).tint(Self.pink)
            Picker("预判", selection: $settings.leadMs) {
                Text("关闭").tag(0); Text("0.3秒").tag(300); Text("0.6秒").tag(600)
            }.pickerStyle(.segmented)
            Text("地图状态：\(map.shortStatus)").font(.caption).foregroundColor(Self.sub)
            HStack {
                Text("风格").foregroundColor(.white)
                Spacer()
                Picker("风格", selection: $settings.theme) {
                    ForEach(Settings.themeOrder, id: \.self) { t in Text(Settings.themeName(t)).tag(t) }
                }
                .tint(ContentView.cyan)
            }
            Text(Settings.themeDesc(settings.theme)).font(.caption2).foregroundColor(ContentView.sub)
            Toggle("小地图", isOn: $settings.mapOn).foregroundColor(.white).tint(ContentView.pink)
            if settings.mapOn {
                Text("地图来源：高德（普通底图和卫星图）").font(.caption).foregroundColor(ContentView.sub)
                if settings.mapSource == MapFeeder.SRC_AMAP && settings.theme == 1 {
                    Toggle("俯视建筑轮廓", isOn: $settings.buildings).foregroundColor(.white).tint(ContentView.pink)
                    Text(ble.buildingsSupported ? "圆屏支持建筑图层，默认提取高德建筑俯视轮廓" : "正在查询圆屏建筑能力；确认前先显示普通底图")
                        .font(.caption2).foregroundColor(ContentView.sub)
                    if ble.isReady && !ble.buildingsSupported {
                        Button("重新查询建筑能力") { ble.retryBuildingCapability() }
                    }
                    if !map.buildingInfo.isEmpty { Text(map.buildingInfo).font(.caption).foregroundColor(ContentView.sub) }
                }
                Text(map.offlineStatus).font(.caption).foregroundColor(ContentView.sub)
                Text("选定路线后，前台自动下载沿途地图；锁屏使用已保存地图包。请等下载完成再出发。")
                    .font(.caption2).foregroundColor(ContentView.sub)
                Text("走过的路线").foregroundColor(.white)
                Picker("走过的路线", selection: $settings.trail) {
                    Text("变灰").tag(1); Text("擦除").tag(2)
                }
                .pickerStyle(.segmented)
                Toggle("清爽模式", isOn: $settings.clean).foregroundColor(.white).tint(ContentView.pink)
                Text("清爽模式：地图保留，去掉红绿灯、电子眼、安全提示、测速牌和行程信息").font(.caption2).foregroundColor(ContentView.sub)
            }
            Text("夜间配色").foregroundColor(.white)
            Picker("夜间配色", selection: $settings.nightMode) {
                Text("自动（日出日落）").tag(0); Text("白天").tag(1); Text("夜间").tag(2)
            }
            .pickerStyle(.segmented)
            if !settings.nightDesc.isEmpty { Text(settings.nightDesc).font(.caption2).foregroundColor(ContentView.sub) }
            Toggle("弯道急缓上色", isOn: $settings.curve).foregroundColor(.white).tint(ContentView.pink)
        }
    }
    private var favoritesCard: some View {
        CardView {
            Text("常用目的地").foregroundColor(.white).bold()
            if favorites.places.isEmpty { Text("选择目的地后点收藏").foregroundColor(Self.sub) }
            ForEach(favorites.places) { place in
                HStack {
                    Button(place.name) { choose(place.searchPlace) }.foregroundColor(Self.cyan)
                    Spacer()
                    Button("移除") { favorites.remove(place) }.foregroundColor(Self.sub)
                }
            }
        }
    }
    private var voiceCard: some View {
        CardView {
            Text("导航语音").foregroundColor(.white).bold()
            Toggle("导航静音", isOn: $settings.voiceMuted)
            Toggle("播报时压低音乐", isOn: $settings.duck)
            Picker("系统音色", selection: $voiceID) {
                Text("自动优选中文").tag("")
                ForEach(AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("zh") }, id: \.identifier) { voice in
                    Text(voice.name).tag(voice.identifier)
                }
            }
            Text("语速"); Slider(value: $voiceRate, in: 0.3...0.6)
            Text("音调"); Slider(value: $voicePitch, in: 0.7...1.4)
            Button("试听播报") { Speech.shared.test() }
        }.foregroundColor(.white).tint(Self.pink)
    }

    // MARK: Key 设置
    private var keyCard: some View {
        CardView {
            Text("Key 设置").foregroundColor(.white).bold()
            Text("高德 Key：\(Settings.mask(settings.amapKeyInUse))（搜索、导航、巡航用）")
                .font(.footnote).foregroundColor(settings.amapKeyInUse.isEmpty ? Color.orange : ContentView.sub)
            Text("和风天气：\(weather.host.isEmpty || weather.key.isEmpty ? "未配置（可选）" : "已配置")")
                .font(.footnote).foregroundColor(ContentView.sub)
            Button(settings.keysMissing ? "去填写" : "修改") { openKeySetup() }
                .foregroundColor(ContentView.cyan)
        }
    }

    /// 没填高德 key：弹出填写页，返回 true（调用的地方就不往下做了）
    private func needAmapKey() -> Bool {
        if settings.amapKeyInUse.isEmpty {
            hideKeyboard()
            openKeySetup()
            return true
        }
        return false
    }

    // MARK: 调试信息
    private var debugCard: some View {
        CardView {
            Button(showDebug ? "收起调试信息" : "调试信息") { showDebug.toggle() }.foregroundColor(ContentView.cyan)
            if showDebug {
                Text("""
                圆屏：\(ble.status)
                已发送 \(ble.sentCount) 条，最近：\(ble.lastSent)
                \(ble.screenStats)
                导航：\(navi.info)
                路名：\(navi.uiRoad)
                \(navi.laneRaw)
                电子眼：\(navi.camRaw)
                巡航：\(navi.cruiseRaw)
                \(navi.extraInfo)
                小地图：\(map.infoText)
                地图数据累计发送 \(ble.bulkKB) KB
                天气：\(weather.info)
                """)
                .font(.caption.monospaced())
                .foregroundColor(ContentView.sub)
                .textSelection(.enabled)
            }
        }
    }
}

// MARK: - 小组件

/// 底部面板里的内容块：面板本身就是卡片，里面不再套一层圆角卡
struct SheetBlock<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 苹果地图式悬浮玻璃圆钮
struct MapGlassButton: View {
    let icon: String
    var active = false
    var tint: Color = ContentView.cyan
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 42, height: 42)
            .background(Circle().fill(active ? tint.opacity(0.9) : ContentView.card.opacity(0.94)))
            .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.25), radius: 6, y: 3)
    }
}

struct CardView<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(ContentView.card))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(ContentView.stroke, lineWidth: 1))
    }
}

/// 一条路线的对比卡片：标签、时间、距离 · 红绿灯 · 收费
struct RouteCard: View {
    let option: NaviBridge.RouteOption
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(option.label).font(.caption).foregroundColor(selected ? ContentView.pink : ContentView.sub).lineLimit(1)
            Text(NaviBridge.durText(option.timeS)).font(.headline).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
            Text(NaviBridge.distText(option.length) + (option.lights > 0 ? " · \(option.lights)灯" : "") + (option.toll > 0 ? " · ¥\(option.toll)" : ""))
                .font(.caption2).foregroundColor(ContentView.sub).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(ContentView.bg))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? ContentView.pink : ContentView.stroke, lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
    }
}

struct PillButton: View {
    let title: String
    let color: Color
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Capsule().fill(enabled ? color : Color.gray.opacity(0.4)))
        }
        .disabled(!enabled)
    }
}

/// 收起键盘
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

// MARK: - 首页三阶段
private enum HomeStage: Equatable { case idle, place, routes }

/// 设置中心的子页面
private enum SettingsPage: String, CaseIterable, Identifiable {
    case display, voice, screen, debug, cruise, routeModes, favorites, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .display: return "圆屏显示"
        case .voice: return "导航语音"
        case .screen: return "圆屏设置"
        case .debug: return "调试信息"
        case .cruise: return "巡航模式"
        case .routeModes: return "路线规划"
        case .favorites: return "常用目的地"
        case .about: return "关于"
        }
    }
}

// MARK: - 首页底图：高德地图，跟随定位 + 画路线 / 大头针
/// 复用工程里已有的高德 SDK（MAMapView 由 Bridging Header 引入），不新增依赖、不改 pbxproj。
struct HomeMapView: UIViewRepresentable {
    let night: Bool
    var satellite = false
    var focus: CLLocationCoordinate2D? = nil
    var focusToken = 0
    var recenterToken = 0
    var overviewToken = 0
    var routes: [NaviBridge.RouteOption] = []
    var selectedRouteID = -1
    var ghost: [CLLocationCoordinate2D] = []
    var dest: CLLocationCoordinate2D? = nil
    var vias: [CLLocationCoordinate2D] = []
    var bottomInset: CGFloat = 122

    /// 坐标指纹：把字符串插值从长链式表达式里拆出来
    private static func coordKey(_ c: CLLocationCoordinate2D?) -> String {
        guard let c = c else { return "" }
        return String(format: "%.6f,%.6f", c.latitude, c.longitude)
    }

    private static func mapType(night: Bool, satellite: Bool) -> MAMapType {
        if satellite { return .satellite }
        return night ? .standardNight : .standard
    }

    func makeCoordinator() -> HomeMapDelegate { HomeMapDelegate() }

    func makeUIView(context: Context) -> MAMapView {
        let map = MAMapView(frame: .zero)
        map.mapType = HomeMapView.mapType(night: night, satellite: satellite)
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = true
        if let p = NaviBridge.shared.myPosition() {
            map.setCenter(CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng), animated: false)
        }
        map.zoomLevel = 16
        map.userTrackingMode = .follow
        map.delegate = context.coordinator.asDelegate
        return map
    }

    func updateUIView(_ map: MAMapView, context: Context) {
        let type: MAMapType = HomeMapView.mapType(night: night, satellite: satellite)
        if map.mapType != type { map.mapType = type }
        let c = context.coordinator

        // 内容没变就不重画，避免 SwiftUI 频繁刷新把地图拖卡。
        // 拆成带显式类型的小表达式：整段长链式插值会让 Swift 类型检查器超时（Xcode 16.4 实测）。
        let routeKey: String = routes.map { (r: NaviBridge.RouteOption) -> String in
            "\(r.id):\(r.coords.count)"
        }.joined(separator: ",")
        let destKey: String = HomeMapView.coordKey(dest)
        let viaKey: String = vias.map { (p: CLLocationCoordinate2D) -> String in
            HomeMapView.coordKey(p)
        }.joined(separator: ";")
        let focusKey: String = HomeMapView.coordKey(focus)
        let head: String = "|" + String(selectedRouteID) + "|" + String(ghost.count) + "|"
        let key: String = routeKey + head + destKey + "|" + viaKey + "|" + focusKey + "|f" + String(focusToken)
        if c.key != key {
            c.key = key
            if let old = map.overlays { map.removeOverlays(old) }
            let oldPins = (map.annotations ?? []).compactMap { $0 as? MAPointAnnotation }
            if !oldPins.isEmpty { map.removeAnnotations(oldPins) }

            var pins: [MAPointAnnotation] = []
            for (i, v) in vias.enumerated() {
                let a = MAPointAnnotation(); a.coordinate = v; a.title = "途经 \(i + 1)"; pins.append(a)
            }
            if let d = dest ?? focus {
                let a = MAPointAnnotation(); a.coordinate = d; a.title = "目的地"; pins.append(a)
            }
            if !pins.isEmpty { map.addAnnotations(pins) }

            var lines: [MAPolyline] = []
            func add(_ coords: [CLLocationCoordinate2D], _ kind: String) {
                guard coords.count >= 2 else { return }
                var cc = coords
                if let l = MAPolyline(coordinates: &cc, count: UInt(cc.count)) { l.title = kind; lines.append(l) }
            }
            add(ghost, "ghost")
            for r in routes where r.id != selectedRouteID { add(r.coords, "alt") }
            if let s = routes.first(where: { $0.id == selectedRouteID }) { add(s.coords, "sel") }
            if !lines.isEmpty { map.addOverlays(lines) }
        }

        if c.focusSeq != focusToken {
            c.focusSeq = focusToken
            if let f = focus {
                map.userTrackingMode = MAUserTrackingMode.none
                map.setCenter(f, animated: true)
                map.setZoomLevel(15.5, animated: true)
            }
        }
        if c.recenterSeq != recenterToken {
            c.recenterSeq = recenterToken
            map.userTrackingMode = .follow
            map.setZoomLevel(16, animated: true)
        }
        if c.overviewSeq != overviewToken {
            c.overviewSeq = overviewToken
            if let lines = map.overlays, !lines.isEmpty {
                map.userTrackingMode = MAUserTrackingMode.none
                map.showOverlays(lines, edgePadding: UIEdgeInsets(top: 70, left: 36, bottom: bottomInset + 18, right: 36), animated: false)
            }
        }
    }
}

/// 地图回调：选中路线粉色粗线、备选灰色、分享原路线橙色虚线；目的地红针、途经点紫针。
/// 与工程里的 RouteMapDelegate 同样用运行时登记协议，避开 Swift / 高德 SDK 方法名冲突。
final class HomeMapDelegate: NSObject {
    var key = ""
    var focusSeq = -1
    var recenterSeq = -1
    var overviewSeq = -1

    var asDelegate: MAMapViewDelegate? {
        class_addProtocol(HomeMapDelegate.self, MAMapViewDelegate.self)
        return (self as AnyObject) as? MAMapViewDelegate
    }

    @objc(mapView:viewForAnnotation:)
    func annotationView(_ m: MAMapView, annotation: MAAnnotation) -> MAAnnotationView? {
        guard let a = annotation as? MAPointAnnotation else { return nil }
        let id = "homePin"
        let v = (m.dequeueReusableAnnotationView(withIdentifier: id) as? MAPinAnnotationView) ?? MAPinAnnotationView(annotation: a, reuseIdentifier: id)
        v?.annotation = a
        v?.pinColor = a.title == "目的地" ? .red : .purple
        v?.canShowCallout = false
        return v
    }

    @objc(mapView:rendererForOverlay:)
    func renderer(_ m: MAMapView, overlay: MAOverlay) -> MAOverlayRenderer? {
        guard let pl = overlay as? MAPolyline, let r = MAPolylineRenderer(polyline: pl) else { return nil }
        r.lineJoinType = kMALineJoinRound
        r.lineCapType = kMALineCapRound
        switch pl.title {
        case "sel":
            r.strokeColor = UIColor(red: 1, green: 0.31, blue: 0.71, alpha: 1); r.lineWidth = 8
        case "ghost":
            r.strokeColor = UIColor(red: 1, green: 0.62, blue: 0.15, alpha: 0.95); r.lineWidth = 4
            r.lineDashType = kMALineDashTypeSquare
        default:
            r.strokeColor = UIColor(white: 0.6, alpha: 0.7); r.lineWidth = 6
        }
        return r
    }
}

// MARK: - 车牌与限行设置

/// 填一次车牌，之后每次点「路线」都会把车牌交给高德，自动规避当日限行。
/// 高德接口：AMapNaviVehicleInfo.vehicleId + isETARestriction + type → AMapNaviDriveManager.setVehicleInfo()
struct PlateSetupView: View {
    @ObservedObject private var settings = Settings.shared
    @Environment(\.presentationMode) private var presentationMode
    @State private var draft = ""
    @State private var vehicleType = 0
    @State private var avoid = true
    @State private var note = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CardView {
                        Text("车牌号").foregroundColor(.white).bold()
                        TextField("例如 京A12345 / 京AD12345", text: $draft)
                            .textFieldStyle(.plain)
                            .font(.title3.monospaced())
                            .foregroundColor(.white)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(ContentView.bg))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ContentView.stroke, lineWidth: 1))
                        Text("普通车牌 7 位、新能源车牌 8 位；会自动去掉空格和标点、把字母转成大写。")
                            .font(.caption).foregroundColor(ContentView.sub)
                        Text("点一下选省份，后面直接填字母和数字").font(.caption2).foregroundColor(ContentView.sub)
                        provinceChips
                    }

                    CardView {
                        Text("车辆类型").foregroundColor(.white).bold()
                        HStack(spacing: 8) {
                            ForEach(Settings.vehicleTypes) { v in
                                Button { vehicleType = v.code } label: {
                                    Text(v.name).font(.caption)
                                        .foregroundColor(vehicleType == v.code ? .white : ContentView.sub)
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .background(Capsule().fill(vehicleType == v.code ? ContentView.pink : ContentView.bg))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("新能源车牌请选「纯电客车」或「插混客车」，否则尾号限行可能判断不准。")
                            .font(.caption).foregroundColor(ContentView.sub)
                    }

                    CardView {
                        Toggle("规划路线时避开限行", isOn: $avoid)
                            .font(.subheadline).foregroundColor(.white).tint(ContentView.pink)
                        Text("开启后，每次规划路线都会把车牌传给高德，绕开当日尾号限行、外地牌限行等路段；改完已有路线会立刻重算。")
                            .font(.caption).foregroundColor(ContentView.sub)
                        Text("限行数据以高德为准。各地禁摩规则与汽车尾号限行不同，本功能按小客车规则处理，请以现场交通标志为准。")
                            .font(.caption2).foregroundColor(ContentView.sub)
                    }

                    if !note.isEmpty { Text(note).font(.caption).foregroundColor(.orange) }

                    if !settings.plateNumber.isEmpty {
                        Button {
                            settings.plateNumber = ""
                            settings.applyVehicleSettings()
                            presentationMode.wrappedValue.dismiss()
                        } label: {
                            Text("清除车牌").font(.subheadline).foregroundColor(.orange)
                        }
                    }
                }
                .padding(16)
            }
            .background(ContentView.bg.ignoresSafeArea())
            .navigationTitle("车牌与限行")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                        .foregroundColor(ContentView.sub)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }.foregroundColor(ContentView.pink)
                }
            }
        }
        .onAppear {
            draft = settings.plateNumber
            vehicleType = settings.vehicleType
            avoid = settings.avoidRestriction
        }
    }

    private var currentProvince: String {
        guard let f = Settings.normalizedPlate(draft).first else { return "" }
        return String(f)
    }

    /// 省份简称快捷按钮：点一下替换车牌首字，省得切中文键盘
    private var provinceChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], spacing: 6) {
            ForEach(Settings.plateProvinces, id: \.self) { p in
                Button {
                    let body = Settings.normalizedPlate(draft)
                    let tail = Settings.plateProvinces.contains(currentProvince) ? String(body.dropFirst()) : body
                    draft = p + tail
                } label: {
                    Text(p).font(.subheadline)
                        .foregroundColor(currentProvince == p ? .white : ContentView.sub)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(currentProvince == p ? ContentView.pink : ContentView.bg))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func save() {
        let p = Settings.normalizedPlate(draft)
        if !p.isEmpty && !Settings.plateValid(p) {
            note = "车牌格式不对：省份简称 + 发牌机关字母 + 5 或 6 位序号，例如 京A12345、京AD12345"
            return
        }
        settings.plateNumber = p
        settings.vehicleType = vehicleType
        settings.avoidRestriction = avoid
        settings.applyVehicleSettings()
        presentationMode.wrappedValue.dismiss()
    }
}
