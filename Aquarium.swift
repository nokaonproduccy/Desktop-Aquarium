import AppKit
import CoreGraphics
import CryptoKit

enum Species: String, CaseIterable {
    case koi = "Koi", guppy = "Guppy", minnow = "Pearl minnow"
    var colors: (UInt32, UInt32) {
        switch self {
        case .koi: return (0xffead1, 0xde8271)
        case .guppy: return (0xb8e9eb, 0xa994d2)
        case .minnow: return (0xe8f5e6, 0x86bec8)
        }
    }
}

enum Water: String, CaseIterable {
    case seaGlass = "Sea Glass", jade = "Jade Lagoon", dusk = "Moonwater"
    var colors: (UInt32, UInt32) {
        switch self {
        case .seaGlass: return (0xb8eadc, 0x347f86)
        case .jade: return (0xb2dbb9, 0x266a60)
        case .dusk: return (0xc7c7ee, 0x485783)
        }
    }
}

func tint(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

struct Fish {
    let species: Species
    let phase: CGFloat
    let size: CGFloat
    var point: CGPoint
    var speed: CGFloat = 8
    var stroke: CGFloat = 0
    var angle: CGFloat
    var friendID: String? = nil
}

struct Food {
    var point: CGPoint
    let drift: CGFloat
    let born: CGFloat
}

enum Plant: String, Codable, CaseIterable {
    case algae, coral, kelp, stones, shell, driftwood
    case amberSnail, violetSnail, pinkStar, blueStar, shrimp
    case pearl, moonCoral, lantern, crystal

    var title: String {
        switch self {
        case .amberSnail: return "Amber snail"
        case .violetSnail: return "Violet snail"
        case .pinkStar: return "Pink starfish"
        case .blueStar: return "Blue starfish"
        case .moonCoral: return "Moon coral"
        default: return rawValue.capitalized
        }
    }
}

enum Sand: String, CaseIterable {
    case bare, ivory, rose, basalt, gravel
    var color: UInt32 {
        switch self {
        case .bare: return 0
        case .ivory: return 0xe1d0ab
        case .rose: return 0xbc8f86
        case .basalt: return 0x545e72
        case .gravel: return 0x9c907e
        }
    }
}

struct LinkStatus: Codable {
    let linkedSince: Double?
    let serverTime: Double
    let giftAfter: Double
}

struct Gift: Codable {
    let id: String
    let kind: Plant

    static let choices: [Plant] = [.shell, .pearl, .moonCoral, .lantern, .crystal]
}

struct SurfaceMode {
    var height: CGFloat = 0
    var velocity: CGFloat = 0

    mutating func step(_ dt: CGFloat, frequency: CGFloat, damping: CGFloat, limit: CGFloat) {
        let steps = max(1, Int(ceil(dt / 0.008)))
        let step = dt / CGFloat(steps)
        for _ in 0..<steps {
            velocity += (-frequency * frequency * height - damping * velocity) * step
            height += velocity * step
            if abs(height) > limit {
                height = clamp(height, -limit, limit)
                velocity *= -0.2
            }
        }
    }
}

struct Decoration: Codable {
    var kind: Plant
    var fraction: CGFloat
    var waterDepth: CGFloat? = nil
    var placedAt: Double? = nil
}

func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
    min(high, max(low, value))
}

struct FriendFish: Codable {
    let id: String
    let key: Data
    let name: String
    let species: String
}

struct FriendEnvelope: Codable {
    let id: String
    let sender: String
    let payload: String
}

struct FishNote: Codable {
    let text: String
    let species: String
}

struct MailboxItem: Codable {
    let id: String
    let payload: String
}

struct Pairing {
    let url: URL
    let token: String
    let key: SymmetricKey

    init?(url: String, token: String, secret: String) {
        guard let endpoint = URL(string: url), endpoint.scheme == "https",
              endpoint.host != nil, endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil, token.count >= 32,
              let bytes = Data(base64Encoded: secret), bytes.count == 32 else { return nil }
        self.url = endpoint
        self.token = token
        key = SymmetricKey(data: bytes)
    }

    func request(_ method: String, path: String, body: Data? = nil,
                 onFailure: ((Int) -> Void)? = nil, completion: @escaping (Data?) -> Void) {
        let target = path.split(separator: "/").reduce(url) {
            $0.appendingPathComponent(String($1))
        }
        var request = URLRequest(url: target, timeoutInterval: 12)
        request.httpMethod = method
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                let success = (200..<300).contains(status)
                if !success { onFailure?(status) }
                completion(success ? data ?? Data() : nil)
            }
        }.resume()
    }
}

final class Tank: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    let defaults = UserDefaults.standard
    var fish: [Fish] = []
    var food: [Food] = []
    var ripple: CGPoint = .zero
    var rippleAge: CGFloat = 10
    var elapsed: CGFloat = 0
    var clock: TimeInterval = 0
    var timer: Timer?
    var water = Water.seaGlass
    var mouseOrigin = CGPoint.zero
    var previousMouse = CGPoint.zero
    var initialWindowOrigin = CGPoint.zero
    var previousDragTime: TimeInterval = 0
    var dragVelocity = CGPoint.zero
    var primaryWave = SurfaceMode()
    var shortWave = SurfaceMode()
    var gravityPulse: CGFloat = 0
    var trayWidth: CGFloat { min(180, bounds.width - 24) }
    var trayFrame: CGRect { CGRect(x: 12, y: 8, width: trayWidth, height: 51) }
    let trayItems: [Plant] = [.algae, .coral, .kelp, .stones, .shell, .driftwood]
    let creatures: [Plant] = [.amberSnail, .violetSnail, .pinkStar, .blueStar, .shrimp]
    let rewards: [(Int, Plant)] = [(7, .pearl), (30, .moonCoral), (90, .lantern), (365, .crystal)]
    var status: LinkStatus?
    var gifts: [Gift] = []
    var nextPartnerRefresh: TimeInterval = 0
    var friends: [FriendFish] = []
    var friendInbox: (FriendEnvelope, FishNote)?
    var friendRequest = false
    var movingChest = false
    var addFishButton: CGRect {
        CGRect(x: 13, y: 88, width: 96, height: 22)
    }
    var fishPopover: NSPopover?
    var selectingFish = false
    var selectedFish: Set<Int> = []
    weak var fishDeleteButton: NSButton?
    var chestPopover: NSPopover?
    weak var receivedGiftsMenu: NSPopUpButton?
    var hoverArea: NSTrackingArea?
    var hoverPoint: CGPoint?
    var hoverSince: CGFloat?
    var hoveredFish: Int?
    var shrimpKicks: [Int: CGFloat] = [:]
    var lighting: CGFloat = 0
    var sand: Sand { Sand(rawValue: defaults.string(forKey: "sand") ?? "") ?? .bare }
    var floorY: CGFloat { bounds.height - (sand == .bare ? 7 : 13) }
    var chestFrame: CGRect {
        let fraction = defaults.object(forKey: "chestPosition") as? Double ?? 0.76
        return CGRect(x: bounds.width * CGFloat(fraction) - 13, y: floorY - 20, width: 26, height: 20)
    }
    var linkedDays: Int {
        guard let status, let start = status.linkedSince else { return 0 }
        return Int(max(0, status.serverTime - start) / 86400)
    }
    var agitation: CGFloat = 0
    var editing = false
    var pairing: Pairing?
    var pairingGeneration = UUID()
    var checkingMail = false
    var acknowledging = false
    var sending = false
    var nextMailCheck: TimeInterval = 0
    var incoming: (MailboxItem, FishNote)?
    var previewNote: FishNote?
    var visibleNote: FishNote? { previewNote ?? friendInbox?.1 ?? incoming?.1 }
    var needsFirstFish: Bool { fish.isEmpty && !defaults.bool(forKey: "finishedFishSetup") }
    var messageSpecies: String { fish.first?.species.rawValue ?? Species.koi.rawValue }
    var sendButton: CGRect {
        CGRect(x: 13, y: 63, width: 96, height: 23)
    }
    var resizing = false
    var pendingPlant: Plant?
    var movingDecoration: Int?
    var cursor = CGPoint.zero
    var decorations: [Decoration] = []
    var surface: CGFloat { bounds.height * 0.22 }
    var resizeHandle: CGRect {
        CGRect(x: bounds.maxX - 32, y: bounds.maxY - 32, width: 32, height: 32)
    }
    var dragging = false
    var pointerDown = false
    var counts: [Species: Int] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        for species in Species.allCases {
            if let value = defaults.object(forKey: species.rawValue) as? Int {
                counts[species] = max(0, value)
            }
        }
        water = Water(rawValue: defaults.string(forKey: "water") ?? "") ?? .seaGlass
        if let data = defaults.data(forKey: "decorations"),
           let saved = try? JSONDecoder().decode([Decoration].self, from: data) {
            decorations = saved.map { item in
                var item = item
                if item.placedAt == nil { item.placedAt = Date().timeIntervalSince1970 }
                return item
            }
            saveDecorations()
        }
        if let data = defaults.data(forKey: "friendFish"),
           let saved = try? JSONDecoder().decode([FriendFish].self, from: data) {
            friends = saved
        }
        stock()
        if let saved = defaults.stringArray(forKey: "messagePairing"), saved.count == 3 {
            pairing = Pairing(url: saved[0], token: saved[1], secret: saved[2])
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Aquarium. Feed the fish.")
        clock = ProcessInfo.processInfo.systemUptime
        timer = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(tick),
                      userInfo: nil, repeats: true)
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        feed(CGPoint(x: bounds.midX, y: bounds.midY))
        return true
    }

    func stock() {
        var next: [Fish] = []
        for species in Species.allCases {
            var existing = fish.filter { $0.species == species && $0.friendID == nil }
            let count = counts[species, default: 0]
            existing = Array(existing.prefix(count))
            while existing.count < count {
                existing.append(Fish(species: species, phase: .random(in: 0...30),
                    size: .random(in: 0.84...1.13),
                    point: CGPoint(x: bounds.width * .random(in: 0.25...0.75),
                                   y: bounds.height * .random(in: 0.40...0.77)),
                    angle: .random(in: 0...(2 * .pi))))
            }
            next.append(contentsOf: existing)
        }
        for friend in friends {
            if let existing = fish.first(where: { $0.friendID == friend.id }) {
                next.append(existing)
            } else {
                next.append(Fish(species: Species(rawValue: friend.species) ?? .koi,
                                 phase: .random(in: 0...30), size: 1,
                                 point: CGPoint(x: bounds.midX, y: bounds.midY),
                                 angle: .random(in: 0...(2 * .pi)), friendID: friend.id))
            }
        }
        fish = next
        if !fish.isEmpty { defaults.set(true, forKey: "finishedFishSetup") }
        hoverSince = nil
        hoveredFish = nil
        if fishPopover?.isShown == true {
            selectedFish.removeAll()
            updateFishManager()
        }
    }

    func feed(_ point: CGPoint) {
        let x = clamp(point.x, 12, bounds.width - 12)
        let y = clamp(point.y, surfaceY(at: x) + 6, bounds.height - 12)
        ripple = CGPoint(x: x, y: y)
        rippleAge = 0
        for offset in [-6.0, 0.0, 6.0] {
            let pelletX = clamp(x + CGFloat(offset), 8, bounds.width - 8)
            let pelletY = clamp(y + CGFloat.random(in: -3...3),
                                surfaceY(at: pelletX) + 4, bounds.height - 9)
            food.append(Food(point: CGPoint(x: pelletX, y: pelletY),
                             drift: .random(in: -2...2), born: elapsed))
        }
        if food.count > 60 { food.removeFirst(food.count - 60) }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        pointerDown = true
        mouseOrigin = window.convertPoint(toScreen: event.locationInWindow)
        previousMouse = mouseOrigin
        initialWindowOrigin = window.frame.origin
        previousDragTime = event.timestamp
        dragVelocity = .zero
        dragging = false
        resizing = false
        movingChest = false
        pendingPlant = nil
        movingDecoration = nil
        cursor = convert(event.locationInWindow, from: nil)
        if visibleNote != nil && bubbleFrame.contains(cursor) {
            cursor = CGPoint(x: -1, y: -1)
            if previewNote != nil {
                previewNote = nil
                needsDisplay = true
            } else if friendInbox != nil {
                dismissFriendNote()
            } else {
                dismissNote()
            }
            return
        }
        if !editing && chestFrame.insetBy(dx: -3, dy: -4).contains(cursor) {
            cursor = CGPoint(x: -1, y: -1)
            openChest()
            return
        }
        if !editing, let index = decorations.indices.reversed().first(where: {
            decorations[$0].kind == .shrimp &&
                distance(decorationAnchor(at: $0), CGPoint(x: cursor.x, y: cursor.y + 5)) < 13
        }) {
            shrimpKicks[index] = elapsed
            cursor = CGPoint(x: -1, y: -1)
            return
        }
        if event.clickCount == 2 && (fish.isEmpty || cursor.y < surfaceY(at: cursor.x)) {
            cursor = CGPoint(x: -1, y: -1)
            editing.toggle()
            needsDisplay = true
            return
        }
        if editing {
            if addFishButton.contains(cursor) {
                cursor = CGPoint(x: -1, y: -1)
                addFriend()
                return
            }
            if chestFrame.contains(cursor) {
                movingChest = true
                return
            }
            if sendButton.contains(cursor) {
                cursor = CGPoint(x: -1, y: -1)
                composeNote()
                return
            }
            if cursor.x > bounds.width - 39 && (63...86).contains(cursor.y) {
                editing = false
                cursor = CGPoint(x: -1, y: -1)
                needsDisplay = true
                return
            }
            resizing = resizeHandle.contains(cursor)
            if trayFrame.contains(cursor) {
                let row = cursor.y < trayFrame.minY + 25 ? trayItems : creatures
                let cellWidth = trayFrame.width / CGFloat(row.count)
                let slot = Int((cursor.x - trayFrame.minX) / cellWidth)
                pendingPlant = row[min(row.count - 1, slot)]
            } else if !resizing {
                movingDecoration = decorations.indices.reversed().first {
                    let anchor = decorationAnchor(at: $0)
                    let height: CGFloat = creatures.contains(decorations[$0].kind) ? 17 : 32
                    return CGRect(x: anchor.x - 14, y: anchor.y - height,
                                  width: 28, height: height + 5).contains(cursor)
                }
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, pointerDown, cursor.x >= 0, event.timestamp >= previousDragTime else { return }
        let location = window.convertPoint(toScreen: event.locationInWindow)
        let delta = location - previousMouse
        let total = location - mouseOrigin
        let threshold: CGFloat = editing && !resizing && pendingPlant == nil && movingDecoration == nil ? 9 : 4
        guard dragging || hypot(total.x, total.y) > threshold else { return }
        dragging = true
        if movingChest {
            let point = convert(window.convertPoint(fromScreen: location), from: nil)
            defaults.set(Double(clamp(point.x / bounds.width, 0.16, 0.86)), forKey: "chestPosition")
        } else if resizing {
            let frame = window.frame
            let size = CGSize(width: clamp(frame.width + delta.x, 150, 560),
                              height: clamp(frame.height - delta.y, 130, 460))
            window.setFrame(CGRect(x: frame.minX, y: frame.maxY - size.height,
                                   width: size.width, height: size.height), display: true)
            defaults.set([Double(size.width), Double(size.height)], forKey: "size")
        } else if pendingPlant != nil || movingDecoration != nil {
            cursor = convert(window.convertPoint(fromScreen: location), from: nil)
        } else {
            let dt = CGFloat(clamp(event.timestamp - previousDragTime, 0.012, 0.15))
            let velocity = CGPoint(x: delta.x / dt, y: delta.y / dt)
            let smoothing = dt / (dt + 0.035)
            let change = CGPoint(x: (velocity.x - dragVelocity.x) * smoothing,
                                 y: (velocity.y - dragVelocity.y) * smoothing)
            stir(change)
            dragVelocity.x += change.x
            dragVelocity.y += change.y
            window.setFrameOrigin(CGPoint(x: initialWindowOrigin.x + total.x,
                                          y: initialWindowOrigin.y + total.y))
        }
        previousMouse = location
        previousDragTime = event.timestamp
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard pointerDown else { return }
        pointerDown = false
        if dragging {
            if editing && !resizing && !movingChest {
                let drop = convert(event.locationInWindow, from: nil)
                let inside = bounds.contains(drop) && drop.y >= surfaceY(at: drop.x)
                if let index = movingDecoration {
                    if inside {
                        decorations[index] = placedDecoration(decorations[index].kind, at: drop)
                    } else {
                        decorations.remove(at: index)
                        shrimpKicks.removeAll()
                        movingDecoration = nil
                    }
                    saveDecorations()
                } else if let kind = pendingPlant, inside, drop.y > trayFrame.maxY, decorations.count < 40 {
                    decorations.append(placedDecoration(kind, at: drop))
                    saveDecorations()
                }
            }
            if event.timestamp - previousDragTime < 0.12 {
                let remaining = CGFloat(exp(-max(0, event.timestamp - previousDragTime) * 18))
                stir(CGPoint(x: -dragVelocity.x * remaining, y: -dragVelocity.y * remaining))
            }
            savePosition()
        } else if !editing && bounds.contains(cursor) && cursor.y >= surfaceY(at: cursor.x) {
            feed(cursor)
        }
        pendingPlant = nil
        movingDecoration = nil
        dragging = false
        needsDisplay = true
    }

    func saveDecorations() {
        if let data = try? JSONEncoder().encode(decorations) {
            defaults.set(data, forKey: "decorations")
        }
    }

    func stir(_ change: CGPoint) {
        primaryWave.velocity = clamp(primaryWave.velocity - change.x * 0.23, -180, 180)
        shortWave.velocity = clamp(shortWave.velocity - change.x * 0.022, -50, 50)
        gravityPulse = clamp(gravityPulse + change.y / 2600, -0.3, 0.35)
        agitation = clamp(agitation + hypot(change.x, change.y) / 1300, 0, 1)
    }

    func savePosition() {
        if let origin = window?.frame.origin {
            defaults.set([Double(origin.x), Double(origin.y)], forKey: "position")
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let add = NSMenuItem(title: "Add Fish…", action: #selector(addFriend), keyEquivalent: "")
        add.target = self
        menu.addItem(add)
        let code = NSMenuItem(title: "My Friend Code…", action: #selector(showFriendCode), keyEquivalent: "")
        code.target = self
        menu.addItem(code)
        let edit = NSMenuItem(title: editing ? "Done Editing" : "Edit Aquarium",
                              action: #selector(toggleEdit), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        let manage = NSMenuItem(title: "Manage Fish", action: #selector(openFishManager), keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)
        addKeepsakeMenus(to: menu)
        let pair = NSMenuItem(title: "Pair with a Friend…", action: #selector(configurePairing), keyEquivalent: "")
        pair.target = self
        menu.addItem(pair)
        let preview = NSMenuItem(title: "Preview a Message…", action: #selector(previewMessage),
                                 keyEquivalent: "")
        preview.target = self
        menu.addItem(preview)
        let feedItem = NSMenuItem(title: "Feed fish", action: #selector(feedCenter), keyEquivalent: "")
        feedItem.target = self
        menu.addItem(feedItem)
        menu.addItem(.separator())
        let palette = NSMenuItem(title: "Water color", action: nil, keyEquivalent: "")
        let colors = NSMenu()
        for preset in Water.allCases {
            let choice = NSMenuItem(title: preset.rawValue, action: #selector(changeWater(_:)), keyEquivalent: "")
            choice.target = self
            choice.state = preset == water ? .on : .off
            colors.addItem(choice)
        }
        palette.submenu = colors
        menu.addItem(palette)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Aquarium", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func toggleEdit() {
        editing.toggle()
        needsDisplay = true
    }

    @objc func feedCenter() { _ = accessibilityPerformPress() }

    @objc func openFishManager() {
        if let fishPopover, fishPopover.isShown { fishPopover.close(); return }
        let panel = NSPopover()
        panel.behavior = .transient
        panel.contentViewController = NSViewController()
        fishPopover = panel
        selectingFish = false
        selectedFish.removeAll()
        updateFishManager()
        let rightEdge = window?.screen?.visibleFrame.maxX ?? 1000
        let room = rightEdge - (window?.frame.maxX ?? 0)
        panel.show(relativeTo: bounds, of: self, preferredEdge: room >= 245 ? .maxX : .minX)
    }

    func updateFishManager() {
        guard let panel = fishPopover else { return }
        let width: CGFloat = 230
        let height: CGFloat = 234
        let content = NSView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        let title = NSTextField(labelWithString: "Manage Fish")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.frame = CGRect(x: 13, y: 198, width: 130, height: 24)
        content.addSubview(title)
        let select = NSButton(title: selectingFish ? "Cancel" : "Select", target: self, action: #selector(toggleFishSelection))
        select.frame = CGRect(x: 151, y: 196, width: 68, height: 26)
        select.isEnabled = !fish.isEmpty
        content.addSubview(select)
        let scroll = NSScrollView(frame: CGRect(x: 10, y: 44, width: 210, height: 145))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let gridHeight = max(145, CGFloat((fish.count + 2) / 3) * 64)
        let grid = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: gridHeight))
        for (index, swimmer) in fish.enumerated() {
            let name = friends.first { $0.id == swimmer.friendID }?.name ?? "Common fish"
            let image = NSImage(size: CGSize(width: 43, height: 27), flipped: true) { [weak self] rect in
                guard let self, let ctx = NSGraphicsContext.current?.cgContext else { return false }
                let icon = Fish(species: swimmer.species, phase: 0, size: 0.94,
                                point: CGPoint(x: rect.midX + 3, y: rect.midY), angle: 0)
                self.drawFish(icon, in: ctx)
                return true
            }
            let tile = NSButton(title: name, target: self, action: #selector(selectFishTile(_:)))
            tile.image = image
            tile.imagePosition = .imageAbove
            tile.font = .systemFont(ofSize: 10)
            tile.setButtonType(.pushOnPushOff)
            tile.tag = index
            tile.state = selectedFish.contains(index) ? .on : .off
            tile.isBordered = selectingFish
            tile.frame = CGRect(x: CGFloat(index % 3) * 65, y: gridHeight - CGFloat(index / 3 + 1) * 64,
                                width: 65, height: 61)
            tile.toolTip = name + " · " + swimmer.species.rawValue
            grid.addSubview(tile)
        }
        if fish.isEmpty {
            let empty = NSTextField(labelWithString: "Your tank is empty.")
            empty.textColor = .secondaryLabelColor
            empty.frame = CGRect(x: 5, y: 112, width: 194, height: 20)
            grid.addSubview(empty)
        }
        scroll.documentView = grid
        scroll.contentView.scroll(to: CGPoint(x: 0, y: gridHeight - 145))
        content.addSubview(scroll)
        let action = NSButton(title: selectingFish ? "Delete Selected" : "Add Fish…", target: self,
                              action: selectingFish ? #selector(deleteSelectedFish) : #selector(addFishFromManager))
        action.frame = CGRect(x: 12, y: 10, width: 133, height: 27)
        action.isEnabled = !selectingFish || !selectedFish.isEmpty
        fishDeleteButton = action
        content.addSubview(action)
        panel.contentViewController?.view = content
        panel.contentSize = content.frame.size
    }

    @objc func toggleFishSelection() {
        selectingFish.toggle()
        selectedFish.removeAll()
        updateFishManager()
    }

    @objc func selectFishTile(_ tile: NSButton) {
        guard selectingFish else { tile.state = .off; return }
        if tile.state == .on { selectedFish.insert(tile.tag) } else { selectedFish.remove(tile.tag) }
        fishDeleteButton?.isEnabled = !selectedFish.isEmpty
    }

    @objc func addFishFromManager() {
        fishPopover?.close()
        addFriend()
    }

    @objc func deleteSelectedFish() {
        let indices = selectedFish.sorted(by: >).filter { fish.indices.contains($0) }
        let linked = Set(indices.compactMap { fish[$0].friendID })
        if !linked.isEmpty {
            NSApp.activate(ignoringOtherApps: true)
            let confirmation = NSAlert()
            confirmation.messageText = "Are you sure?"
            confirmation.informativeText = "The selected linked fish will be removed from your tank and message recipients."
            confirmation.addButton(withTitle: "Cancel")
            confirmation.addButton(withTitle: "Remove Fish")
            guard confirmation.runModal() == .alertSecondButtonReturn else { return }
        }
        for index in indices {
            let swimmer = fish.remove(at: index)
            if swimmer.friendID == nil {
                counts[swimmer.species, default: 0] -= 1
                defaults.set(counts[swimmer.species, default: 0], forKey: swimmer.species.rawValue)
            }
        }
        if let sender = friendInbox?.0.sender, linked.contains(sender) { friendInbox = nil }
        friends.removeAll { linked.contains($0.id) }
        saveFriends()
        selectingFish = false
        selectedFish.removeAll()
        updateFishManager()
    }

    @objc func changeWater(_ sender: NSMenuItem) {
        guard let selected = Water(rawValue: sender.title) else { return }
        water = selected
        defaults.set(water.rawValue, forKey: "water")
        needsDisplay = true
    }

    @objc func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = CGFloat(min(now - clock, 0.067))
        clock = now
        if now >= nextMailCheck {
            nextMailCheck = now + 4
            checkFriendMail()
            checkMail()
        }
        if now >= nextPartnerRefresh {
            nextPartnerRefresh = now + 25
            refreshPartner()
            let time = Calendar.current.dateComponents([.hour, .minute], from: Date())
            let hour = Double(time.hour ?? 12) + Double(time.minute ?? 0) / 60
            lighting = defaults.object(forKey: "moonlight") as? Bool == false ? 0
                : CGFloat(max(0, cos(hour * .pi / 12)))
        }
        guard window?.occlusionState.contains(.visible) == true else { return }
        elapsed += dt
        updateFishHover()
        shrimpKicks = shrimpKicks.filter { elapsed - $0.value < 0.65 }
        rippleAge += dt
        food.removeAll { elapsed - $0.born > 9 }
        for index in food.indices {
            food[index].point.x = clamp(food[index].point.x + food[index].drift * dt, 8, bounds.width - 8)
            food[index].point.y = clamp(food[index].point.y + 3 * dt,
                                        surfaceY(at: food[index].point.x) + 4, bounds.height - 9)
        }
        let depth = bounds.height - surface
        let waveNumber = CGFloat.pi / max(1, bounds.width)
        let gravity = 2100 * (1 + gravityPulse)
        let primaryFrequency = sqrt(gravity * waveNumber * tanh(waveNumber * depth))
        let shortNumber = waveNumber * 3
        let shortFrequency = sqrt(gravity * shortNumber * tanh(shortNumber * depth))
        primaryWave.step(dt, frequency: primaryFrequency, damping: 3.5, limit: surface * 0.55)
        shortWave.step(dt, frequency: shortFrequency, damping: 6.0, limit: surface * 0.09)
        gravityPulse *= exp(-dt * 7)
        agitation = max(0, agitation - dt * 0.48)
        let motionScale: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.45 : 1
        let neighbors = fish
        for index in fish.indices {
            var swimmer = fish[index]
            let phase = swimmer.phase
            let time = elapsed * motionScale
            let left: CGFloat = 23
            let right = bounds.width - left
            let top = surfaceY(at: swimmer.point.x) + 15
            let bottom = bounds.height - 18
            let idle = CGPoint(x: bounds.midX + (bounds.width * 0.35) * sin(time * 0.19 + phase),
                               y: (top + bottom) / 2 + max(0, bottom - top) * 0.36 *
                                   cos(time * 0.23 + phase * 1.3))
            let closest = food.indices.min {
                distance(food[$0].point, swimmer.point) < distance(food[$1].point, swimmer.point)
            }
            let isSpeaking = swimmer.friendID != nil && swimmer.friendID == friendInbox?.0.sender
            let speakingPoint = CGPoint(x: bounds.midX + sin(elapsed * 1.3) * 4,
                                        y: bounds.height - 25 + sin(elapsed * 2) * 2)
            let goal = isSpeaking ? speakingPoint : (closest.map { food[$0].point } ?? idle)
            let toGoal = goal - swimmer.point
            let range = max(1, hypot(toGoal.x, toGoal.y))
            var steer = CGPoint(x: toGoal.x / range, y: toGoal.y / range)
            for other in neighbors.indices where other != index {
                let away = swimmer.point - neighbors[other].point
                let gap = hypot(away.x, away.y)
                if gap < 30 && gap > 0.1 {
                    let force = (30 - gap) / 30 * 1.65
                    steer.x += away.x / gap * force
                    steer.y += away.y / gap * force
                }
            }
            steer.x += clamp((left + 12 - swimmer.point.x) / 12, 0, 2)
                - clamp((swimmer.point.x - right + 12) / 12, 0, 2)
            steer.y += clamp((top + 9 - swimmer.point.y) / 9, 0, 2)
                - clamp((swimmer.point.y - bottom + 9) / 9, 0, 2)
            steer.x += cos(time * 4.1 + phase) * agitation * 0.8
            steer.y += sin(time * 4.8 + phase) * agitation * 0.7
            let heading = atan2(steer.y, steer.x)
            let turn = atan2(sin(heading - swimmer.angle), cos(heading - swimmer.angle))
            let turnRate: CGFloat = closest == nil ? 1.9 : 4.4
            swimmer.angle += clamp(turn, -dt * turnRate, dt * turnRate)
            let cruise: CGFloat = swimmer.species == .koi ? 15 : 19
            let targetSpeed = (closest == nil ? cruise : 52) + agitation * 31
            swimmer.speed += (targetSpeed - swimmer.speed) * min(1, dt * 3.4)
            swimmer.stroke += dt * (3 + swimmer.speed * 0.15) * motionScale
            let kick = 0.94 + 0.13 * sin(swimmer.stroke)
            let stride = min(isSpeaking ? range * 0.12 : .greatestFiniteMagnitude,
                             swimmer.speed * kick * dt * motionScale)
            swimmer.point.x = clamp(swimmer.point.x + cos(swimmer.angle) * stride, left, right)
            swimmer.point.y = clamp(swimmer.point.y + sin(swimmer.angle) * stride, top, bottom)
            let mouth = CGPoint(x: swimmer.point.x + cos(swimmer.angle) * 9,
                                y: swimmer.point.y + sin(swimmer.angle) * 9)
            if let closest, elapsed - food[closest].born > 0.18,
               distance(food[closest].point, mouth) < 9 {
                food.remove(at: closest)
            }
            fish[index] = swimmer
        }
        needsDisplay = true
    }

    func surfaceY(at x: CGFloat) -> CGFloat {
        let phase = x / max(1, bounds.width)
        let position = CGFloat.pi * phase
        return surface + primaryWave.height * cos(position) + shortWave.height * cos(3 * position)
    }

    func placedDecoration(_ kind: Plant, at point: CGPoint) -> Decoration {
        let x = clamp(point.x, 10, bounds.width - 10)
        let top = surfaceY(at: x) + 12
        let depth = max(1, floorY - top)
        let relative = creatures.contains(kind) && kind != .shrimp
            ? clamp((point.y - top) / depth, 0, 1) : nil
        return Decoration(kind: kind, fraction: x / bounds.width, waterDepth: relative,
                          placedAt: Date().timeIntervalSince1970)
    }

    func decorationAnchor(at index: Int) -> CGPoint {
        let item = decorations[index]
        let center = item.fraction * bounds.width
        let age = max(0, Date().timeIntervalSince1970 - (item.placedAt ?? Date().timeIntervalSince1970))
        var x = center
        var y = floorY
        switch item.kind {
        case .amberSnail, .violetSnail, .pinkStar, .blueStar:
            let snail = item.kind == .amberSnail || item.kind == .violetSnail
            let period: CGFloat = snail ? 36000 : 345600
            let phase = CGFloat(age.truncatingRemainder(dividingBy: Double(period))) / period * 2 * .pi
            x = clamp(center + sin(phase) * (snail ? 15 : 10), 10, bounds.width - 10)
            let top = surfaceY(at: x) + 12
            let range = max(1, floorY - top)
            let drift = (1 - cos(phase)) * (snail ? 4 : 2)
            y = clamp(top + range * (item.waterDepth ?? 1) - drift, top, floorY)
        case .shrimp:
            let phase = CGFloat(age.truncatingRemainder(dividingBy: 22)) / 22 * 2 * .pi
            x = clamp(center + sin(phase) * 14, 10, bounds.width - 10)
            let progress = (elapsed - (shrimpKicks[index] ?? -100)) / 0.65
            let jump = (0..<1).contains(progress) ? sin(.pi * progress) * 14 : 0
            y = floorY - (1 - cos(phase * 2)) * 1.6 - jump
        default:
            break
        }
        return CGPoint(x: x, y: y)
    }

    func drawPlant(_ kind: Plant, x: CGFloat, y: CGFloat, alpha: CGFloat = 1) {
        let plant = NSBezierPath()
        plant.lineCapStyle = .round
        switch kind {
        case .algae:
            tint(0x81bba2, 0.86 * alpha).setStroke()
            plant.lineWidth = 3
            let offsets: [CGFloat] = [-10, 0, 12]
            for offset in offsets {
                plant.move(to: CGPoint(x: x, y: y))
                plant.curve(to: CGPoint(x: x + offset, y: y - 28 + abs(offset) * 0.5),
                            controlPoint1: CGPoint(x: x + offset * 0.2 - 5, y: y - 8),
                            controlPoint2: CGPoint(x: x + offset + 5, y: y - 15))
            }
        case .coral:
            tint(0xe99e91, 0.88 * alpha).setStroke()
            plant.lineWidth = 3.4
            plant.move(to: CGPoint(x: x - 4, y: y))
            plant.curve(to: CGPoint(x: x + 2, y: y - 25),
                        controlPoint1: CGPoint(x: x + 1, y: y - 9),
                        controlPoint2: CGPoint(x: x + 1, y: y - 19))
            for (dx, dy) in [(-10, -19), (12, -20), (-12, -10)] {
                plant.move(to: CGPoint(x: x, y: y - 7))
                plant.line(to: CGPoint(x: x + CGFloat(dx), y: y + CGFloat(dy)))
            }
        case .kelp:
            tint(0x63a272, 0.91 * alpha).setFill()
            let leans: [CGFloat] = [-1, 1]
            for lean in leans {
                plant.move(to: CGPoint(x: x, y: y))
                plant.curve(to: CGPoint(x: x + 10 * lean, y: y - 32),
                            controlPoint1: CGPoint(x: x - 8 * lean, y: y - 17),
                            controlPoint2: CGPoint(x: x + 17 * lean, y: y - 21))
                plant.curve(to: CGPoint(x: x, y: y),
                            controlPoint1: CGPoint(x: x + 19 * lean, y: y - 18),
                            controlPoint2: CGPoint(x: x + 1 * lean, y: y - 14))
                plant.close()
            }
            plant.fill()
            return
        case .stones:
            for (dx, dy, width, height, color) in [
                (-13.0, -9.0, 25.0, 9.0, UInt32(0x778b99)),
                (-5.0, -16.0, 17.0, 10.0, UInt32(0xa1b0bc)),
                (3.0, -7.0, 13.0, 7.0, UInt32(0xc0b8ad))
            ] {
                tint(color, 0.9 * alpha).setFill()
                NSBezierPath(ovalIn: CGRect(x: x + CGFloat(dx), y: y + CGFloat(dy),
                                           width: CGFloat(width), height: CGFloat(height))).fill()
            }
            return
        case .shell:
            let shell = NSBezierPath(ovalIn: CGRect(x: x - 11, y: y - 15, width: 22, height: 15))
            tint(0xf1ccab, 0.94 * alpha).setFill()
            shell.fill()
            tint(0xb78788, 0.75 * alpha).setStroke()
            plant.lineWidth = 1
            let ribs: [CGFloat] = [-7, -3, 3, 7]
            for dx in ribs {
                plant.move(to: CGPoint(x: x, y: y - 2))
                plant.line(to: CGPoint(x: x + dx, y: y - 12))
            }
        case .driftwood:
            tint(0xb68b71, 0.95 * alpha).setStroke()
            plant.lineWidth = 5
            plant.move(to: CGPoint(x: x - 14, y: y - 2))
            plant.curve(to: CGPoint(x: x + 13, y: y - 14),
                        controlPoint1: CGPoint(x: x - 5, y: y - 2),
                        controlPoint2: CGPoint(x: x + 8, y: y - 8))
            plant.move(to: CGPoint(x: x + 2, y: y - 6))
            plant.line(to: CGPoint(x: x - 4, y: y - 19))
        case .amberSnail, .violetSnail:
            tint(0xa8afa0, alpha).setFill()
            NSBezierPath(ovalIn: CGRect(x: x - 10, y: y - 5, width: 21, height: 5)).fill()
            tint(kind == .amberSnail ? 0xc89965 : 0xaa8ebd, alpha).setFill()
            NSBezierPath(ovalIn: CGRect(x: x - 7, y: y - 14, width: 13, height: 13)).fill()
            tint(0xffedda, 0.7 * alpha).setStroke()
            NSBezierPath(ovalIn: CGRect(x: x - 4, y: y - 11, width: 6, height: 6)).stroke()
        case .pinkStar, .blueStar:
            for i in 0..<10 {
                let angle = CGFloat(i) * .pi / 5 - .pi / 2
                let radius: CGFloat = i.isMultiple(of: 2) ? 9 : 4
                let point = CGPoint(x: x + cos(angle) * radius, y: y - 8 + sin(angle) * radius)
                if i == 0 { plant.move(to: point) } else { plant.line(to: point) }
            }
            plant.close()
            tint(kind == .pinkStar ? 0xe99eac : 0x8fbaca, alpha).setFill()
            plant.fill()
        case .shrimp:
            tint(0xf5a99a, alpha).setStroke()
            plant.lineWidth = 2.5
            plant.move(to: CGPoint(x: x - 7, y: y - 3))
            plant.curve(to: CGPoint(x: x + 6, y: y - 5),
                        controlPoint1: CGPoint(x: x + 2, y: y - 12),
                        controlPoint2: CGPoint(x: x + 6, y: y - 10))
            plant.line(to: CGPoint(x: x + 3, y: y - 2))
        case .pearl, .moonCoral, .lantern, .crystal:
            let color: UInt32
            switch kind {
            case .pearl: color = 0xffe5d3
            case .moonCoral: color = 0xaf9dd7
            case .lantern: color = 0xffca79
            default: color = 0x9be2dc
            }
            if kind == .moonCoral { drawPlant(.coral, x: x, y: y, alpha: alpha * 0.54) }
            let orb = NSBezierPath(ovalIn: CGRect(x: x - 7, y: y - 15, width: 14, height: 14))
            NSGradient(starting: tint(0xffffff, alpha), ending: tint(color, alpha))?.draw(in: orb, angle: 70)
        }
        plant.stroke()
    }

    func drawGlass(_ frame: CGRect, radius: CGFloat, opacity: CGFloat) {
        let shape = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        NSGradient(starting: tint(0x40565b, opacity * 0.83),
                   ending: tint(0x1a2d33, opacity))?.draw(in: shape, angle: 90)
        tint(0xf2ffff, 0.23).setStroke()
        shape.lineWidth = 0.65
        shape.stroke()
    }

    func drawEditor() {
        drawGlass(trayFrame, radius: 11, opacity: 0.66)
        if let context = NSGraphicsContext.current?.cgContext {
            for (rowIndex, row) in [trayItems, creatures].enumerated() {
                let width = trayFrame.width / CGFloat(row.count)
                for (index, kind) in row.enumerated() {
                    let x = trayFrame.minX + (CGFloat(index) + 0.5) * width
                    context.saveGState()
                    context.translateBy(x: x, y: trayFrame.minY + 23 + CGFloat(rowIndex) * 24)
                    context.scaleBy(x: 0.6, y: 0.6)
                    drawPlant(kind, x: 0, y: 0)
                    context.restoreGState()
                }
            }
        }
        drawGlass(addFishButton, radius: 10, opacity: 0.84)
        drawGlass(sendButton, radius: sendButton.height / 2, opacity: 0.84)
        let done = CGRect(x: bounds.width - 39, y: sendButton.minY,
                          width: 31, height: sendButton.height)
        drawGlass(done, radius: 10, opacity: 0.67)
        let label = "Done"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        for (title, frame) in [("Send Message", sendButton), ("Add Fish", addFishButton), (label, done)] {
            let text = title as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2),
                      withAttributes: attributes)
        }
        let grip = NSBezierPath()
        let insets: [CGFloat] = [13, 19]
        for inset in insets {
            grip.move(to: CGPoint(x: bounds.width - inset, y: bounds.height - 5))
            grip.line(to: CGPoint(x: bounds.width - 5, y: bounds.height - inset))
        }
        tint(0xffffff, 0.85).setStroke()
        grip.lineWidth = 1.5
        grip.stroke()
        if dragging, bounds.contains(cursor), cursor.y >= surfaceY(at: cursor.x),
           let kind = pendingPlant ?? movingDecoration.map({ decorations[$0].kind }) {
            let placement = placedDecoration(kind, at: cursor)
            let x = placement.fraction * bounds.width
            let top = surfaceY(at: x) + 12
            let y = placement.waterDepth.map { top + max(1, floorY - top) * $0 } ?? floorY
            drawPlant(kind, x: x, y: y, alpha: 0.7)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.65, dy: 0.65), xRadius: 24, yRadius: 24)
        ctx.saveGState()
        edge.addClip()
        NSGradient(starting: tint(0xffffff, 0.13), ending: tint(0xe0f4ef, 0.02))?.draw(in: bounds, angle: 90)
        let (light, dark) = water.colors
        let waterline = NSBezierPath()
        waterline.move(to: CGPoint(x: 0, y: surfaceY(at: 0)))
        for index in 1...24 {
            let x = bounds.width * CGFloat(index) / 24
            waterline.line(to: CGPoint(x: x, y: surfaceY(at: x)))
        }
        let liquid = NSBezierPath()
        liquid.append(waterline)
        liquid.line(to: CGPoint(x: bounds.width, y: bounds.height))
        liquid.line(to: CGPoint(x: 0, y: bounds.height))
        liquid.close()
        ctx.saveGState()
        liquid.addClip()
        let crest = surface - abs(primaryWave.height) - abs(shortWave.height)
        let waterRect = CGRect(x: 0, y: crest, width: bounds.width, height: bounds.height - crest)
        NSGradient(starting: tint(light, 0.28), ending: tint(dark, 0.56))?.draw(in: waterRect, angle: 90)
        let reflection = NSBezierPath()
        reflection.move(to: CGPoint(x: 0, y: surfaceY(at: 0) + 3))
        for index in 1...24 {
            let x = bounds.width * CGFloat(index) / 24
            reflection.line(to: CGPoint(x: x, y: surfaceY(at: x) + 3))
        }
        tint(light, 0.22).setStroke()
        reflection.lineWidth = 3
        reflection.stroke()
        tint(0x213b73, 0.27 * lighting).setFill()
        NSBezierPath(rect: waterRect).fill()
        drawSand()
        for (index, item) in decorations.enumerated() where !dragging || movingDecoration != index {
            let anchor = decorationAnchor(at: index)
            drawPlant(item.kind, x: anchor.x, y: anchor.y)
        }
        drawChest()
        for index in 0..<6 {
            let n = CGFloat(index)
            let y = bounds.height - 6 - (elapsed * (3 + n * 0.4) + 24 * n).truncatingRemainder(dividingBy: bounds.height - surface - 6)
            let x = bounds.width * (0.10 + 0.16 * n) + sin(elapsed * 0.5 + n) * 4
            let bubble = NSBezierPath(ovalIn: CGRect(x: x, y: y, width: 3 + n / 3, height: 3 + n / 3))
            bubble.lineWidth = 0.65
            tint(0xe6fffa, 0.32).setStroke()
            bubble.stroke()
        }
        if rippleAge < 1.4 {
            for index in 0..<2 {
                let age = rippleAge - CGFloat(index) * 0.18
                if age < 0 { continue }
                let r = 3 + age * 25
                let ring = NSBezierPath(ovalIn: CGRect(x: ripple.x - r, y: ripple.y - r,
                                                       width: 2 * r, height: 2 * r))
                tint(0xf4ffff, max(0, 0.55 - age * 0.4)).setStroke()
                ring.lineWidth = 0.8
                ring.stroke()
            }
        }
        for pellet in food {
            let alpha = clamp((9 - (elapsed - pellet.born)) * 2, 0, 1)
            let dot = NSBezierPath(ovalIn: CGRect(x: pellet.point.x - 1.8, y: pellet.point.y - 1.8,
                                                 width: 3.6, height: 3.6))
            tint(0xffd99d, 0.95 * alpha).setFill()
            dot.fill()
            tint(0x573c2f, 0.73 * alpha).setStroke()
            dot.lineWidth = 0.7
            dot.stroke()
        }
        for swimmer in fish {
            drawFish(swimmer, in: ctx)
            let age = (elapsed + swimmer.phase).truncatingRemainder(dividingBy: 11)
            if age < 1.5 {
                let bubble = NSBezierPath(ovalIn: CGRect(x: swimmer.point.x + 6,
                    y: swimmer.point.y - 8 - age * 9, width: 2.5, height: 2.5))
                tint(0xd6ffff, 0.55 * (1 - age / 1.5)).setStroke()
                bubble.lineWidth = 0.6
                bubble.stroke()
            }
        }
        if let note = visibleNote, friendInbox == nil || previewNote != nil {
            let guest = Fish(species: Species(rawValue: note.species) ?? .koi, phase: 0, size: 1,
                             point: guestPoint, stroke: elapsed * 4, angle: -0.15)
            drawFish(guest, in: ctx, highlighted: true)
        }
        ctx.restoreGState()
        tint(0xe7fff7, 0.65).setStroke()
        waterline.lineWidth = 1.05
        waterline.stroke()
        if editing {
            drawEditor()
        } else if needsFirstFish {
            let text = "Double-click to add a fish" as NSString
            var attrs = bubbleTextAttributes
            attrs[.font] = NSFont.systemFont(ofSize: 10, weight: .medium)
            let size = text.size(withAttributes: attrs)
            let frame = CGRect(x: bounds.midX - size.width / 2 - 6, y: bounds.midY - 10,
                               width: size.width + 12, height: 21)
            drawGlass(frame, radius: 8, opacity: 0.66)
            text.draw(at: CGPoint(x: frame.minX + 6, y: frame.minY + 3), withAttributes: attrs)
        }
        drawFishName()
        if let note = visibleNote { drawBubble(note) }
        ctx.restoreGState()
        tint(0xf5ffff, 0.34).setStroke()
        edge.lineWidth = 0.85
        edge.stroke()
    }

    var guestPoint: CGPoint {
        if previewNote == nil, let sender = friendInbox?.0.sender,
           let friend = fish.first(where: { $0.friendID == sender }) {
            return friend.point
        }
        return CGPoint(x: bounds.midX + sin(elapsed * 1.3) * 6,
                y: bounds.height - 24 + sin(elapsed * 2) * 3.5)
    }

    var bubbleTextAttributes: [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byCharWrapping
        return [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style
        ]
    }

    func bubbleLayout(for note: FishNote) -> (frame: CGRect, text: NSTextStorage, layout: NSLayoutManager, glyphs: NSRange) {
        let text = NSTextStorage(string: note.text, attributes: bubbleTextAttributes)
        let width = min(216, bounds.width - 40, ceil(text.size().width) + 2)
        let container = NSTextContainer(size: CGSize(width: width, height: 2048))
        container.lineFragmentPadding = 0
        let layout = NSLayoutManager()
        layout.addTextContainer(container)
        text.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(for: container)
        let height = max(15, ceil(layout.usedRect(for: container).maxY)) + 12
        let bubbleWidth = width + 18
        let x = clamp(guestPoint.x - bubbleWidth / 2, 12, bounds.width - bubbleWidth - 12)
        let bottom = max(height + 4, guestPoint.y - 18)
        return (CGRect(x: x, y: bottom - height, width: bubbleWidth, height: height), text, layout, glyphs)
    }

    var bubbleFrame: CGRect {
        guard let note = visibleNote else { return .zero }
        return bubbleLayout(for: note).frame
    }

    func drawBubble(_ note: FishNote) {
        let bubble = bubbleLayout(for: note)
        let frame = bubble.frame
        drawGlass(frame, radius: min(12, frame.height / 2), opacity: 0.86)
        let pointer = NSBezierPath()
        let pointerX = clamp(guestPoint.x, frame.minX + 7, frame.maxX - 7)
        pointer.move(to: CGPoint(x: pointerX - 4, y: frame.maxY))
        pointer.line(to: CGPoint(x: pointerX, y: frame.maxY + 5))
        pointer.line(to: CGPoint(x: pointerX + 4, y: frame.maxY))
        pointer.close()
        tint(0x1a2d33, 0.86).setFill()
        pointer.fill()
        withExtendedLifetime(bubble.text) {
            bubble.layout.drawGlyphs(forGlyphRange: bubble.glyphs,
                                     at: CGPoint(x: frame.minX + 9, y: frame.minY + 6))
        }
    }

    @objc func previewMessage() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Preview a Message"
        alert.informativeText = "See what your friend will see. This preview stays on your Mac."
        let field = NSTextField(string: "hello from the other side of the pond ♥")
        field.frame = CGRect(x: 0, y: 0, width: 295, height: 25)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Preview")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { return }
        let species = messageSpecies
        previewNote = FishNote(text: String(text.prefix(72)), species: species)
        needsDisplay = true
    }

    func notice(_ title: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

    @objc func configurePairing() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Pair with a Friend"
        alert.informativeText = "Enter the HTTPS relay URL, your own mailbox token, and the shared message key."
        let url = NSTextField(string: defaults.stringArray(forKey: "messagePairing")?.first ?? "")
        url.placeholderString = "https://your-relay.example"
        let token = NSSecureTextField()
        token.placeholderString = "Your mailbox token"
        let secret = NSSecureTextField()
        secret.placeholderString = "Shared message key"
        let fields = NSView(frame: CGRect(x: 0, y: 0, width: 310, height: 86))
        for (index, field) in [url, token, secret].enumerated() {
            field.frame = CGRect(x: 0, y: 60 - 29 * index, width: 310, height: 24)
            fields.addSubview(field)
        }
        alert.accessoryView = fields
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if pairing != nil { alert.addButton(withTitle: "Disconnect") }
        let result = alert.runModal()
        if result == .alertThirdButtonReturn {
            defaults.removeObject(forKey: "messagePairing")
            pairing = nil
        } else if result == .alertFirstButtonReturn {
            let values = [url.stringValue, token.stringValue, secret.stringValue].map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let valid = Pairing(url: values[0], token: values[1], secret: values[2]) else {
                notice("Check your pairing details", "Use an HTTPS URL and the token and key generated for the relay.")
                return
            }
            pairing = valid
            defaults.set(values, forKey: "messagePairing")
        } else { return }
        pairingGeneration = UUID()
        status = nil
        gifts = []
        nextPartnerRefresh = 0
        checkingMail = false
        acknowledging = false
        sending = false
        incoming = nil
        nextMailCheck = 0
    }

    func composeNote(draft: String = "") {
        if !friends.isEmpty { composeForFriends(draft); return }
        guard !sending else { return }
        guard let pairing else { configurePairing(); return }
        let species = messageSpecies
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Send Message"
        alert.informativeText = "Your note can be up to 72 characters."
        let field = NSTextField(string: draft)
        field.frame = CGRect(x: 0, y: 0, width: 295, height: 25)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let message = field.stringValue.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !message.isEmpty else { return }
        guard message.count <= 72, message.utf8.count <= 320 else {
            notice("Message is too long", "Keep your note to 72 characters.")
            composeNote(draft: message)
            return
        }
        let note = FishNote(text: message, species: species)
        let generation = pairingGeneration
        do {
            let encoded = try JSONEncoder().encode(note)
            let sealed = try AES.GCM.seal(encoded, using: pairing.key)
            guard let combined = sealed.combined else { return }
            let item = MailboxItem(id: UUID().uuidString, payload: combined.base64EncodedString())
            let body = try JSONEncoder().encode(item)
            sending = true
            sendNote(body, draft: message, pairing: pairing, generation: generation, retry: true)
        } catch {
            notice("Couldn’t prepare your message", "Open Send Message to try again.")
        }
    }

    func sendNote(_ body: Data, draft: String, pairing: Pairing, generation: UUID, retry: Bool) {
        pairing.request("POST", path: "messages", body: body) { [weak self] data in
            guard let self, self.pairingGeneration == generation else { return }
            if data == nil && retry {
                self.sendNote(body, draft: draft, pairing: pairing, generation: generation, retry: false)
                return
            }
            self.sending = false
            if data == nil {
                self.notice("Delivery couldn’t be confirmed", "Check the relay connection. Your note is still in the composer.")
                self.composeNote(draft: draft)
            }
        }
    }

    func checkMail() {
        guard let pairing, incoming == nil, !checkingMail, !acknowledging else { return }
        checkingMail = true
        let generation = pairingGeneration
        pairing.request("GET", path: "messages") { [weak self] data in
            guard let self, self.pairingGeneration == generation else { return }
            self.checkingMail = false
            guard let data, let item = try? JSONDecoder().decode(MailboxItem.self, from: data),
                  let bytes = Data(base64Encoded: item.payload),
                  let box = try? AES.GCM.SealedBox(combined: bytes),
                  let message = try? AES.GCM.open(box, using: pairing.key),
                  let note = try? JSONDecoder().decode(FishNote.self, from: message) else { return }
            self.incoming = (item, note)
            self.needsDisplay = true
        }
    }

    func dismissNote() {
        guard let pairing, let current = incoming, !acknowledging else { return }
        let generation = pairingGeneration
        acknowledging = true
        incoming = nil
        needsDisplay = true
        pairing.request("DELETE", path: "messages/" + current.0.id) { [weak self] data in
            guard let self, self.pairingGeneration == generation else { return }
            self.acknowledging = false
            if data == nil { self.incoming = current }
            self.nextMailCheck = 0
            self.needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        hoverPoint = convert(event.locationInWindow, from: nil)
        hoverSince = nil
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) {
        hoverPoint = nil
        hoverSince = nil
        needsDisplay = true
    }

    func updateFishHover() {
        guard !editing, !pointerDown, let point = hoverPoint else {
            hoverSince = nil
            hoveredFish = nil
            return
        }
        if hoverSince == nil {
            hoveredFish = fish.indices.first {
                fish[$0].friendID != nil && distance(point, fish[$0].point) < 23
            }
            if hoveredFish != nil { hoverSince = elapsed }
        }
    }

    func drawFishName() {
        guard let since = hoverSince, elapsed - since >= 1.5, let index = hoveredFish,
              fish.indices.contains(index) else { return }
        let name = friends.first { $0.id == fish[index].friendID }?.name ?? ""
        guard !name.isEmpty else { return }
        let attrs = bubbleTextAttributes
        let text = name as NSString
        let size = text.size(withAttributes: attrs)
        let width = min(bounds.width - 12, size.width + 12)
        let point = fish[index].point
        let frame = CGRect(x: clamp(point.x - width / 2, 6, bounds.width - width - 6),
                           y: max(5, point.y - 32), width: width, height: 19)
        drawGlass(frame, radius: 8, opacity: 0.79)
        text.draw(with: frame.insetBy(dx: 5, dy: 2), options: [.truncatesLastVisibleLine], attributes: attrs)
    }

    func addKeepsakeMenus(to menu: NSMenu) {
        let hello = NSMenuItem(title: "Send a hello ♥", action: #selector(sendHello), keyEquivalent: "")
        hello.target = self
        menu.addItem(hello)
        let moon = NSMenuItem(title: "Automatic moonlight", action: #selector(toggleMoon), keyEquivalent: "")
        moon.target = self
        moon.state = defaults.object(forKey: "moonlight") as? Bool == false ? .off : .on
        menu.addItem(moon)
        let sandMenu = NSMenu()
        for kind in Sand.allCases {
            let item = NSMenuItem(title: kind.rawValue.capitalized, action: #selector(selectSand(_:)), keyEquivalent: "")
            item.representedObject = kind.rawValue
            item.target = self
            item.state = sand == kind ? .on : .off
            sandMenu.addItem(item)
        }
        let substrate = NSMenuItem(title: "Tank floor", action: nil, keyEquivalent: "")
        substrate.submenu = sandMenu
        menu.addItem(substrate)
        let extras = NSMenu()
        for (days, kind) in rewards {
            let choice = decorationAction(kind)
            if linkedDays < days {
                choice.title += " · \(days) days"
                choice.action = nil
            }
            extras.addItem(choice)
        }
        let decor = NSMenuItem(title: "Milestones", action: nil, keyEquivalent: "")
        decor.submenu = extras
        menu.addItem(decor)
    }

    func decorationAction(_ kind: Plant) -> NSMenuItem {
        let item = NSMenuItem(title: kind.title, action: #selector(placeExtra(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = kind.rawValue
        return item
    }

    @objc func placeExtra(_ item: NSMenuItem) {
        guard let value = item.representedObject as? String, let kind = Plant(rawValue: value) else { return }
        addDecoration(kind)
    }

    func addDecoration(_ kind: Plant) {
        guard decorations.count < 40 else { return }
        let position = (1...8).map { CGFloat($0) / 10 }.max { a, b in
            let first = decorations.map { abs($0.fraction - a) }.min() ?? 1
            let second = decorations.map { abs($0.fraction - b) }.min() ?? 1
            return first < second
        } ?? 0.5
        decorations.append(Decoration(kind: kind, fraction: position))
        saveDecorations()
        needsDisplay = true
    }

    @objc func toggleMoon() {
        defaults.set(defaults.object(forKey: "moonlight") as? Bool == false, forKey: "moonlight")
        nextPartnerRefresh = 0
    }

    @objc func selectSand(_ item: NSMenuItem) {
        defaults.set(item.representedObject as? String, forKey: "sand")
        needsDisplay = true
    }

    func drawSand() {
        guard sand != .bare else { return }
        let bed = NSBezierPath()
        bed.move(to: CGPoint(x: 0, y: floorY))
        bed.curve(to: CGPoint(x: bounds.width, y: floorY + 1),
                  controlPoint1: CGPoint(x: bounds.width * 0.33, y: floorY - 6),
                  controlPoint2: CGPoint(x: bounds.width * 0.67, y: floorY + 4))
        bed.line(to: CGPoint(x: bounds.width, y: bounds.height))
        bed.line(to: CGPoint(x: 0, y: bounds.height))
        bed.close()
        tint(sand.color, 0.83).setFill()
        bed.fill()
        for i in 0..<Int(bounds.width / 4) {
            let grain: CGFloat = sand == .gravel ? CGFloat(2 + i % 4) : CGFloat(1 + i % 2)
            tint(i.isMultiple(of: 2) ? 0xffffff : 0x293340, 0.24).setFill()
            NSBezierPath(ovalIn: CGRect(x: CGFloat(i * 4), y: floorY + CGFloat(2 + (i * 7) % 9),
                                       width: grain, height: grain * 0.7)).fill()
        }
    }

    var socialAccount: Pairing? {
        guard let values = defaults.stringArray(forKey: "socialAccount"), values.count == 3,
              let privateKey = socialKey else { return nil }
        return Pairing(url: values[0], token: values[2], secret: privateKey.rawRepresentation.base64EncodedString())
    }

    var socialKey: Curve25519.KeyAgreement.PrivateKey? {
        if let bytes = defaults.data(forKey: "socialKey") {
            return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bytes)
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        defaults.set(key.rawRepresentation, forKey: "socialKey")
        return key
    }

    func friendKey(_ friend: FriendFish) throws -> SymmetricKey? {
        guard let own = socialKey else { return nil }
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: friend.key)
        let secret = try own.sharedSecretFromKeyAgreement(with: peer)
        return secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(),
                                               sharedInfo: Data("Koi friend notes v1".utf8), outputByteCount: 32)
    }

    @objc func showFriendCode() {
        NSApp.activate(ignoringOtherApps: true)
        if socialAccount == nil {
            let alert = NSAlert()
            alert.messageText = "Set up your friend code"
            alert.informativeText = "Enter the HTTPS relay address, mailbox ID, and private token provided by the relay host."
            let url = NSTextField()
            let id = NSTextField()
            let token = NSSecureTextField()
            url.placeholderString = "https://relay.example"
            id.placeholderString = "Mailbox ID"
            token.placeholderString = "Private token"
            let form = NSView(frame: CGRect(x: 0, y: 0, width: 290, height: 86))
            for (index, field) in [url, id, token].enumerated() {
                field.frame = CGRect(x: 0, y: CGFloat(60 - index * 29), width: 290, height: 24)
                form.addSubview(field)
            }
            alert.accessoryView = form
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn, let key = socialKey else { return }
            let values = [url, id, token].map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard validMailbox(values[1]),
                  Pairing(url: values[0], token: values[2], secret: key.rawRepresentation.base64EncodedString()) != nil else {
                notice("Check relay details", "Use your HTTPS relay address and the mailbox credentials from its host.")
                return
            }
            defaults.set(values, forKey: "socialAccount")
        }
        guard let id = defaults.stringArray(forKey: "socialAccount")?[1], let key = socialKey else { return }
        let value = "koi1." + id + "." + key.publicKey.rawRepresentation.base64EncodedString()
        let alert = NSAlert()
        alert.messageText = "My Friend Code"
        alert.informativeText = "Share this code with friends using your relay. Add their codes too."
        let field = NSTextField(string: value)
        field.frame = CGRect(x: 0, y: 0, width: 350, height: 24)
        field.isEditable = false
        field.isSelectable = true
        alert.accessoryView = field
        alert.addButton(withTitle: "Copy Code")
        alert.addButton(withTitle: "Done")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    }

    func validMailbox(_ id: String) -> Bool {
        id.range(of: "^[a-zA-Z0-9_-]{1,48}$", options: .regularExpression) != nil
    }

    @objc func addFriend() {
        NSApp.activate(ignoringOtherApps: true)
        let first = NSAlert()
        first.messageText = "Add a fish"
        let code = NSTextField()
        code.placeholderString = "Friend code"
        let name = NSTextField()
        name.placeholderString = "Your friend's name"
        let fields = NSView(frame: CGRect(x: 0, y: 0, width: 290, height: 57))
        code.frame = CGRect(x: 0, y: 30, width: 290, height: 24)
        name.frame = CGRect(x: 0, y: 0, width: 290, height: 24)
        fields.addSubview(code)
        fields.addSubview(name)
        first.accessoryView = fields
        first.window.initialFirstResponder = code
        first.addButton(withTitle: "Next")
        first.addButton(withTitle: "Add a common fish")
        first.addButton(withTitle: "Cancel")
        let result = first.runModal()
        if result == .alertSecondButtonReturn {
            addCommonFish()
            return
        }
        guard result == .alertFirstButtonReturn else { return }
        let parts = code.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        let label = String(name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(35))
        guard parts.count == 3, parts[0] == "koi1", validMailbox(String(parts[1])), !label.isEmpty,
              let key = Data(base64Encoded: String(parts[2])),
              (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: key)) != nil else {
            notice("Check the friend code and name", "Paste the code from My Friend Code and enter a name.")
            return
        }
        let id = String(parts[1])
        guard id != defaults.stringArray(forKey: "socialAccount")?[1], !friends.contains(where: { $0.id == id }) else {
            notice("That code is already in use", "Choose a different friend code.")
            return
        }
        let second = NSAlert()
        second.messageText = "Choose a fish for " + label
        let choices = NSPopUpButton(frame: CGRect(x: 0, y: 0, width: 210, height: 26), pullsDown: false)
        choices.addItems(withTitles: Species.allCases.map { $0.rawValue })
        second.accessoryView = choices
        second.addButton(withTitle: "Save")
        second.addButton(withTitle: "Cancel")
        guard second.runModal() == .alertFirstButtonReturn, let species = choices.titleOfSelectedItem else { return }
        friends.append(FriendFish(id: id, key: key, name: label, species: species))
        saveFriends()
        if socialAccount == nil { showFriendCode() }
    }

    func addCommonFish() {
        let alert = NSAlert()
        alert.messageText = "Add a common fish"
        let choices = NSPopUpButton(frame: CGRect(x: 0, y: 0, width: 210, height: 26), pullsDown: false)
        choices.addItems(withTitles: Species.allCases.map { $0.rawValue })
        alert.accessoryView = choices
        alert.addButton(withTitle: "Add Fish")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn,
              let title = choices.titleOfSelectedItem, let species = Species(rawValue: title) else { return }
        let count = counts[species, default: 0] + 1
        counts[species] = count
        defaults.set(count, forKey: species.rawValue)
        stock()
        needsDisplay = true
    }

    func saveFriends() {
        if let data = try? JSONEncoder().encode(friends) { defaults.set(data, forKey: "friendFish") }
        stock()
        needsDisplay = true
    }

    func composeForFriends(_ draft: String) {
        guard !sending else { return }
        guard let account = socialAccount else { showFriendCode(); return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Send a message"
        let field = NSTextField(string: draft)
        field.placeholderString = "Your message"
        let all = NSButton(checkboxWithTitle: "Send to all", target: nil, action: nil)
        let recipients = friends
        let checks = recipients.map { NSButton(checkboxWithTitle: $0.name, target: nil, action: nil) }
        if checks.count == 1 { checks[0].state = .on }
        let listHeight = CGFloat(checks.count * 24)
        let visibleHeight = min(156, listHeight)
        let list = NSView(frame: CGRect(x: 0, y: 0, width: 275, height: listHeight))
        for (index, check) in checks.enumerated() {
            check.frame = CGRect(x: 3, y: listHeight - CGFloat((index + 1) * 24), width: 262, height: 23)
            list.addSubview(check)
        }
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 280, height: visibleHeight))
        scroll.documentView = list
        scroll.hasVerticalScroller = listHeight > visibleHeight
        scroll.contentView.scroll(to: CGPoint(x: 0, y: listHeight - visibleHeight))
        let form = NSView(frame: CGRect(x: 0, y: 0, width: 280, height: visibleHeight + 54))
        field.frame = CGRect(x: 0, y: visibleHeight + 29, width: 280, height: 24)
        all.frame = CGRect(x: 3, y: visibleHeight + 2, width: 270, height: 23)
        form.addSubview(scroll)
        form.addSubview(all)
        form.addSubview(field)
        alert.accessoryView = form
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let selected = zip(recipients, checks).compactMap { friend, check in
            all.state == .on || check.state == .on ? friend : nil
        }
        let text = field.stringValue.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty, text.count <= 72, text.utf8.count <= 320, !selected.isEmpty else {
            notice("Check your message", "Select at least one friend and enter a note of up to 72 characters.")
            return
        }
        sending = true
        var failures: [String] = []
        let group = DispatchGroup()
        for friend in selected {
            let note = FishNote(text: text, species: friend.species)
            guard let key = try? friendKey(friend), let plain = try? JSONEncoder().encode(note),
                  let box = try? AES.GCM.seal(plain, using: key),
                  let bytes = box.combined,
                  let body = try? JSONEncoder().encode(MailboxItem(id: UUID().uuidString, payload: bytes.base64EncodedString())) else {
                failures.append(friend.name)
                continue
            }
            group.enter()
            account.request("POST", path: "friends/" + friend.id, body: body, onFailure: { status in
                let reason: String
                switch status {
                case 401: reason = "The relay rejected your mailbox token."
                case 404: reason = "The relay couldn’t find this friend’s mailbox."
                case 429: reason = "This friend’s message queue is full."
                case 502, 503, 504: reason = "The relay is temporarily unreachable."
                case 0: reason = "Couldn’t connect to the relay."
                default: reason = "The relay returned HTTP \(status)."
                }
                failures.append(friend.name + " — " + reason)
            }) { _ in
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.sending = false
            if !failures.isEmpty { self.notice("Some messages weren’t confirmed", failures.joined(separator: "\n")) }
        }
    }

    func checkFriendMail() {
        guard friendInbox == nil, !friendRequest, !friends.isEmpty, let account = socialAccount else { return }
        friendRequest = true
        account.request("GET", path: "friends") { [weak self] data in
            guard let self else { return }
            self.friendRequest = false
            guard let data, let items = try? JSONDecoder().decode([FriendEnvelope].self, from: data) else { return }
            for item in items {
                guard let friend = self.friends.first(where: { $0.id == item.sender }),
                      let key = try? self.friendKey(friend), let bytes = Data(base64Encoded: item.payload),
                      let box = try? AES.GCM.SealedBox(combined: bytes),
                      let clear = try? AES.GCM.open(box, using: key),
                      let note = try? JSONDecoder().decode(FishNote.self, from: clear) else { continue }
                self.friendInbox = (item, FishNote(text: note.text, species: friend.species))
                self.needsDisplay = true
                break
            }
        }
    }

    func dismissFriendNote() {
        guard let current = friendInbox, let account = socialAccount, !friendRequest else { return }
        friendInbox = nil
        friendRequest = true
        account.request("DELETE", path: "friends/" + current.0.id) { [weak self] data in
            guard let self else { return }
            self.friendRequest = false
            if data == nil && self.friends.contains(where: { $0.id == current.0.sender }) {
                self.friendInbox = current
            }
            self.nextMailCheck = 0
            self.needsDisplay = true
        }
    }

    func drawChest() {
        let box = NSBezierPath(roundedRect: chestFrame, xRadius: 4, yRadius: 4)
        NSGradient(starting: tint(0xe5af9e), ending: tint(0x824f59))?.draw(in: box, angle: 90)
        let band = CGRect(x: chestFrame.minX + 1, y: chestFrame.midY - 1, width: chestFrame.width - 2, height: 2)
        tint(0xedc38b, 0.86).setFill()
        NSBezierPath(rect: band).fill()
        let bands: [CGFloat] = [5, 20]
        for dx in bands {
            NSBezierPath(roundedRect: CGRect(x: chestFrame.minX + dx, y: chestFrame.minY + 1,
                                             width: 1.5, height: 17), xRadius: 0.7, yRadius: 0.7).fill()
        }
        ("♥" as NSString).draw(at: CGPoint(x: chestFrame.midX - 3, y: chestFrame.midY - 3),
                               withAttributes: [.font: NSFont.systemFont(ofSize: 8, weight: .bold),
                                                .foregroundColor: tint(0xffe2aa)])
    }

    func openChest() {
        if let chestPopover, chestPopover.isShown { chestPopover.close(); return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSViewController()
        chestPopover = popover
        updateChest()
        let unflipped = window.map { $0.convertPoint(toScreen: convert(.zero, to: nil)) }
        let roomOnRight = (window?.screen?.visibleFrame.maxX ?? 1000) - (unflipped?.x ?? 0) - bounds.width
        popover.show(relativeTo: chestFrame, of: self, preferredEdge: roomOnRight > 245 ? .maxX : .minX)
        refreshPartner()
    }

    func updateChest() {
        guard let popover = chestPopover else { return }
        let selection = receivedGiftsMenu?.selectedItem?.title
        let width: CGFloat = 238
        let height: CGFloat = 215
        let content = NSView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        content.wantsLayer = true
        content.layer?.backgroundColor = tint(0x52363d).cgColor
        func label(_ text: String, y: CGFloat, size: CGFloat) {
            let view = NSTextField(labelWithString: text)
            view.font = .systemFont(ofSize: size, weight: .medium)
            view.textColor = tint(0xffe4bf)
            view.frame = CGRect(x: 15, y: y, width: 208, height: 21)
            content.addSubview(view)
        }
        label("Treasure chest", y: 181, size: 16)
        let next = rewards.first { $0.0 > linkedDays }
        let progress = status?.linkedSince == nil ? "Pair together to start milestones"
            : next.map { "\(linkedDays) days linked · next at \($0.0)" } ?? "\(linkedDays) days linked"
        label(progress, y: 158, size: 11)
        let inset = NSView(frame: CGRect(x: 12, y: 48, width: 214, height: 103))
        inset.wantsLayer = true
        inset.layer?.backgroundColor = tint(0x36232b).cgColor
        inset.layer?.cornerRadius = 10
        inset.layer?.borderWidth = 1
        inset.layer?.borderColor = tint(0xc18f62, 0.7).cgColor
        content.addSubview(inset)
        if gifts.isEmpty {
            label("No gifts yet", y: 89, size: 12)
        } else {
            let received = NSPopUpButton(frame: CGRect(x: 24, y: 99, width: 191, height: 26), pullsDown: false)
            for gift in gifts.reversed() {
                received.addItem(withTitle: "\(gift.kind.title) · \(gift.id.prefix(6))")
                received.lastItem?.representedObject = gift.kind.rawValue
            }
            if let selection { received.selectItem(withTitle: selection) }
            content.addSubview(received)
            let place = NSButton(title: "Place in tank", target: self, action: #selector(placeGift(_:)))
            place.frame = CGRect(x: 24, y: 65, width: 125, height: 25)
            receivedGiftsMenu = received
            content.addSubview(place)
        }
        let send = NSButton(title: "Send a gift…", target: self, action: #selector(sendGift))
        send.frame = CGRect(x: 13, y: 12, width: 121, height: 27)
        content.addSubview(send)
        popover.contentViewController?.view = content
        popover.contentSize = content.frame.size
    }

    @objc func placeGift(_ button: NSButton) {
        guard let popup = receivedGiftsMenu,
              let raw = popup.selectedItem?.representedObject as? String,
              let kind = Plant(rawValue: raw) else { return }
        addDecoration(kind)
    }

    func refreshPartner() {
        guard let pairing else { return }
        let generation = pairingGeneration
        pairing.request("GET", path: "pair") { [weak self] data in
            guard let self, self.pairingGeneration == generation, let data,
                  let status = try? JSONDecoder().decode(LinkStatus.self, from: data) else { return }
            self.status = status
            if self.chestPopover?.isShown == true { self.updateChest() }
        }
        pairing.request("GET", path: "gifts") { [weak self] data in
            guard let self, self.pairingGeneration == generation, let data,
                  let items = try? JSONDecoder().decode([MailboxItem].self, from: data) else { return }
            self.gifts = items.compactMap { item in
                guard let bytes = Data(base64Encoded: item.payload),
                      let box = try? AES.GCM.SealedBox(combined: bytes),
                      let decoded = try? AES.GCM.open(box, using: pairing.key),
                      let gift = try? JSONDecoder().decode(Gift.self, from: decoded), gift.id == item.id else { return nil }
                return gift
            }
            if self.chestPopover?.isShown == true { self.updateChest() }
        }
    }

    @objc func sendGift() {
        chestPopover?.close()
        guard let pairing else { configurePairing(); return }
        if let status, status.giftAfter > status.serverTime {
            let date = Date(timeIntervalSince1970: status.giftAfter)
            let when = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
            notice("One gift per week", "Your next gift is available \(when).")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let prompt = NSAlert()
        prompt.messageText = "Send a treasure"
        prompt.informativeText = "Your partner can find it in their chest. You can send one gift every seven days."
        let choices = NSPopUpButton(frame: CGRect(x: 0, y: 0, width: 180, height: 27), pullsDown: false)
        choices.addItems(withTitles: Gift.choices.map { $0.title })
        prompt.accessoryView = choices
        prompt.addButton(withTitle: "Send Gift")
        prompt.addButton(withTitle: "Cancel")
        guard prompt.runModal() == .alertFirstButtonReturn, choices.indexOfSelectedItem >= 0 else { return }
        let gift = Gift(id: UUID().uuidString, kind: Gift.choices[choices.indexOfSelectedItem])
        guard let note = try? JSONEncoder().encode(gift),
              let box = try? AES.GCM.seal(note, using: pairing.key),
              let bytes = box.combined,
              let body = try? JSONEncoder().encode(MailboxItem(id: gift.id, payload: bytes.base64EncodedString())) else { return }
        let generation = pairingGeneration
        pairing.request("POST", path: "gifts", body: body) { [weak self] data in
            guard let self, self.pairingGeneration == generation else { return }
            self.refreshPartner()
            if data == nil { self.notice("Gift couldn’t be confirmed", "Check the relay or your weekly gift limit.") }
        }
    }

    @objc func sendHello() {
        if !friends.isEmpty { composeForFriends("♥"); return }
        guard !sending else { return }
        guard let pairing else { configurePairing(); return }
        let kind = messageSpecies
        let note = FishNote(text: "♥", species: kind)
        guard let data = try? JSONEncoder().encode(note),
              let box = try? AES.GCM.seal(data, using: pairing.key),
              let bytes = box.combined,
              let body = try? JSONEncoder().encode(MailboxItem(id: UUID().uuidString,
                                                               payload: bytes.base64EncodedString())) else { return }
        sending = true
        sendNote(body, draft: "♥", pairing: pairing, generation: pairingGeneration, retry: true)
    }

    func drawFish(_ fish: Fish, in ctx: CGContext, highlighted: Bool = false) {
        ctx.saveGState()
        ctx.translateBy(x: fish.point.x, y: fish.point.y)
        ctx.rotate(by: fish.angle + sin(fish.stroke) * 0.048)
        let scale = fish.size * (highlighted ? 1.22 : 1) * (fish.species == .minnow ? 0.72 : 1)
        ctx.scaleBy(x: scale, y: scale)
        let (speciesLight, speciesAccent) = fish.species.colors
        let light: UInt32 = highlighted ? 0xfff2d8 : speciesLight
        let accent: UInt32 = highlighted ? speciesAccent ^ 0x10000c : speciesAccent
        let tailSwing = sin(fish.stroke) * (2.4 + fish.speed * 0.043)
        let tailLength: CGFloat = fish.species == .guppy ? 24 : 19
        let spread: CGFloat = fish.species == .guppy ? 9 : 6
        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: -9, y: 0))
        tail.curve(to: CGPoint(x: -tailLength, y: tailSwing - spread),
                   controlPoint1: CGPoint(x: -15, y: -2),
                   controlPoint2: CGPoint(x: -tailLength + 1, y: tailSwing - spread - 2))
        tail.line(to: CGPoint(x: -tailLength + 3, y: tailSwing))
        tail.line(to: CGPoint(x: -tailLength, y: tailSwing + spread))
        tail.curve(to: CGPoint(x: -9, y: 0),
                   controlPoint1: CGPoint(x: -tailLength + 5, y: tailSwing + 6),
                   controlPoint2: CGPoint(x: -13, y: 2))
        tail.close()
        NSGradient(starting: tint(accent, 0.85),
                   ending: tint(light, 0.56))?.draw(in: tail, angle: 180)

        let fin = NSBezierPath()
        fin.move(to: CGPoint(x: 2, y: 3))
        fin.curve(to: CGPoint(x: -5, y: 8 + sin(fish.stroke) * 0.55),
                  controlPoint1: CGPoint(x: 0, y: 7), controlPoint2: CGPoint(x: -2, y: 9))
        fin.curve(to: CGPoint(x: 2, y: 3),
                  controlPoint1: CGPoint(x: -4, y: 5), controlPoint2: CGPoint(x: -2, y: 3))
        fin.close()
        tint(accent, 0.70).setFill()
        fin.fill()

        let body = NSBezierPath()
        body.move(to: CGPoint(x: -13, y: 0))
        body.curve(to: CGPoint(x: 12, y: 0),
                   controlPoint1: CGPoint(x: -3, y: -9), controlPoint2: CGPoint(x: 12, y: -8))
        body.curve(to: CGPoint(x: -13, y: 0),
                   controlPoint1: CGPoint(x: 12, y: 8), controlPoint2: CGPoint(x: -3, y: 9))
        body.close()
        NSGradient(starting: tint(light), ending: tint(accent))?.draw(in: body, angle: 90)

        ctx.saveGState()
        body.addClip()
        if fish.species == .koi {
            tint(accent, 0.9).setFill()
            NSBezierPath(ovalIn: CGRect(x: -7, y: -6, width: 9, height: 7)).fill()
            NSBezierPath(ovalIn: CGRect(x: 3, y: 1, width: 8, height: 6)).fill()
        }
        tint(0xffffff, highlighted ? 0.88 : 0.56).setFill()
        NSBezierPath(ovalIn: CGRect(x: -1, y: -3.9, width: 6, height: highlighted ? 1.5 : 1.1)).fill()
        ctx.restoreGState()

        tint(0x203f47, 0.91).setFill()
        NSBezierPath(ovalIn: CGRect(x: 7.1, y: -2.8, width: 2, height: 2)).fill()
        tint(0xffffff, 0.84).setFill()
        NSBezierPath(ovalIn: CGRect(x: 7.6, y: -2.65, width: 0.65, height: 0.65)).fill()
        ctx.restoreGState()
    }
}

func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
    let delta = lhs - rhs
    return hypot(delta.x, delta.y)
}

final class AquariumApp: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var status: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let savedSize = UserDefaults.standard.array(forKey: "size") as? [Double] ?? []
        let width: CGFloat = savedSize.count == 2 ? clamp(CGFloat(savedSize[0]), 150, 560) : 180
        let height: CGFloat = savedSize.count == 2 ? clamp(CGFloat(savedSize[1]), 130, 460) : 180
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 900, height: 700)
        var frame = CGRect(x: screen.minX + 32, y: screen.maxY - height - 36, width: width, height: height)
        if let saved = UserDefaults.standard.array(forKey: "position") as? [Double], saved.count == 2 {
            let candidate = CGRect(origin: CGPoint(x: saved[0], y: saved[1]), size: frame.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(candidate) }) { frame = candidate }
        }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "Koi Aquarium"
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.isFloatingPanel = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let rect = CGRect(origin: .zero, size: frame.size)
        let glass = NSVisualEffectView(frame: rect)
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.alphaValue = 0.66
        glass.autoresizingMask = [.width, .height]
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 24
        glass.layer?.masksToBounds = true

        let container = NSView(frame: rect)
        container.addSubview(glass)
        let tank = Tank(frame: rect)
        tank.autoresizingMask = [.width, .height]
        container.addSubview(tank)
        panel.contentView = container
        window = panel
        showTank()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "fish", accessibilityDescription: "Koi Aquarium")
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Aquarium", action: #selector(showTank), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let hide = NSMenuItem(title: "Hide Aquarium", action: #selector(hideTank), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        let quit = NSMenuItem(title: "Quit Aquarium", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
        status = item
    }

    @objc func showTank() {
        guard let window else { return }
        let desktop = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        window.level = NSWindow.Level(rawValue: min(desktop, NSWindow.Level.normal.rawValue - 1))
        window.orderFrontRegardless()
    }
    @objc func hideTank() { window?.orderOut(nil) }
}

let app = NSApplication.shared
let delegate = AquariumApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
