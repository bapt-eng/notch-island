import Cocoa
import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import IOKit.ps

// MARK: - Power & Charging Monitor (IOKit Event-Driven)
struct ChargingState: Equatable {
    var isConnected: Bool
    var isCharging: Bool
    var watts: Int?
    var batteryPercent: Int
    var adapterName: String?
    var timeRemainingMinutes: Int?
    var timestamp: Date
}

class PowerMonitor: ObservableObject {
    @Published var currentState: ChargingState
    private var runLoopSource: CFRunLoopSource?
    var onChargingConnected: ((ChargingState) -> Void)?
    var onChargingDisconnected: (() -> Void)?
    
    private var wasConnected: Bool = false
    
    init() {
        let initial = PowerMonitor.readCurrentPowerInfo()
        self.currentState = initial
        self.wasConnected = initial.isConnected
        self.startMonitoring()
    }
    
    func startMonitoring() {
        let callback: IOPowerSourceCallbackType = { context in
            guard let ctx = context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.handlePowerEvent()
            }
        }
        
        let contextPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if let source = IOPSNotificationCreateRunLoopSource(callback, contextPtr)?.takeRetainedValue() {
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
    }
    
    func handlePowerEvent() {
        let newState = PowerMonitor.readCurrentPowerInfo()
        let previouslyConnected = wasConnected
        self.currentState = newState
        self.wasConnected = newState.isConnected
        
        if !previouslyConnected && newState.isConnected {
            if newState.watts == nil || newState.watts == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self = self else { return }
                    let refreshedState = PowerMonitor.readCurrentPowerInfo()
                    self.currentState = refreshedState
                    self.onChargingConnected?(refreshedState)
                }
            } else {
                self.onChargingConnected?(newState)
            }
        } else if previouslyConnected && !newState.isConnected {
            self.onChargingDisconnected?()
        }
    }
    
    static func readCurrentPowerInfo() -> ChargingState {
        var isCharging = false
        var isConnected = false
        var watts: Int? = nil
        var batteryPercent = 100
        var adapterName: String? = nil
        var timeToFull: Int? = nil
        
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                    if let state = desc[kIOPSPowerSourceStateKey] as? String {
                        isConnected = (state == kIOPSACPowerValue)
                    }
                    if let charging = desc[kIOPSIsChargingKey] as? Bool {
                        isCharging = charging
                    }
                    if let cap = desc[kIOPSCurrentCapacityKey] as? Int,
                       let maxCap = desc[kIOPSMaxCapacityKey] as? Int, maxCap > 0 {
                        batteryPercent = Int((Double(cap) / Double(maxCap)) * 100.0)
                    }
                    if let ttf = desc[kIOPSTimeToFullChargeKey] as? Int, ttf > 0 {
                        timeToFull = ttf
                    }
                }
            }
        }
        
        if let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            if let w = adapter[kIOPSPowerAdapterWattsKey] as? Int, w > 0 {
                watts = w
            } else if let w = adapter["Watts"] as? Int, w > 0 {
                watts = w
            }
            if let name = adapter[kIOPSPowerAdapterFamilyKey] as? String {
                adapterName = name
            } else if let name = adapter["Name"] as? String {
                adapterName = name
            }
        }
        
        return ChargingState(
            isConnected: isConnected,
            isCharging: isCharging,
            watts: watts,
            batteryPercent: batteryPercent,
            adapterName: adapterName,
            timeRemainingMinutes: timeToFull,
            timestamp: Date()
        )
    }
    
    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
    }
}

// MARK: - Staged File Model
struct StagedFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let sizeString: String
    let isDirectory: Bool
    let isImage: Bool
    let cachedThumbnail: NSImage?
    
    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
        
        let ext = url.pathExtension.lowercased()
        let imageExts = ["png", "jpg", "jpeg", "webp", "heic", "tiff", "gif", "bmp", "svg", "icns"]
        let isImg = !isDir.boolValue && imageExts.contains(ext)
        self.isImage = isImg
        
        if isImg, let fullImage = NSImage(contentsOf: url) {
            // Generate small lightweight thumbnail (Max 88x80) to respect 8GB RAM ceiling
            let targetSize = NSSize(width: 88, height: 80)
            let thumb = NSImage(size: targetSize)
            thumb.lockFocus()
            fullImage.draw(in: NSRect(origin: .zero, size: targetSize),
                           from: NSRect(origin: .zero, size: fullImage.size),
                           operation: .copy,
                           fraction: 1.0)
            thumb.unlockFocus()
            self.cachedThumbnail = thumb
        } else {
            self.cachedThumbnail = nil
        }
        
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            if isDir.boolValue {
                self.sizeString = "Dossier"
            } else if size > 1024 * 1024 {
                self.sizeString = String(format: "%.1f Mo", Double(size) / (1024.0 * 1024.0))
            } else if size > 1024 {
                self.sizeString = String(format: "%.0f Ko", Double(size) / 1024.0)
            } else {
                self.sizeString = "\(size) o"
            }
        } else {
            self.sizeString = isDir.boolValue ? "Dossier" : "Fichier"
        }
    }
    
    var isScreenshot: Bool {
        let lower = name.lowercased()
        return lower.contains("capture") || lower.contains("screenshot") || lower.contains("cleanshot")
    }
    
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
    
    static func == (lhs: StagedFile, rhs: StagedFile) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}



// MARK: - Native Vector Flashcard Engine (Zero-Lag, 120 FPS Apple Springs)
struct FormulaCard: Codable, Identifiable, Equatable {
    var id: String
    var category: String
    var question: String
    var answer: String
    var latex: String?
    var tip: String?
    var masteryLevel: Int
    var reviewCount: Int
}

struct FormulaSettings: Codable {
    var intervalMinutes: Int
    var dimBackground: Bool
    var soundEnabled: Bool
    var autoAdvance: Bool?
    var lastReviewTimestamp: Double?
}

struct FormulaDeck: Codable {
    var settings: FormulaSettings
    var cards: [FormulaCard]
}

class FormulaManager: ObservableObject {
    static let shared = FormulaManager()
    
    @Published var deck: FormulaDeck = FormulaDeck(
        settings: FormulaSettings(intervalMinutes: 30, dimBackground: false, soundEnabled: true, autoAdvance: false, lastReviewTimestamp: 0),
        cards: []
    )
    @Published var currentCard: FormulaCard? = nil
    @Published var isFlipped: Bool = false
    @Published var currentIndex: Int = 0
    
    private var reviewTimer: Timer?
    private let filePath: String
    private var isSystemActive: Bool = true
    
    init() {
        let home = NSHomeDirectory()
        self.filePath = "\(home)/.gemini/formulas/formulas.json"
        loadFromDisk()
        setupPowerAndScreenObservers()
        startPeriodicTimer()
    }
    
    func setupPowerAndScreenObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isSystemActive = false
        }
        wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isSystemActive = true
        }
        wsCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isSystemActive = false
        }
        wsCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isSystemActive = true
            self?.startPeriodicTimer()
        }
        wsCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isSystemActive = false
        }
        wsCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isSystemActive = true
        }
    }
    
    func loadFromDisk() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let decoded = try? JSONDecoder().decode(FormulaDeck.self, from: data) else {
            return
        }
        self.deck = decoded
        if currentCard == nil, let first = decoded.cards.first {
            self.currentCard = first
        }
    }
    
    func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(deck) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
    }
    
    func startPeriodicTimer() {
        reviewTimer?.invalidate()
        let intervalSec = max(60.0, Double(deck.settings.intervalMinutes * 60))
        let timer = Timer(timeInterval: intervalSec, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.triggerScheduledReview()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        reviewTimer = timer
    }
    
    func updateInterval(minutes: Int) {
        deck.settings.intervalMinutes = minutes
        saveToDisk()
        startPeriodicTimer()
    }
    
    func triggerScheduledReview() {
        guard isSystemActive else { return }
        pickNextCard()
        AppDelegate.shared?.store.showFlashcard()
    }
    
    func pickNextCard(cardId: String? = nil) {
        loadFromDisk()
        guard !deck.cards.isEmpty else { return }
        self.isFlipped = false
        if let cid = cardId, let found = deck.cards.first(where: { $0.id == cid }) {
            self.currentCard = found
        } else {
            currentIndex = (currentIndex + 1) % deck.cards.count
            self.currentCard = deck.cards[currentIndex]
        }
    }
    
    func flipCard() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            self.isFlipped.toggle()
        }
        if deck.settings.soundEnabled {
            if let pop = NSSound(named: "Pop") {
                pop.volume = 0.20
                pop.play()
            }
        }
    }
    
    func validateCard(mastered: Bool) {
        guard let card = currentCard else { return }
        if let idx = deck.cards.firstIndex(where: { $0.id == card.id }) {
            deck.cards[idx].reviewCount += 1
            if mastered {
                deck.cards[idx].masteryLevel += 1
            } else {
                deck.cards[idx].masteryLevel = max(0, deck.cards[idx].masteryLevel - 1)
            }
        }
        deck.settings.lastReviewTimestamp = Date().timeIntervalSince1970
        saveToDisk()
        
        if deck.settings.soundEnabled {
            if let sound = NSSound(named: mastered ? "Glass" : "Basso") {
                sound.volume = 0.20
                sound.play()
            }
        }
    }
}

class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

class FocusOverlayView: NSView {
    override func mouseDown(with event: NSEvent) {
        AppDelegate.shared?.store.dismissFlashcard()
    }
}

class FocusOverlayPanel: NSPanel {
    init() {
        let screenUnion = NSScreen.screens.reduce(NSRect.null) { rect, screen in
            return rect.union(screen.frame)
        }
        super.init(
            contentRect: screenUnion,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = NSColor(white: 0.0, alpha: 0.58)
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) - 1)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.alphaValue = 0.0
        
        let overlayView = FocusOverlayView(frame: NSRect(origin: .zero, size: screenUnion.size))
        overlayView.autoresizingMask = [.width, .height]
        self.contentView = overlayView
    }
}

class ScreenDimmerManager {
    static let shared = ScreenDimmerManager()
    private var dimmerPanel: FocusOverlayPanel?
    private var isDimming = false

    func dimScreens(animated: Bool = true) {
        guard FormulaManager.shared.deck.settings.dimBackground else { return }
        guard !isDimming else { return }
        isDimming = true
        undimScreens(animated: false)
        let panel = FocusOverlayPanel()
        dimmerPanel = panel
        panel.orderFront(nil)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.completionHandler = nil
                panel.animator().alphaValue = 1.0
            }
        } else {
            panel.alphaValue = 1.0
        }
        isDimming = false
    }

    func undimScreens(animated: Bool = true) {
        guard let panel = dimmerPanel else { return }
        dimmerPanel = nil
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.30
                panel.animator().alphaValue = 0.0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        } else {
            panel.alphaValue = 0.0
            panel.orderOut(nil)
        }
    }
}

struct NativeLaTeXView: View {
    let cardId: String
    let fallbackText: String
    let maxHeight: CGFloat
    @State private var cachedImage: NSImage? = nil

    private func loadSVG(at path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let img = NSImage(contentsOfFile: path) else { return nil }
        let origW = max(1.0, img.size.width)
        let origH = max(1.0, img.size.height)
        let aspect = origW / origH
        let targetH = maxHeight
        let targetW = min(500, targetH * aspect)
        img.size = NSSize(width: targetW, height: targetH)
        return img
    }

    var body: some View {
        Group {
            if let img = cachedImage {
                Image(nsImage: img)
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: maxHeight)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            } else {
                Text(fallbackText)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.98, green: 0.85, blue: 0.38))
                    .padding(6)
            }
        }
        .onAppear {
            if cachedImage == nil {
                cachedImage = loadSVG(at: "\(NSHomeDirectory())/.gemini/formulas/svg/\(cardId).svg")
            }
        }
        .onChange(of: cardId) { _ in
            cachedImage = loadSVG(at: "\(NSHomeDirectory())/.gemini/formulas/svg/\(cardId).svg")
        }
    }
}

// MARK: - Island State Store
struct IslandMessage {
    let title: String
    let body: String
    let icon: String
    let tintColorHex: String
}

enum IslandMode {
    case compact
    case chargingHUD
    case fileShelf
    case flashcard
    case messageHUD
}

class IslandStore: ObservableObject {
    var onGeometryChange: ((_ animated: Bool) -> Void)?
    
    @Published var files: [StagedFile] = [] {
        didSet {
            onGeometryChange?(false)
        }
    }
    @Published var isHovered: Bool = false {
        didSet {
            if isHovered != oldValue {
                onGeometryChange?(!isHovered)
            }
        }
    }
    @Published var isDropTarget: Bool = false {
        didSet {
            if isDropTarget != oldValue {
                onGeometryChange?(!isDropTarget)
            }
        }
    }
    
    @Published var flashcardActive: Bool = false {
        didSet {
            if flashcardActive != oldValue {
                onGeometryChange?(!flashcardActive)
            }
        }
    }
    @Published var chargingHUDActive: Bool = false {
        didSet {
            if chargingHUDActive != oldValue {
                onGeometryChange?(!chargingHUDActive)
            }
        }
    }
    @Published var messageHUDActive: Bool = false {
        didSet {
            if messageHUDActive != oldValue {
                onGeometryChange?(!messageHUDActive)
            }
        }
    }
    @Published var activeChargingState: ChargingState? = nil
    @Published var activeMessage: IslandMessage? = nil
    @Published var soundEnabled: Bool = false
    
    private var chargingDismissTimer: Timer?
    private var messageDismissTimer: Timer?
    
    var isExpanded: Bool {
        return isHovered || isDropTarget || (files.count > 0 && isHovered)
    }
    
    var currentMode: IslandMode {
        if messageHUDActive && activeMessage != nil {
            return .messageHUD
        } else if flashcardActive {
            return .flashcard
        } else if isHovered || isDropTarget || (files.count > 0 && isHovered) {
            return .fileShelf
        } else if chargingHUDActive && activeChargingState != nil {
            return .chargingHUD
        } else {
            return .compact
        }
    }
    
    func showMessage(title: String, body: String, icon: String = "bubble.left.and.bubble.right.fill", tint: String = "cyan", duration: Double = 5.0) {
        self.activeMessage = IslandMessage(title: title, body: body, icon: icon, tintColorHex: tint)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.74)) {
            self.messageHUDActive = true
        }
        playGentleFeedback()
        
        messageDismissTimer?.invalidate()
        messageDismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                self.messageHUDActive = false
                self.activeMessage = nil
            }
        }
    }
    
    func showFlashcard(cardId: String? = nil) {
        FormulaManager.shared.pickNextCard(cardId: cardId)
        self.isHovered = false
        ScreenDimmerManager.shared.dimScreens(animated: true)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
            self.flashcardActive = true
        }
        if soundEnabled || FormulaManager.shared.deck.settings.soundEnabled {
            if let sound = NSSound(named: "Ping") {
                sound.volume = 0.20
                sound.play()
            }
        }
        DispatchQueue.main.async {
            if let win = AppDelegate.shared?.window {
                win.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func dismissFlashcard() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            self.flashcardActive = false
            self.isHovered = false
        }
        FormulaManager.shared.isFlipped = false
        ScreenDimmerManager.shared.undimScreens(animated: true)
        AppDelegate.shared?.updateWindowGeometry(animated: false)
    }
    
    func validateAndDismissFlashcard(mastered: Bool) {
        FormulaManager.shared.validateCard(mastered: mastered)
        dismissFlashcard()
    }
    
    func playGentleFeedback() {
        guard soundEnabled else { return }
        if let sound = NSSound(named: "Tink") {
            sound.volume = 0.20
            sound.play()
        }
    }
    
    func showChargingHUD(state: ChargingState) {
        self.activeChargingState = state
        withAnimation(.spring(response: 0.32, dampingFraction: 0.74)) {
            self.chargingHUDActive = true
        }
        
        playGentleFeedback()
        
        chargingDismissTimer?.invalidate()
        chargingDismissTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                self.chargingHUDActive = false
            }
        }
    }
    
    func hideChargingHUD() {
        chargingDismissTimer?.invalidate()
        chargingDismissTimer = nil
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            self.chargingHUDActive = false
        }
    }
    
    func addFiles(urls: [URL]) {
        for url in urls {
            if !files.contains(where: { $0.url == url }) {
                files.append(StagedFile(url: url))
            }
        }
        if soundEnabled {
            if let pop = NSSound(named: "Pop") {
                pop.volume = 0.20
                pop.play()
            }
        }
    }
    
    func removeFile(_ file: StagedFile) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            files.removeAll(where: { $0.id == file.id })
        }
    }
    
    func clearAll() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            files.removeAll()
        }
    }
    
    func openInFinder(_ file: StagedFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }
    
    func openFile(_ file: StagedFile) {
        NSWorkspace.shared.open(file.url)
    }
    
    // MARK: - Screenshot & Image Storage
    var screenshotCacheDir: URL {
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("NotchIslandScreenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }
    
    func saveImageData(_ data: Data, suggestedName: String? = nil) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'à' HH.mm.ss"
        let timestamp = formatter.string(from: Date())
        let filename = suggestedName ?? "Capture d’écran \(timestamp).png"
        let fileURL = screenshotCacheDir.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Erreur d'écriture screenshot:", error)
            return nil
        }
    }
    
    func pasteFromClipboard() {
        let pb = NSPasteboard.general
        
        // 1. Check for File URLs first
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            addFiles(urls: urls)
            return
        }
        
        // 2. Check for PNG image data
        if let pngData = pb.data(forType: .png) {
            if let url = saveImageData(pngData) {
                addFiles(urls: [url])
                return
            }
        }
        
        // 3. Check for TIFF image data
        if let tiffData = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiffData),
           let pngData = rep.representation(using: .png, properties: [:]) {
            if let url = saveImageData(pngData) {
                addFiles(urls: [url])
                return
            }
        }
    }
    
    func triggerInteractiveScreenshot() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'à' HH.mm.ss"
        let timestamp = formatter.string(from: Date())
        let filename = "Capture d’écran \(timestamp).png"
        let destURL = screenshotCacheDir.appendingPathComponent(filename)
        
        // Temporarily collapse island so it does not obstruct the screenshot
        self.isHovered = false
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let task = Process()
            task.launchPath = "/usr/sbin/screencapture"
            // -i: interactive mode (selection or space for window)
            task.arguments = ["-i", destURL.path]
            
            task.launch()
            task.waitUntilExit()
            
            if FileManager.default.fileExists(atPath: destURL.path) {
                DispatchQueue.main.async {
                    self?.addFiles(urls: [destURL])
                    self?.isHovered = true
                    self?.playGentleFeedback()
                }
            }
        }
    }
}

// MARK: - Custom Seamless Notch Shape (Zero Top Radius, Smooth Bottom Radius)
struct NotchPillShape: Shape {
    var bottomRadius: CGFloat = 22
    
    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = max(0, min(bottomRadius, min(rect.width / 2, rect.height)))
        
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Perfectly Positioned Charging HUD View (Below Notch Area)
struct ChargingHUDView: View {
    let state: ChargingState
    @State private var isPulsing: Bool = false
    
    var wattsValue: String {
        if let w = state.watts, w > 0 {
            return "\(w)"
        }
        return "--"
    }
    
    var isFastCharge: Bool {
        if let w = state.watts {
            return w >= 60
        }
        return false
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Hardware Notch Clearance Zone (38px reserved for top screen bezel & camera cutout)
            Color.clear
                .frame(height: 38)
            
            // Visible Interactive Content Area
            HStack(alignment: .center, spacing: 14) {
                // Left: Glowing MagSafe Bolt
                ZStack {
                    Circle()
                        .fill(Color(red: 0.188, green: 0.820, blue: 0.345).opacity(isPulsing ? 0.35 : 0.12))
                        .frame(width: 34, height: 34)
                        .scaleEffect(isPulsing ? 1.15 : 0.95)
                        .animation(Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: isPulsing)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.188, green: 0.820, blue: 0.345), Color(red: 0.12, green: 0.65, blue: 0.28)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                        .shadow(color: Color(red: 0.188, green: 0.820, blue: 0.345).opacity(0.55), radius: 6, x: 0, y: 1)
                    
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                }
                .frame(width: 36)
                
                // Center: Status & Wattage Typography
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(isFastCharge ? "CHARGE RAPIDE" : "EN CHARGE")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .kerning(0.8)
                            .foregroundColor(Color(red: 0.188, green: 0.820, blue: 0.345))
                        
                        Circle()
                            .fill(Color(red: 0.188, green: 0.820, blue: 0.345).opacity(0.8))
                            .frame(width: 3.5, height: 3.5)
                        
                        Text(state.adapterName ?? "MagSafe 3")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.60))
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(wattsValue)
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("W")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.188, green: 0.820, blue: 0.345))
                        
                        if let timeRemaining = state.timeRemainingMinutes, timeRemaining > 0 {
                            Text("• ~\(timeRemaining) min")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.60))
                                .padding(.leading, 6)
                        }
                    }
                }
                
                Spacer(minLength: 8)
                
                // Right: Circular Battery Progress Ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 3.2)
                        .frame(width: 32, height: 32)
                    
                    Circle()
                        .trim(from: 0.0, to: CGFloat(min(100, max(0, state.batteryPercent))) / 100.0)
                        .stroke(
                            LinearGradient(
                                colors: [Color(red: 0.188, green: 0.820, blue: 0.345), Color(red: 0.35, green: 0.95, blue: 0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 32, height: 32)
                    
                    Text("\(state.batteryPercent)%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(width: 36)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }
        .frame(width: 360, height: 88)
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Native Apple Dynamic Island Message HUD View
struct MessageHUDView: View {
    let message: IslandMessage
    @State private var isPulsing: Bool = false
    
    var tintColor: Color {
        switch message.tintColorHex.lowercased() {
        case "green", "emerald": return Color(red: 0.188, green: 0.820, blue: 0.345)
        case "magenta", "pink": return Color(red: 0.98, green: 0.14, blue: 0.45)
        case "orange": return Color(red: 1.0, green: 0.58, blue: 0.0)
        case "purple": return Color(red: 0.68, green: 0.32, blue: 0.98)
        default: return Color(red: 0.22, green: 0.74, blue: 0.98)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 38)
            
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tintColor.opacity(isPulsing ? 0.35 : 0.12))
                        .frame(width: 34, height: 34)
                        .scaleEffect(isPulsing ? 1.15 : 0.95)
                        .animation(Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: isPulsing)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [tintColor, tintColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                        .shadow(color: tintColor.opacity(0.55), radius: 6, x: 0, y: 1)
                    
                    Image(systemName: message.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 36)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(message.title.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .kerning(0.8)
                            .foregroundColor(tintColor)
                        
                        Circle()
                            .fill(Color.white.opacity(0.4))
                            .frame(width: 3, height: 3)
                        
                        Text("MAINTENANT")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.60))
                    }
                    
                    Text(message.body)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }
                
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 380, height: 88)
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Sleek Dark File Card View
struct FileCardView: View {
    let file: StagedFile
    let onRemove: () -> Void
    let onOpen: () -> Void
    @State private var isCardHovered = false
    
    var borderColor: Color {
        if file.isScreenshot {
            return isCardHovered ? Color.cyan.opacity(0.85) : Color.cyan.opacity(0.3)
        } else {
            return isCardHovered ? Color.white.opacity(0.25) : Color.white.opacity(0.06)
        }
    }
    
    @ViewBuilder
    var thumbnailView: some View {
        if file.isImage, let thumb = file.cachedThumbnail {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(file.isScreenshot ? Color.cyan.opacity(0.7) : Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 2)
        } else {
            Image(nsImage: file.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 2)
        }
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 5) {
                thumbnailView
                
                HStack(spacing: 2) {
                    if file.isScreenshot {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 7))
                            .foregroundColor(.cyan)
                    }
                    Text(file.name)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(width: 72)
                
                Text(file.sizeString)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(file.isScreenshot ? Color.cyan.opacity(0.85) : Color.white.opacity(0.5))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(width: 82, height: 92)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCardHovered ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .onHover { h in
                withAnimation(.easeInOut(duration: 0.15)) { isCardHovered = h }
            }
            .onTapGesture(count: 2) {
                onOpen()
            }
            .onDrag {
                NSItemProvider(object: file.url as NSURL)
            }
            
            if isCardHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.65))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(4)
                .transition(.opacity)
            }
        }
    }
}


// MARK: - Flashcard Views (Native Pure Swift)
struct FlashcardHeaderView: View {
    @ObservedObject var store: IslandStore
    let card: FormulaCard
    
    var body: some View {
        HStack(spacing: 8) {
            Text(card.category.uppercased())
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(Color.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(Color.cyan.opacity(0.18))
                        .overlay(Capsule().stroke(Color.cyan.opacity(0.35), lineWidth: 0.8))
                )
            
            Spacer()
            
            Text("⚡ RÉVISION FLASH")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.55))
            
            Button(action: { store.dismissFlashcard() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.20)))
                    .contentShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 40)
    }
}

struct FlashcardQuestionBody: View {
    let card: FormulaCard
    let onFlip: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 2)
            
            Text(card.question)
                .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 20)
            
            if let tip = card.tip, !tip.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.yellow)
                    Text(tip)
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.70))
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
            }
            
            Spacer(minLength: 4)
            
            Button(action: onFlip) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .bold))
                    Text("Dévoiler la formule & solution")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Text("[ Espace ]")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.65))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.35), Color.blue.opacity(0.35)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.cyan.opacity(0.55), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom, 12)
        }
    }
}

struct FlashcardAnswerBody: View {
    @ObservedObject var store: IslandStore
    let card: FormulaCard
    
    var body: some View {
        VStack(spacing: 8) {
            // 1. Question Reminder
            Text(card.question)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundColor(Color.cyan)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 20)
                .padding(.top, 2)
            
            // 2. Pure Vector LaTeX Formula Container (Crisp White on OLED Black)
            VStack(alignment: .center, spacing: 0) {
                NativeLaTeXView(cardId: card.id, fallbackText: card.latex ?? "", maxHeight: 135)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.05, green: 0.06, blue: 0.09).opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.45), Color.white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, 16)
            
            // 3. Definitions & Formulations List
            VStack(alignment: .leading, spacing: 3) {
                ForEach(card.answer.components(separatedBy: "\n"), id: \.self) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 4, height: 4)
                            .padding(.top, 4)
                        Text(line)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.92))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            
            // 4. Mnemonic Tip
            if let tip = card.tip, !tip.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.yellow)
                    Text(tip)
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.72))
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
            }
            
            Spacer(minLength: 2)
            
            // 5. Actions Row
            HStack(spacing: 10) {
                Button(action: { store.validateAndDismissFlashcard(mastered: true) }) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Maîtrisé (Entrée)")
                    }
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(red: 0.12, green: 0.70, blue: 0.35))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { store.validateAndDismissFlashcard(mastered: false) }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("À revoir (Échap)")
                    }
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.12))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Calculator.app"))
                }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.7))
                        .padding(7)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }
}

struct FlashcardView: View {
    @ObservedObject var store: IslandStore
    @ObservedObject var formulaManager = FormulaManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            if let card = formulaManager.currentCard {
                FlashcardHeaderView(store: store, card: card)
                
                if formulaManager.isFlipped {
                    FlashcardAnswerBody(store: store, card: card)
                        .transition(.opacity)
                } else {
                    FlashcardQuestionBody(card: card, onFlip: {
                        formulaManager.flipCard()
                    })
                    .transition(.opacity)
                }
            } else {
                VStack(spacing: 12) {
                    Text("Aucune formule dans la base.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    Button("Fermer") { store.dismissFlashcard() }
                }
                .padding(.top, 50)
            }
        }
        .frame(width: 540, height: 385)
    }
}

// MARK: - Dynamic Island Main Container View (120 FPS Fluid Springs)
struct DynamicIslandView: View {
    @ObservedObject var store: IslandStore
    
    var currentPillWidth: CGFloat {
        switch store.currentMode {
        case .messageHUD:
            return 380
        case .flashcard:
            return 540
        case .fileShelf:
            return store.files.isEmpty ? 380 : min(560, max(380, CGFloat(store.files.count) * 90 + 50))
        case .chargingHUD:
            return 360
        case .compact:
            return store.files.isEmpty ? 185 : 210
        }
    }
    
    var currentPillHeight: CGFloat {
        switch store.currentMode {
        case .messageHUD:
            return 88
        case .flashcard:
            return 385
        case .fileShelf:
            return 188
        case .chargingHUD:
            return 88
        case .compact:
            return 36
        }
    }
    
    var bottomCornerRadius: CGFloat {
        switch store.currentMode {
        case .messageHUD: return 22
        case .flashcard: return 28
        case .fileShelf: return 24
        case .chargingHUD: return 22
        case .compact: return 16
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Background Seamless OLED Pill (Flush with top bezel, 0 gap)
                NotchPillShape(bottomRadius: bottomCornerRadius)
                    .fill(Color(red: 8/255, green: 9/255, blue: 11/255).opacity(0.99))
                    .overlay(
                        NotchPillShape(bottomRadius: bottomCornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.clear,
                                        borderBaseColor
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: store.currentMode == .chargingHUD ? 1.2 : (store.isDropTarget ? 1.5 : 0.8)
                            )
                    )
                    .shadow(color: Color.black.opacity(0.65), radius: 16, x: 0, y: 8)
                
                // Active Mode Content
                Group {
                    switch store.currentMode {
                    case .messageHUD:
                        if let msg = store.activeMessage {
                            MessageHUDView(message: msg)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                                    removal: .scale(scale: 0.96).combined(with: .opacity)
                                ))
                        }
                    case .flashcard:
                        FlashcardView(store: store)
                            .transition(.opacity)
                    case .chargingHUD:
                        if let chargingState = store.activeChargingState {
                            ChargingHUDView(state: chargingState)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                                    removal: .scale(scale: 0.96).combined(with: .opacity)
                                ))
                        }
                    case .fileShelf:
                        fileShelfContent
                            .transition(.opacity)
                    case .compact:
                        collapsedContent
                            .transition(.opacity)
                    }
                }
            }
            .frame(width: currentPillWidth, height: currentPillHeight)
            .clipShape(NotchPillShape(bottomRadius: bottomCornerRadius))
            .onDrop(of: [.fileURL, .image, .png, .jpeg, .tiff], isTargeted: $store.isDropTarget) { providers in
                handleDrop(providers: providers)
                return true
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.32, dampingFraction: 0.74, blendDuration: 0.05), value: store.currentMode)
    }
    
    var borderBaseColor: Color {
        if store.currentMode == .flashcard {
            return Color.cyan.opacity(0.65)
        } else if store.currentMode == .chargingHUD {
            return Color(red: 0.188, green: 0.820, blue: 0.345).opacity(0.50)
        } else if store.isDropTarget {
            return Color.cyan.opacity(0.6)
        } else {
            return Color.white.opacity(0.12)
        }
    }
    
    var collapsedContent: some View {
        HStack(spacing: 7) {
            if store.files.isEmpty {
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 6, height: 6)
                
                Text("Dynamic Island")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            } else {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("\(store.files.count) élément\(store.files.count > 1 ? "s" : "")")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 5, height: 5)
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 10)
    }
    
    var fileShelfContent: some View {
        VStack(spacing: 0) {
            // Notch Clearance Top Spacer
            Color.clear
                .frame(height: 38)
            
            VStack(spacing: 7) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: store.files.isEmpty ? "arrow.down.doc" : "tray.full.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                        
                        Text(store.files.isEmpty ? "Déposer ici" : "Salle d'attente (\(store.files.count))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 5) {
                        Button(action: { store.triggerInteractiveScreenshot() }) {
                            HStack(spacing: 3) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 8))
                                Text("Capture")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                            }
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.cyan.opacity(0.12))
                            .cornerRadius(5)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: { store.pasteFromClipboard() }) {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 8))
                                Text("Coller")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                            }
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(5)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if !store.files.isEmpty {
                            Button(action: { store.clearAll() }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 8))
                                    Text("Vider")
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                }
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(5)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
                
                if store.files.isEmpty {
                    VStack(spacing: 5) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.35))
                        
                        Text("Glissez fichiers ou captures d’écran")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 6)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(store.files) { file in
                                FileCardView(
                                    file: file,
                                    onRemove: { store.removeFile(file) },
                                    onOpen: { store.openFile(file) }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(height: 98)
                }
                
                if !store.files.isEmpty {
                    HStack {
                        Text("Glissez vers l'extérieur pour déplacer")
                            .font(.system(size: 8.5, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        var droppedURLs: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            
            // Check for file URL first
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        droppedURLs.append(url)
                        group.leave()
                    } else {
                        self.tryLoadImageData(from: provider) { imgURL in
                            if let imgURL = imgURL {
                                droppedURLs.append(imgURL)
                            }
                            group.leave()
                        }
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    if let img = image as? NSImage,
                       let tiff = img.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: tiff),
                       let png = rep.representation(using: .png, properties: [:]) {
                        if let url = self.store.saveImageData(png) {
                            droppedURLs.append(url)
                        }
                    }
                    group.leave()
                }
            } else {
                self.tryLoadImageData(from: provider) { imgURL in
                    if let imgURL = imgURL {
                        droppedURLs.append(imgURL)
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            if !droppedURLs.isEmpty {
                store.addFiles(urls: droppedURLs)
            }
        }
    }
    
    private func tryLoadImageData(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        let imageTypes = [UTType.png.identifier, UTType.tiff.identifier, UTType.jpeg.identifier, UTType.image.identifier]
        
        var targetType: String? = nil
        for type in imageTypes {
            if provider.hasItemConformingToTypeIdentifier(type) {
                targetType = type
                break
            }
        }
        
        guard let typeId = targetType else {
            completion(nil)
            return
        }
        
        provider.loadDataRepresentation(forTypeIdentifier: typeId) { data, error in
            if let data = data {
                if typeId == UTType.tiff.identifier,
                   let rep = NSBitmapImageRep(data: data),
                   let png = rep.representation(using: .png, properties: [:]) {
                    let url = self.store.saveImageData(png)
                    completion(url)
                } else {
                    let ext = (typeId == UTType.jpeg.identifier) ? "jpg" : "png"
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd 'à' HH.mm.ss"
                    let name = "Capture d’écran \(formatter.string(from: Date())).\(ext)"
                    let url = self.store.saveImageData(data, suggestedName: name)
                    completion(url)
                }
            } else {
                completion(nil)
            }
        }
    }
}

// MARK: - Dynamic Window Container with Adaptive Hit-Testing & Hover Tracking
class IslandHostingContainer: NSView {
    var store: IslandStore!
    private var trackingArea: NSTrackingArea?
    private var collapseTimer: Timer?
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        let size = bounds.size
        let r: CGFloat
        switch store.currentMode {
        case .messageHUD: r = 22
        case .flashcard: r = 26
        case .fileShelf: r = 24
        case .chargingHUD: r = 22
        case .compact: r = 16
        }
        
        // Pass through transparent rounded corners at the bottom
        if point.y < r {
            if point.x < r {
                let dx = point.x - r
                let dy = point.y - r
                if (dx * dx + dy * dy) > (r * r) { return nil }
            } else if point.x > size.width - r {
                let dx = point.x - (size.width - r)
                let dy = point.y - r
                if (dx * dx + dy * dy) > (r * r) { return nil }
            }
        }
        return super.hitTest(point)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .inVisibleRect
        ]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        checkHoverState()
    }
    
    override func mouseMoved(with event: NSEvent) {
        checkHoverState()
    }
    
    override func mouseExited(with event: NSEvent) {
        collapseTimer?.invalidate()
        collapseTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                self.store.isHovered = false
            }
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if store.currentMode == .flashcard {
            let loc = convert(event.locationInWindow, from: nil)
            let pillW: CGFloat = 540
            let pillH: CGFloat = 385
            let pillRect = NSRect(x: (bounds.width - pillW) / 2.0, y: bounds.height - pillH, width: pillW, height: pillH)
            if !pillRect.contains(loc) {
                store.dismissFlashcard()
                return
            }
        }
        super.mouseDown(with: event)
    }
    
    private func checkHoverState() {
        collapseTimer?.invalidate()
        collapseTimer = nil
        
        guard !store.flashcardActive && !store.chargingHUDActive else { return }
        
        if !store.isHovered {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.74)) {
                store.isHovered = true
            }
        }
    }
}

// MARK: - AppKit Window Controller & Dynamic Window Geometry
class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    
    var window: NSPanel!
    var store = IslandStore()
    var powerMonitor = PowerMonitor()
    var containerView: IslandHostingContainer!
    private var collapseWindowTimer: Timer?
    
    override init() {
        super.init()
        AppDelegate.shared = self
    }
    
    func targetSize() -> CGSize {
        let w: CGFloat
        let h: CGFloat
        switch store.currentMode {
        case .messageHUD:
            w = 380
            h = 88
        case .flashcard:
            w = 540
            h = 385
        case .fileShelf:
            w = store.files.isEmpty ? 380 : min(560, max(380, CGFloat(store.files.count) * 90 + 50))
            h = 188
        case .chargingHUD:
            w = 360
            h = 88
        case .compact:
            w = store.files.isEmpty ? 185 : 210
            h = 36
        }
        return CGSize(width: w, height: h)
    }
    
    func targetRect(for size: CGSize? = nil) -> NSRect {
        let sz = size ?? targetSize()
        guard let screen = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) ?? NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(x: 0, y: 0, width: sz.width, height: sz.height)
        }
        let screenRect = screen.frame
        let midX: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, right.minX > left.maxX {
            midX = (left.maxX + right.minX) / 2.0
        } else {
            midX = screenRect.midX
        }
        let x = midX - (sz.width / 2.0)
        let y = screenRect.maxY - sz.height + 4 // +4px subpixel bleed into bezel
        return NSRect(x: x, y: y, width: sz.width, height: sz.height)
    }
    
    func updateWindowGeometry(animated: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            self.collapseWindowTimer?.invalidate()
            self.collapseWindowTimer = nil
            
            let rect = self.targetRect()
            let isExpanding = rect.width > window.frame.width || rect.height > window.frame.height
            
            if isExpanding {
                // Expanding: resize window frame immediately so SwiftUI spring has room to render
                window.setFrame(rect, display: true, animate: false)
            } else if animated {
                // Collapsing: let SwiftUI spring animate smoothly for 0.32s, then shrink frame to notch bounds
                self.collapseWindowTimer = Timer.scheduledTimer(withTimeInterval: 0.32, repeats: false) { [weak self] _ in
                    guard let self = self, let window = self.window else { return }
                    let finalRect = self.targetRect()
                    window.setFrame(finalRect, display: true, animate: false)
                }
            } else {
                window.setFrame(rect, display: true, animate: false)
            }
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let initialSize = targetSize()
        let initialRect = targetRect(for: initialSize)
        
        window = IslandPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.hasShadow = false
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        
        containerView = IslandHostingContainer(frame: NSRect(origin: .zero, size: initialSize))
        containerView.store = store
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        
        let hostingView = NSHostingView(rootView: DynamicIslandView(store: store))
        hostingView.frame = containerView.bounds
        hostingView.autoresizingMask = [.width, .height]
        
        containerView.addSubview(hostingView)
        window.contentView = containerView
        window.setFrame(initialRect, display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
        
        // Connect Store Geometry Updates
        store.onGeometryChange = { [weak self] animated in
            self?.updateWindowGeometry(animated: animated)
        }
        
        // Screen Resolution & Layout Change Listener
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateWindowGeometry(animated: false)
        }
        
        // Connect Power Monitor Events
        powerMonitor.onChargingConnected = { [weak self] state in
            self?.store.showChargingHUD(state: state)
        }
        
        powerMonitor.onChargingDisconnected = { [weak self] in
            self?.store.hideChargingHUD()
        }
        
        // Local Key Monitor for Instant Fluid Flashcard Navigation
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.store.currentMode == .flashcard else { return event }
            if event.keyCode == 49 { // Space bar
                FormulaManager.shared.flipCard()
                return nil
            } else if event.keyCode == 36 { // Enter / Return
                self.store.validateAndDismissFlashcard(mastered: true)
                return nil
            } else if event.keyCode == 53 { // Escape
                self.store.dismissFlashcard()
                return nil
            }
            return event
        }
        
        // Global Key Monitor: Escape dismisses flashcard from ANY active app
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.store.currentMode == .flashcard else { return }
            if event.keyCode == 53 { // Escape
                DispatchQueue.main.async {
                    self.store.dismissFlashcard()
                }
            }
        }
        
        // Global Mouse Monitor: Clicking outside the Island dismisses flashcard immediately
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.store.currentMode == .flashcard, let window = self.window else { return }
            let mouseLoc = NSEvent.mouseLocation
            if !window.frame.contains(mouseLoc) {
                DispatchQueue.main.async {
                    self.store.dismissFlashcard()
                }
            }
        }
        
        // Setup Distributed Notification Observers for testing & CLI triggers
        let dCenter = DistributedNotificationCenter.default()
        dCenter.addObserver(
            self,
            selector: #selector(handleTestCharge(_:)),
            name: NSNotification.Name("com.antigravity.notchisland.testCharge"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        dCenter.addObserver(
            self,
            selector: #selector(handleSetSound(_:)),
            name: NSNotification.Name("com.antigravity.notchisland.setSound"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        dCenter.addObserver(
            self,
            selector: #selector(handleHide(_:)),
            name: NSNotification.Name("com.antigravity.notchisland.hide"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        dCenter.addObserver(
            self,
            selector: #selector(handleTakeScreenshot(_:)),
            name: NSNotification.Name("com.antigravity.notchisland.screenshot"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        dCenter.addObserver(
            self,
            selector: #selector(handlePasteClipboard(_:)),
            name: NSNotification.Name("com.antigravity.notchisland.paste"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        dCenter.addObserver(
            self,
            selector: #selector(handleTriggerFlashcard(_:)),
            name: NSNotification.Name("com.antigravity.notchisland.triggerFlashcard"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        dCenter.addObserver(
            self,
            selector: #selector(handleFlipFlashcard(_:)),
            name: NSNotification.Name("com.antigravity.notchisland.flipFlashcard"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        dCenter.addObserver(
            self,
            selector: #selector(handleDismissFlashcard(_:)),
            name: NSNotification.Name("com.antigravity.notchisland.dismissFlashcard"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        dCenter.addObserver(
            self,
            selector: #selector(handleReloadFormulas(_:)),
            name: NSNotification.Name("com.antigravity.notchisland.reloadFormulas"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        dCenter.addObserver(
            self,
            selector: #selector(handleShowMessage(_:)),
            name: NSNotification.Name("com.antigravity.notchisland.showMessage"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        dCenter.addObserver(
            self,
            selector: #selector(handleSetInterval(_:)),
            name: NSNotification.Name("com.antigravity.notchisland.setInterval"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }
    
    @objc func handleShowMessage(_ notif: Notification) {
        let title = notif.userInfo?["title"] as? String ?? "Notification"
        let body = notif.userInfo?["body"] as? String ?? ""
        let icon = notif.userInfo?["icon"] as? String ?? "bubble.left.and.bubble.right.fill"
        let tint = notif.userInfo?["tint"] as? String ?? "cyan"
        let dur = Double(notif.userInfo?["duration"] as? Int ?? 5)
        self.store.showMessage(title: title, body: body, icon: icon, tint: tint, duration: dur)
    }
    
    @objc func handleTakeScreenshot(_ notif: Notification) {
        self.store.triggerInteractiveScreenshot()
    }
    
    @objc func handlePasteClipboard(_ notif: Notification) {
        self.store.pasteFromClipboard()
    }
    
    @objc func handleTriggerFlashcard(_ notif: Notification) {
        let cardId = notif.userInfo?["cardId"] as? String
        self.store.showFlashcard(cardId: cardId)
    }
    
    @objc func handleFlipFlashcard(_ notif: Notification) {
        FormulaManager.shared.flipCard()
    }
    
    @objc func handleDismissFlashcard(_ notif: Notification) {
        self.store.dismissFlashcard()
    }
    
    @objc func handleReloadFormulas(_ notif: Notification) {
        FormulaManager.shared.loadFromDisk()
    }
    
    @objc func handleSetInterval(_ notif: Notification) {
        if let mins = notif.userInfo?["minutes"] as? Int {
            FormulaManager.shared.updateInterval(minutes: mins)
        } else if let mStr = notif.userInfo?["minutes"] as? String, let mins = Int(mStr) {
            FormulaManager.shared.updateInterval(minutes: mins)
        }
    }
    
    @objc func handleTestCharge(_ notif: Notification) {
        var watts = 96
        var battery = 84
        if let userInfo = notif.userInfo {
            if let w = userInfo["watts"] as? Int { watts = w }
            else if let wStr = userInfo["watts"] as? String, let w = Int(wStr) { watts = w }
            if let b = userInfo["battery"] as? Int { battery = b }
            else if let bStr = userInfo["battery"] as? String, let b = Int(bStr) { battery = b }
        }
        
        let simulatedState = ChargingState(
            isConnected: true,
            isCharging: true,
            watts: watts,
            batteryPercent: battery,
            adapterName: "MagSafe 3",
            timeRemainingMinutes: 35,
            timestamp: Date()
        )
        self.store.showChargingHUD(state: simulatedState)
    }
    
    @objc func handleSetSound(_ notif: Notification) {
        if let enabled = notif.userInfo?["enabled"] as? Bool {
            self.store.soundEnabled = enabled
        }
    }
    
    @objc func handleHide(_ notif: Notification) {
        self.store.hideChargingHUD()
    }
}

// MARK: - Application Main
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
