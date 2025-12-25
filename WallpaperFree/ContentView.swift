//
//  WallpaperFreeApp.swift
//  WallpaperFree
//
//  Created by TAKAMURA on 25.12.2025.
//

import SwiftUI
import AppKit
import AVKit
import WebKit
import Combine
import AVFoundation

// MARK: - Models

struct VideoFile: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let path: String
    
    var url: URL {
        URL(fileURLWithPath: path)
    }
    
    init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
    
    init(url: URL) {
        self.id = UUID()
        self.name = url.lastPathComponent
        self.path = url.path
    }
    
}

struct ScreenSettings: Codable {
    var videoFileID: UUID?
    var isEnabled: Bool
}

// MARK: - Settings Manager

class SettingsManager: ObservableObject {
    @Published var videoLibrary: [VideoFile] = []
    @Published var screenSettings: [String: ScreenSettings] = [:]
    
    private let libraryKey = "videoLibrary"
    private let settingsKey = "screenSettings"
    
    init() {
        loadSettings()
    }
    
    func saveSettings() {
        if let encoded = try? JSONEncoder().encode(videoLibrary) {
            UserDefaults.standard.set(encoded, forKey: libraryKey)
        }
        if let encoded = try? JSONEncoder().encode(screenSettings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
    }
    
    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: libraryKey),
           let decoded = try? JSONDecoder().decode([VideoFile].self, from: data) {
            videoLibrary = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode([String: ScreenSettings].self, from: data) {
            screenSettings = decoded
        }
    }
    
    func addVideoFile(url: URL) {
        let file = VideoFile(url: url)
        if !videoLibrary.contains(where: { $0.path == file.path }) {
            videoLibrary.append(file)
            saveSettings()
        }
    }
    
    func generateThumbnailAsync(url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        
        do {
            let (cgImage, _) = try await generator.image(at: time)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            print("Error: \(error)")
            return nil
        }
    }
    
    func removeVideoFile(_ file: VideoFile) {
        videoLibrary.removeAll { $0.id == file.id }
        for (key, var setting) in screenSettings {
            if setting.videoFileID == file.id {
                setting.videoFileID = nil
                setting.isEnabled = false
                screenSettings[key] = setting
            }
        }
        saveSettings()
    }
    
    func getSettings(for screen: NSScreen) -> ScreenSettings {
        let key = screenIdentifier(for: screen)
        return screenSettings[key] ?? ScreenSettings(videoFileID: nil, isEnabled: false)
    }
    
    func updateSettings(for screen: NSScreen, settings: ScreenSettings) {
        let key = screenIdentifier(for: screen)
        screenSettings[key] = settings
        saveSettings()
    }
    
    func screenIdentifier(for screen: NSScreen) -> String {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "screen_\(screenNumber)"
        }
        return "\(screen.frame.width)x\(screen.frame.height)_\(screen.frame.origin.x)_\(screen.frame.origin.y)"
    }
}

// MARK: - Window Management

class WallpaperWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Engine

class WallpaperEngine: NSObject, ObservableObject {
    @Published var videoVolume: Double = 1.0 {
        didSet {
            for player in activePlayers.values {
                player.volume = Float(videoVolume)
            }
            UserDefaults.standard.set(videoVolume, forKey: "videoVolume")
        }
    }
    
    private var activeWindows: [String: NSWindow] = [:]
    private var activePlayers: [String: AVQueuePlayer] = [:]
    private var activeLoopers: [String: AVPlayerLooper] = [:]
    
    private var screenObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    
    override init() {
        super.init()
        
        let savedVolume = UserDefaults.standard.double(forKey: "videoVolume")
        videoVolume = savedVolume > 0 ? savedVolume : 1.0
        
        setupObservers()
    }
    
    deinit {
        removeObservers()
    }
    
    private func setupObservers() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("Screen configuration changed")
            self?.handleScreenChange()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("System woke from sleep")
            self?.handleWakeFromSleep()
        }
    }
    
    private func removeObservers() {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    
    private func handleScreenChange() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.reapplyWindows()
        }
    }
    
    private func handleWakeFromSleep() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.reapplyWindows()
        }
    }
    
    private func reapplyWindows() {
        var screenVideoMap: [(String, URL)] = []
        
        for (screenId, player) in activePlayers {
            if let currentItem = player.currentItem,
               let asset = currentItem.asset as? AVURLAsset {
                screenVideoMap.append((screenId, asset.url))
            }
        }
        
        for screenId in Array(activeWindows.keys) {
            stopWallpaper(forScreenId: screenId)
        }
        
        for (screenId, url) in screenVideoMap {
            if let screen = NSScreen.screens.first(where: { screenIdentifier($0) == screenId }) {
                setVideo(url: url, for: screen)
            }
        }
    }
    
    private func screenIdentifier(_ screen: NSScreen) -> String {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "screen_\(screenNumber)"
        }
        return "\(screen.frame.width)x\(screen.frame.height)_\(screen.frame.origin.x)_\(screen.frame.origin.y)"
    }
    
    private func createWindow(on screen: NSScreen) -> NSWindow {

        var windowFrame = screen.frame
        
        if screen == NSScreen.main {
           let menuBarHeight = screen.frame.height - screen.visibleFrame.height - screen.visibleFrame.origin.y
           windowFrame.origin.y += menuBarHeight
           windowFrame.size.height -= menuBarHeight
       }
        
        let window = WallpaperWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        window.setFrame(windowFrame, display: true)
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.backgroundColor = .black
        window.isOpaque = true
        window.ignoresMouseEvents = true
        
        window.orderBack(nil)
        return window
    }
    
    func setVideo(url: URL, for screen: NSScreen) {
        let screenId = screenIdentifier(screen)
        stopWallpaper(forScreenId: screenId)
        
        print("Setting video for screen: \(screenId)")
        
        let window = createWindow(on: screen)
        
        let playerItem = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        
        queuePlayer.volume = Float(videoVolume)
        
        let playerLayer = AVPlayerLayer(player: queuePlayer)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = window.contentView!.bounds
        
        window.contentView?.wantsLayer = true
        window.contentView?.layer = CALayer()
        window.contentView?.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView?.layer?.addSublayer(playerLayer)
        
        activeWindows[screenId] = window
        activePlayers[screenId] = queuePlayer
        activeLoopers[screenId] = looper
        
        queuePlayer.play()
    }
    
    func stopWallpaper(for screen: NSScreen) {
        let screenId = screenIdentifier(screen)
        stopWallpaper(forScreenId: screenId)
    }
    
    private func stopWallpaper(forScreenId screenId: String) {
        if let window = activeWindows[screenId] {
            window.orderOut(nil)
            activeWindows.removeValue(forKey: screenId)
        }
        
        if let player = activePlayers[screenId] {
            player.pause()
            activePlayers.removeValue(forKey: screenId)
        }
        
        activeLoopers.removeValue(forKey: screenId)
    }
    
    func isRunning(on screen: NSScreen) -> Bool {
        let screenId = screenIdentifier(screen)
        return activeWindows[screenId] != nil
    }
    
    func stopAll() {
        for screenId in Array(activeWindows.keys) {
            stopWallpaper(forScreenId: screenId)
        }
    }
}

// MARK: - UI Components
struct VideoCardView: View {
    @StateObject private var settings = SettingsManager()
    let file: VideoFile
    let onRemove: () -> Void
    @State private var thumbnail: NSImage?
    @State private var isHovering = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.black.opacity(0.2)
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .frame(height: 100)
            .frame(maxWidth: .infinity)
            .clipped()
            .background(Color.black)

            VStack {
                Spacer()
                LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
                    .frame(height: 40)
            }
            
            VStack {
                Spacer()
                Text(file.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.5).clipShape(Circle()))
                }
                .buttonStyle(.plain)
                .padding(6)
                .transition(.opacity.animation(.easeInOut(duration: 0.1)))
            }
        }
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovering ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hover
            }
        }
        .task {
            if thumbnail == nil {
                thumbnail = await settings.generateThumbnailAsync(url: file.url)
            }
        }
    }
}

struct VideoLibraryView: View {
    @Binding var library: [VideoFile]
    
    let onAdd: () -> Void
    let onRemove: (VideoFile) -> Void
    
    let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("My Collection")
                    .font(.title3)
                    .bold()
                
                Spacer()
                
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus")
                }
                .controlSize(.regular)
            }
            .padding(.horizontal)
            
            Divider()
            
            ScrollView {
                if library.isEmpty {
                    VStack(spacing: 15) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 40))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("Empty...")
                            .foregroundColor(.secondary)
                        
                        Button("Let's add first one!", action: onAdd)
                            .buttonStyle(.link)
                    }
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(library) { file in
                            VideoCardView(
                                file: file,
                                onRemove: { onRemove(file) }
                            )
                        }
                    }
                    .padding()
                }
            }
//            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .padding(0)
        }
    }
}

struct ScreenRowView: View {
    let screen: NSScreen
    @Binding var isEnabled: Bool
    @Binding var selectedVideoID: UUID?
    let videoLibrary: [VideoFile]
    let onToggle: (Bool) -> Void
    let onVideoChange: (UUID?) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "display")
                    .foregroundColor(.blue)
                
                Text(screen.localizedName)
                    .font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        onToggle(newValue)
                    }
                ))
                .toggleStyle(.switch)
                .disabled(videoLibrary.isEmpty || selectedVideoID == nil)
            }
            Picker("Video", selection: Binding(
                get: { selectedVideoID },
                set: { newValue in
                    onVideoChange(newValue)
                }
            )) {
                Text("Select video...")
                    .tag(nil as UUID?)
                
                ForEach(videoLibrary) { file in
                    Text(file.name)
                        .tag(file.id as UUID?)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(8)
    }
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var engine = WallpaperEngine()
    @StateObject private var settings = SettingsManager()
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Monitor Manager")
                .font(.title2)
                .bold()
            
            VideoLibraryView(
                library: $settings.videoLibrary,
                onAdd: addVideo,
                onRemove: { file in
                    settings.removeVideoFile(file)
                }
            )
            
            Divider()
            
            Text("Screens")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        let screenSettings = settings.getSettings(for: screen)
                        ScreenRowView(
                            screen: screen,
                            isEnabled: Binding(
                                get: { screenSettings.isEnabled && engine.isRunning(on: screen) },
                                set: { newValue in
                                    handleToggle(for: screen, isEnabled: newValue)
                                }
                            ),
                            selectedVideoID: Binding(
                                get: { screenSettings.videoFileID },
                                set: { newValue in
                                    handleVideoChange(for: screen, videoID: newValue)
                                }
                            ),
                            videoLibrary: settings.videoLibrary,
                            onToggle: { isEnabled in
                                handleToggle(for: screen, isEnabled: isEnabled)
                            },
                            onVideoChange: { videoID in
                                handleVideoChange(for: screen, videoID: videoID)
                            }
                        )
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 250)
            
            
            Divider()
            
            HStack {
                Image(systemName: "speaker.wave.2.fill")
                Slider(value: $engine.videoVolume, in: 0.0...1.0)
                Text("\(Int(engine.videoVolume * 100))%")
                    .frame(width: 45)
            }
        }
        .frame(width: 400, height: 800)
        .padding()
        .onAppear {
            applyAllSettings()
        }
    }
    
    private func applyAllSettings() {
        for screen in NSScreen.screens {
            let savedSettings = settings.getSettings(for: screen)
            if savedSettings.isEnabled,
               let videoID = savedSettings.videoFileID,
               let videoFile = settings.videoLibrary.first(where: { $0.id == videoID }) {
                print("Auto-starting wallpaper for \(screen.localizedName)")
                engine.setVideo(url: videoFile.url, for: screen)
            }
        }
    }
    
    private func handleToggle(for screen: NSScreen, isEnabled: Bool) {
        var savedSettings = settings.getSettings(for: screen)
        savedSettings.isEnabled = isEnabled
        settings.updateSettings(for: screen, settings: savedSettings)
        
        if isEnabled {
            if let videoID = savedSettings.videoFileID,
               let videoFile = settings.videoLibrary.first(where: { $0.id == videoID }) {
                engine.setVideo(url: videoFile.url, for: screen)
            }
        } else {
            engine.stopWallpaper(for: screen)
        }
    }
    
    private func handleVideoChange(for screen: NSScreen, videoID: UUID?) {
        var savedSettings = settings.getSettings(for: screen)
        savedSettings.videoFileID = videoID
        settings.updateSettings(for: screen, settings: savedSettings)
        
        if savedSettings.isEnabled, let videoID = videoID,
           let videoFile = settings.videoLibrary.first(where: { $0.id == videoID }) {
            engine.setVideo(url: videoFile.url, for: screen)
        } else {
            engine.stopWallpaper(for: screen)
        }
    }
    
    private func addVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                settings.addVideoFile(url: url)
            }
        }
    }
}

#Preview {
    ContentView()
}
