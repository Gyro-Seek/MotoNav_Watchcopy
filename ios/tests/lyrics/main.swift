import Foundation
var checks = 0
func check(_ p: Bool, _ message: String) { precondition(p, message); checks += 1 }
let synthetic = "[ar:测试歌手]\n[ti:测试歌]\n[00:01.00]测试第一行\n[00:02.5][00:04.500]测试重复行\n[00:06.00]\n[00:07:125]测试末行"
let lrc = LyricsTimeline(synthetic)
check(lrc.cues.count == 5, "multiple timestamps and blank clear")
check(lrc.line(at: 0.99).isEmpty, "no early lyrics")
check(lrc.line(at: 1) == "测试第一行", "timestamp boundary")
check(lrc.line(at: 2.49) == "测试第一行", "keep previous line")
check(lrc.line(at: 2.5) == "测试重复行", "tenths")
check(lrc.line(at: 4.5) == "测试重复行", "millisecond timestamp")
check(lrc.line(at: 6).isEmpty, "instrumental break clears line")
check(lrc.line(at: 7.125) == "测试末行", "colon millisecond timestamp")
check(lrc.line(at: -1).isEmpty && lrc.line(at: .nan).isEmpty, "invalid positions")
let offset = LyricsTimeline("[offset:-500]\n[00:01.00]偏移测试")
check(offset.line(at: 0.49).isEmpty && offset.line(at: 0.5) == "偏移测试", "negative offset")
let merged = LyricsTimeline("[00:03.00]测试后行\n[00:01.00]测试原文\n[00:01.00]测试译文\n[00:01.00]测试原文")
check(merged.cues.count == 2, "sort and combine translations")
check(merged.line(at: 1) == "测试原文 / 测试译文", "deduplicate")
check(LyricsTimeline("[ar:test]\nplain unsynced text\n[00:99.00]bad\n[00:nan]bad").cues.isEmpty, "unsynced and malformed ignored")
check(LyricsTimeline(String(repeating: "a", count: 128 * 1024 + 1)).cues.isEmpty, "bound parser input")
let paused = MediaPlaybackClock("0,1.0,12", now: 100)!
check(paused.position(now: 200, duration: 180) == 12, "paused even stale rate")
let playing = MediaPlaybackClock("1,1.0,12", now: 100)!
check(playing.position(now: 105, duration: 180) == 17, "monotonic progress")
check(playing.position(now: 300, duration: 180) == 180, "clamp end")
check(playing.position(now: 90, duration: 180) == 12, "clock backwards")
let rewind = MediaPlaybackClock("2,-2,12", now: 100)!
check(rewind.position(now: 107, duration: 180) == 0, "rewind clamped")
for text in ["", "4,1,0", "1,nan,0", "1,1,-1", "1,1,0,2"] { check(MediaPlaybackClock(text, now: 0) == nil, "invalid clock") }
let track = LyricsTrack(title: "测试歌曲 & Live", artist: "测试歌手", album: "测试专辑", duration: 180.5)
let query = URLComponents(url: track.url!, resolvingAgainstBaseURL: false)!.queryItems!
check(query.first(where: { $0.name == "track_name" })?.value == track.title, "unicode and ampersand query safe")
check(track.matches(title: track.title, artist: track.artist, album: track.album, duration: 182), "duration tolerance")
check(!track.matches(title: track.title, artist: track.artist, album: track.album, duration: 190), "wrong song version")
check(!track.matches(title: track.title, artist: "别的歌手", album: track.album, duration: 180), "wrong artist")
check(!track.matches(title: track.title, artist: track.artist, album: "别的专辑", duration: 180), "wrong album")
check(!track.matches(title: "别的歌", artist: track.artist, album: track.album, duration: 180), "wrong title")
check(LyricsTrack(title: "", artist: "x", album: "", duration: 10).url == nil, "wait for track")
check(LyricsTrack(title: "x", artist: "y", album: "", duration: .nan).url == nil, "invalid duration")
print("Synced lyrics: \(checks) checks passed")
