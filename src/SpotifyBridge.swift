import Foundation
import SwiftUI

/// SpotifyBridge — Now Playing temps réel via AppleScript + DistributedNotificationCenter
/// Listens to "com.spotify.client.PlaybackState" notifications for zero-polling updates.
final class SpotifyBridge: ObservableObject {
    // MARK: - Published state
    @Published private(set) var track: SpotifyTrack?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isSpotifyRunning: Bool = false
    
    // MARK: - Polling timer (fallback if notifications fail)
    private var pollingTimer: Timer?
    private var notificationObserver: NSObjectProtocol?
    private let pollInterval: TimeInterval = 2.0
    
    // MARK: - Lifecycle
    init() {
        checkAndListen()
    }
    
    deinit {
        tearDown()
    }
    
    // MARK: - Setup
    private func checkAndListen() {
        // 1. Vérifier que Spotify est installé
        guard isSpotifyInstalled else {
            isSpotifyRunning = false
            track = nil
            return
        }
        
        isSpotifyRunning = true
        
        // 2. Écouter les notifications Spotify (zero-polling primary channel)
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackState"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshNowPlaying()
        }
        
        // 3. Fallback polling timer (au cas où notifications ne firent pas)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.refreshNowPlaying()
        }
        
        // 4. Refresh initial
        refreshNowPlaying()
    }
    
    var isSpotifyInstalled: Bool {
        return FileManager.default.fileExists(atPath: "/Applications/Spotify.app/Contents/MacOS/Spotify")
    }
    
    // MARK: - AppleScript: Now Playing
    func refreshNowPlaying() {
        guard isSpotifyInstalled else { return }
        
        let script = """
        tell application "Spotify"
            try
                set t to name of current track
                set a to artist of current track
                set al to album of current track
                set d to duration of current track
                set p to player position
                set s to player state
                return t & "||" & a & "||" & al & "||" & d & "||" & p & "||" & s
            on error
                return "|||||||||STOPPED"
            end try
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let `self` = self else { return }
            let output = self.runAppleScript(script)
            let resultString = output?.stringValue ?? "|||||||||STOPPED"
            let parts = resultString.components(separatedBy: "||")
            
            var title: String = ""
            var artist: String = ""
            var album: String = ""
            var duration: Int = 0
            var position: Int = 0
            var state: String = "STOPPED"
            
            if parts.count >= 6 {
                title = parts[0]
                artist = parts[1]
                album = parts[2]
                duration = Int(Double(parts[3] ?? "0") ?? 0)
                position = Int(Double(parts[4] ?? "0") ?? 0)
                state = parts[5].uppercased()
            }
            
            // Convertir position en ms (AppleScript retourne en secondes)
            let positionMs = Int(Double(position) * 1000)
            let durationMs = Int(Double(duration) * 1000)
            
            let track = SpotifyTrack(
                title: title,
                artist: artist,
                album: album,
                durationMs: durationMs,
                positionMs: positionMs,
                state: state
            )
            
            DispatchQueue.main.async {
                self.track = track
                self.isPlaying = (state == "PLAYING")
            }
        }
    }
    
    // MARK: - AppleScript: Controls
    @discardableResult
    private func runAppleScript(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if let err = error {
            #if DEBUG
            print("SpotifyBridge AppleScript error: \(err)")
            #endif
        }
        return output
    }
    
    // MARK: - Control Methods
    func playPause() {
        runAppleScript("tell application \"Spotify\" to playpause")
    }
    
    func nextTrack() {
        runAppleScript("tell application \"Spotify\" to next track")
    }
    
    func previousTrack() {
        runAppleScript("tell application \"Spotify\" to previous track")
    }
    
    func setVolume(_ level: Double) {
        let clampedLevel = max(0.0, min(100.0, level))
        runAppleScript("tell application \"Spotify\" to set sound volume to \(Int(clampedLevel))")
    }
    
    func seekTo(_ positionSeconds: Double) {
        runAppleScript("tell application \"Spotify\" to set player position to \(Int(positionSeconds))")
    }
    
    // MARK: - Teardown
    private func tearDown() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        
        if let observer = notificationObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            notificationObserver = nil
        }
    }
}

// MARK: - SpotifyTrack Model
struct SpotifyTrack: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let artist: String
    let album: String
    let durationMs: Int
    let positionMs: Int
    let state: String  // "PLAYING" / "PAUSED" / "STOPPED"
    
    var progress: Double {
        guard durationMs > 0 else { return 0.0 }
        return Double(positionMs) / Double(durationMs)
    }
    
    var formattedCurrentTime: String {
        let totalSec = positionMs / 1000
        let min = totalSec / 60
        let sec = totalSec % 60
        return String(format: "%d:%02d", min, sec)
    }
    
    var formattedTotalTime: String {
        let totalSec = durationMs / 1000
        let min = totalSec / 60
        let sec = totalSec % 60
        return String(format: "%d:%02d", min, sec)
    }
    
    var displayName: String {
        if artist.isEmpty { return title }
        return "\(title) — \(artist)"
    }
}

// MARK: - Spotify NowPlaying View (SwiftUI)
struct SpotifyNowPlayingView: View {
    @ObservedObject var bridge: SpotifyBridge
    
    var body: some View {
        if let track = bridge.track, track.title.isEmpty == false {
            VStack(alignment: .leading, spacing: 6) {
                // Track info
                Text(track.displayName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(track.album.isEmpty ? "" : track.album)
                    .font(.system(size: 9.5, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
                
                // Progress bar
                ProgressView(value: track.progress)
                    .tint(bridge.isPlaying ? Color(red: 0.188, green: 0.820, blue: 0.345) : .white.opacity(0.3))
                    .progressViewStyle(.linear)
                
                // Controls & time
                HStack(spacing: 12) {
                    Text(track.formattedCurrentTime)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                    
                    Spacer()
                    
                    HStack(spacing: 14) {
                        Button(action: { bridge.previousTrack() }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: { bridge.playPause() }) {
                            Image(systemName: bridge.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: { bridge.nextTrack() }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text(track.formattedTotalTime)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } else if !bridge.isSpotifyRunning {
            Text("Spotify non installé")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
        } else {
            Text("Aucune lecture en cours")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
        }
    }
}
