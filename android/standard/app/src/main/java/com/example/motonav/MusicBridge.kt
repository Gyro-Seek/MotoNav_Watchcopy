package com.example.motonav

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.KeyEvent

/** 通过系统媒体会话同步歌曲、遥控播放，不传输音频。 */
object MusicBridge {
    private val handler = Handler(Looper.getMainLooper())
    private var ctx: Context? = null
    private var controllers = emptyList<MediaController>()
    private var current: MediaController? = null
    private var lastText = ""
    private var lastState = ""
    @Volatile var info = "等待圆屏音乐操作"
    private var operation = 0
    private var coverRetrySeq = 0
    private var lastToggleTime = 0L
    private var lastTrackSkipTime = 0L
    private val callback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) { publish() }
        override fun onPlaybackStateChanged(state: PlaybackState?) { publish() }
        override fun onSessionDestroyed() { refresh() }
    }
    fun init(context: Context) {
        if (ctx != null) return
        ctx = context.applicationContext
        handler.post(object : Runnable {
            override fun run() { refresh(); handler.postDelayed(this, 1500) }
        })
    }
    fun refresh(force: Boolean = false) {
        if (Looper.myLooper() != Looper.getMainLooper()) { handler.post { refresh(force) }; return }
        val c = ctx ?: return
        val next = if (!AmapProbe.notifEnabled(c)) emptyList() else try {
            val msm = c.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            msm.getActiveSessions(ComponentName(c, AmapNotifyListener::class.java)).filter { it.packageName != c.packageName }
        } catch (_: SecurityException) { emptyList() }
        if (controllers.map { it.sessionToken } != next.map { it.sessionToken }) {
            controllers.forEach { try { it.unregisterCallback(callback) } catch (_: Exception) {} }
            controllers = next
            controllers.forEach { try { it.registerCallback(callback, handler) } catch (_: Exception) {} }
        }
        publish(force)
    }
    private fun publish(force: Boolean = false) {
        val c = ctx ?: return
        current = controllers.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
            ?: controllers.firstOrNull { it.sessionToken == current?.sessionToken } ?: controllers.firstOrNull()
        val mc = current
        val meta = mc?.metadata
        val title = meta?.getString(MediaMetadata.METADATA_KEY_TITLE)?.takeIf { it.isNotBlank() }
            ?: meta?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)?.takeIf { it.isNotBlank() }
            ?: if (mc != null) "未知歌曲" else if (AmapProbe.notifEnabled(c)) "暂无音乐播放" else "请开启 MotoNav 通知使用权"
        val artist = meta?.getString(MediaMetadata.METADATA_KEY_ARTIST)?.takeIf { it.isNotBlank() }
            ?: meta?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)?.takeIf { it.isNotBlank() } ?: ""
        val state = mc?.playbackState
        val playing = state?.state == PlaybackState.STATE_PLAYING
        // 部分播放器漏报 actions；允许发标准媒体按键，不按这些位禁用按钮。
        val mask = if (mc != null) 7 else 0
        val durMs = meta?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: -1L
        val posMs = state?.position ?: -1L
        val durSec = if (durMs > 0) (durMs / 1000).toInt() else 0
        val posSec = if (posMs >= 0) (posMs / 1000).toInt() else 0
        val status = "#Z,${if (mc != null) 1 else 0},${if (playing) 1 else 0},$mask,$durSec,$posSec"
        if (force || lastText != "$title\n$artist") {
            lastText = "$title\n$artist"
            for ((slot, text) in listOf(5 to title, 6 to artist)) {
                val image = TextImage.render(text.take(200), 360, if (slot == 5) 32f else 24f)
                BleLink.sendImage(slot, image?.w ?: 0, image?.h ?: 0, image?.data ?: byteArrayOf())
            }
        }
        syncCover(mc, meta, c, force)
        if (force || lastState != status) { lastState = status; BleLink.send(status) }
    }

    private fun syncCover(mc: MediaController?, meta: MediaMetadata?, context: Context, force: Boolean) {
        if (mc == null || meta == null) {
            CoverFeeder.clearCover()
            return
        }
        val tKey = track(mc)
        val memBmp = try {
            meta.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                ?: meta.getBitmap(MediaMetadata.METADATA_KEY_ART)
        } catch (_: Throwable) { null }
        if (memBmp != null && !memBmp.isRecycled) {
            CoverFeeder.feedCover(memBmp, "$tKey#${memBmp.generationId}", force)
            return
        }
        val uriStr = meta.getString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI)
            ?: meta.getString(MediaMetadata.METADATA_KEY_ART_URI)
        if (!uriStr.isNullOrBlank() && (uriStr.startsWith("content://") || uriStr.startsWith("file://"))) {
            val covKey = "$tKey#$uriStr"
            if (!force && !CoverFeeder.needsCover(covKey)) return
            val decoded = try {
                context.contentResolver.openInputStream(android.net.Uri.parse(uriStr))?.use {
                    android.graphics.BitmapFactory.decodeStream(it)
                }
            } catch (_: Throwable) { null }
            if (decoded != null) {
                CoverFeeder.feedCover(decoded, covKey, force)
                decoded.recycle()
                return
            }
        }
        // 切歌时如果当前曲目还没加载完封面，延时重试等异步网络封面返回
        if (CoverFeeder.needsCover(tKey)) {
            val retrySeq = ++coverRetrySeq
            handler.postDelayed({ if (coverRetrySeq == retrySeq) refresh() }, 600)
            handler.postDelayed({ if (coverRetrySeq == retrySeq) refresh() }, 1500)
        } else {
            CoverFeeder.clearCover()
        }
    }

    private fun track(mc: MediaController): String {
        val m = mc.metadata
        return listOf(MediaMetadata.METADATA_KEY_MEDIA_ID, MediaMetadata.METADATA_KEY_TITLE,
            MediaMetadata.METADATA_KEY_ARTIST, MediaMetadata.METADATA_KEY_ALBUM).joinToString("|") { m?.getString(it) ?: "" }
    }

    fun onScreenEvent(action: String, touchInfo: String = "") {
        handler.post {
            if (action == "H") { info = "触摸未命中按钮：$touchInfo"; return@post }
            refresh(action == "Q")
            if (action == "Q") return@post
            if (action == "V") {
                val vol = touchInfo.toIntOrNull() ?: return@post
                val am = ctx?.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
                if (am != null) {
                    val max = am.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
                    val target = ((vol.coerceIn(0, 100) * max) / 100f).toInt()
                    am.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, target, android.media.AudioManager.FLAG_SHOW_UI)
                    info = "已同步音量：${vol}% (阶数 $target/$max)"
                }
                return@post
            }
            if (action == "L") {
                val mc = current
                if (mc == null) { info = "收到喜欢/收藏操作，但没有可控制的播放器"; BleLink.sendEvent("#ZACK,5"); return@post }
                val liked = touchInfo == "1"
                info = "收到喜欢/收藏操作：${if (liked) "点赞" else "取消点赞"} · ${mc.packageName}"
                BleLink.sendEvent("#ZACK,2")
                try {
                    // 1. 尝试匹配播放器在 PlaybackState 中声明的 CustomAction (网易云/QQ音乐/Spotify等)
                    mc.playbackState?.customActions?.forEach { act ->
                        val a = act.action.lowercase()
                        val n = act.name?.toString()?.lowercase() ?: ""
                        if (a.contains("like") || a.contains("fav") || a.contains("heart") || a.contains("love") ||
                            n.contains("like") || n.contains("fav") || n.contains("喜欢") || n.contains("收藏") || n.contains("红心")) {
                            mc.transportControls.sendCustomAction(act.action, act.extras)
                            info += " · 动作(${act.name ?: act.action})"
                        }
                    }
                    // 2. 尝试标准系统 Rating
                    mc.transportControls.setRating(android.media.Rating.newHeartRating(liked))
                    mc.transportControls.setRating(android.media.Rating.newThumbRating(liked))

                    // 3. 常见各大播放器内置私有 action
                    val commonActions = listOf(
                        "com.netease.cloudmusic.action_like", "action_like", "action_favorite",
                        "ACTION_FAVORITE", "ACTION_LIKE", "toggle_favorite", "toggle_like", "like", "favorite"
                    )
                    for (ca in commonActions) {
                        try { mc.transportControls.sendCustomAction(ca, null) } catch (_: Exception) {}
                    }
                    // 4. 通过 NotificationListenerService 触发通知栏上的“喜欢”动作 (最高保真度)
                    try {
                        val sbn = AmapNotifyListener.instance?.activeNotifications?.firstOrNull { it.packageName == mc.packageName }
                        val notif = sbn?.notification
                        notif?.actions?.forEach { nAct ->
                            val t = nAct.title?.toString()?.lowercase() ?: ""
                            if (t.contains("like") || t.contains("fav") || t.contains("喜欢") || t.contains("收藏") || t.contains("红心")) {
                                nAct.actionIntent?.send()
                                info += " · 通知栏动作(${nAct.title})"
                            }
                        }
                    } catch (_: Exception) {}
                    // 5. 广播兜底 (网易云音乐)
                    if (mc.packageName == "com.netease.cloudmusic") {
                        try {
                            ctx?.sendBroadcast(android.content.Intent("com.netease.cloudmusic.musicpost.like").setPackage("com.netease.cloudmusic"))
                        } catch (_: Exception) {}
                    }
                    BleLink.sendEvent("#ZACK,3")
                } catch (e: Exception) {
                    BleLink.sendEvent("#ZACK,4")
                }
                refresh(true)
                return@post
            }
            if (action == "R") {
                val mc = current
                if (mc == null) { info = "收到循环模式切换，但没有可控制的播放器"; BleLink.sendEvent("#ZACK,5"); return@post }
                val targetMode = touchInfo.toIntOrNull() ?: 0
                val modeDesc = when (targetMode) { 1 -> "单曲循环"; 2 -> "随机播放"; else -> "列表循环" }
                info = "切换循环模式为 $modeDesc · ${mc.packageName}"
                BleLink.sendEvent("#ZACK,2")
                try {
                    val tc = mc.transportControls
                    val repeatVal = if (targetMode == 1) 1 else 2 // 1: ONE, 2: ALL
                    try {
                        val mSetRepeat = tc.javaClass.getMethod("setRepeatMode", Int::class.javaPrimitiveType)
                        mSetRepeat.invoke(tc, repeatVal)
                    } catch (_: Exception) {}
                    try {
                        val shuffleVal = if (targetMode == 2) 1 else 0 // 1: ALL, 0: NONE
                        val mSetShuffle = tc.javaClass.getMethod("setShuffleMode", Int::class.javaPrimitiveType)
                        mSetShuffle.invoke(tc, shuffleVal)
                    } catch (_: Exception) {}
                    val customRepeatActions = listOf("cycleRepeatMode", "repeat", "shuffle", "toggle_repeat", "toggle_shuffle")
                    for (ca in customRepeatActions) {
                        try { tc.sendCustomAction(ca, null) } catch (_: Exception) {}
                    }
                    mc.playbackState?.customActions?.forEach { act ->
                        val a = act.action.lowercase()
                        val n = act.name?.toString()?.lowercase() ?: ""
                        if (a.contains("repeat") || a.contains("shuffle") || a.contains("loop") ||
                            n.contains("循环") || n.contains("随机")) {
                            try { tc.sendCustomAction(act.action, act.extras) } catch (_: Exception) {}
                        }
                    }
                    BleLink.sendEvent("#ZACK,3")
                } catch (e: Exception) {
                    BleLink.sendEvent("#ZACK,4")
                }
                refresh(true)
                return@post
            }
            if (action !in listOf("P", "N", "T")) return@post
            val nowMs = SystemClock.uptimeMillis()
            if (action == "T") {
                if (nowMs - lastToggleTime < 600L) {
                    info = "忽略快速重复播放/暂停指令"
                    return@post
                }
                lastToggleTime = nowMs
            } else if (action in listOf("P", "N")) {
                if (nowMs - lastTrackSkipTime < 500L) {
                    info = "忽略快速重复切歌指令"
                    return@post
                }
                lastTrackSkipTime = nowMs
            }
            val mc = current
            if (mc == null) { info = "收到 $action，但没有可控制的播放器"; BleLink.sendEvent("#ZACK,5"); return@post }
            val beforeTrack = track(mc)
            val beforePosition = mc.playbackState?.position ?: -1L
            val beforePlaying = mc.playbackState?.state == PlaybackState.STATE_PLAYING
            val op = ++operation
            val name = when (action) { "P" -> "上一首"; "N" -> "下一首"; else -> "播放/暂停" }
            info = "收到$name · ${mc.packageName} · 触摸 $touchInfo"
            BleLink.sendEvent("#ZACK,2")
            try {
                if (action == "T") {
                    // 播放/暂停优先直接调用 TransportControls，绝对精准，杜绝被手机系统线控误当作双击切歌
                    if (beforePlaying) mc.transportControls.pause() else mc.transportControls.play()
                    info += " · 会话控制"
                } else {
                    val code = when (action) {
                        "P" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                        else -> KeyEvent.KEYCODE_MEDIA_NEXT
                    }
                    val now = SystemClock.uptimeMillis()
                    // 成对发送按下和抬起；发往所选会话，避免控制到别的播放器。
                    val down = mc.dispatchMediaButtonEvent(KeyEvent(now, now, KeyEvent.ACTION_DOWN, code, 0))
                    val up = mc.dispatchMediaButtonEvent(KeyEvent(now, SystemClock.uptimeMillis(), KeyEvent.ACTION_UP, code, 0))
                    if (!down && !up) {
                        if (action == "P") mc.transportControls.skipToPrevious() else mc.transportControls.skipToNext()
                        info += " · 会话控制"
                    } else info += " · 媒体按键"
                }
                fun check(attempt: Int) {
                    if (operation != op) return
                    val after = mc.playbackState
                    val changed = if (action == "T")
                        after != null && (if (beforePlaying) (after.state == PlaybackState.STATE_PAUSED || after.state == PlaybackState.STATE_STOPPED) else after.state == PlaybackState.STATE_PLAYING)
                    else track(mc) != beforeTrack ||
                        (beforePosition > 2000 && after != null && after.position >= 0 && after.position < beforePosition - 1500)
                    if (changed) {
                        info += " · 播放器已响应"
                        BleLink.sendEvent("#ZACK,3")
                        refresh(true)
                    } else if (attempt < 5) handler.postDelayed({ check(attempt + 1) }, 300)
                    else {
                        info += " · 已发送，但未收到播放器状态变化"
                        BleLink.sendEvent("#ZACK,4")
                        refresh(true)
                    }
                }
                handler.postDelayed({ check(0) }, 300)
            } catch (e: Exception) {
                info += " · 控制失败：${e.javaClass.simpleName}"
                BleLink.sendEvent("#ZACK,4")
                refresh(true)
            }
        }
    }
}
