import AppKit

// 色块周围保持中性灰，避免环境色把判断带偏。

enum Palette {
    static let background = NSColor(srgbRed: 0.055, green: 0.058, blue: 0.070, alpha: 1)
    static let lift = NSColor(srgbRed: 0.145, green: 0.150, blue: 0.176, alpha: 1)
    static let plate = NSColor(srgbRed: 0.098, green: 0.102, blue: 0.122, alpha: 1)
    static let paper = NSColor(srgbRed: 0.957, green: 0.945, blue: 0.918, alpha: 1)
    static let ink = NSColor(srgbRed: 0.090, green: 0.094, blue: 0.110, alpha: 1)
    static let muted = NSColor(srgbRed: 0.608, green: 0.592, blue: 0.545, alpha: 1)
    static let faint = NSColor(srgbRed: 0.275, green: 0.282, blue: 0.325, alpha: 1)
    static let coral = NSColor(srgbRed: 0.882, green: 0.353, blue: 0.271, alpha: 1)
    static let gold = NSColor(srgbRed: 0.890, green: 0.694, blue: 0.353, alpha: 1)
    static let logoBase = NSColor(srgbRed: 0.416, green: 0.557, blue: 0.522, alpha: 1)
    static let logoOdd = NSColor(srgbRed: 0.855, green: 0.624, blue: 0.333, alpha: 1)
    static let hoverPaper = NSColor(srgbRed: 1, green: 0.995, blue: 0.975, alpha: 1)
    static let pressedPaper = NSColor(srgbRed: 0.820, green: 0.808, blue: 0.770, alpha: 1)
}

enum Fonts {
    static let kicker = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let wordmark = NSFont.systemFont(ofSize: 56, weight: .semibold)
    static let body = NSFont.systemFont(ofSize: 16, weight: .regular)
    static let button = NSFont.systemFont(ofSize: 17, weight: .semibold)
    static let value = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
    static let label = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let detail = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let hint = NSFont.systemFont(ofSize: 15, weight: .medium)
    static let footer = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let overTitle = NSFont.systemFont(ofSize: 40, weight: .semibold)
    static let overLine = NSFont.systemFont(ofSize: 18, weight: .regular)
}

enum Format {
    static let number: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func score(_ value: Int) -> String {
        number.string(from: NSNumber(value: value)) ?? String(value)
    }
}

enum Records {
    private static let levelKey = "absolutesense.bestLevel"
    private static let scoreKey = "absolutesense.bestScore"

    static func load() -> (level: Int, score: Int) {
        let defaults = UserDefaults.standard
        return (defaults.integer(forKey: levelKey), defaults.integer(forKey: scoreKey))
    }

    static func write(level: Int, score: Int) {
        let defaults = UserDefaults.standard
        defaults.set(level, forKey: levelKey)
        defaults.set(score, forKey: scoreKey)
    }

    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: levelKey)
        defaults.removeObject(forKey: scoreKey)
    }
}

enum Phase {
    case title
    case playing
    case over
}

enum Feedback: Equatable {
    case none
    case correct
    case wrong(picked: Int)
}

final class Session {
    var phase: Phase = .title
    var level = 1
    var lives = Game.lives
    var score = 0
    var streak = 0
    var bestStreak = 0
    var board: Board?
    var startedAt = Date()
    var feedback: Feedback = .none
    var locked = false
    var lastGain = 0
    var frozenSpeed: Double?
    var bestLevel: Int
    var bestScore: Int
    var baselineLevel = 0
    var baselineScore = 0
    var rng = SplitMix64.random()
    var token = 0

    init() {
        let saved = Records.load()
        bestLevel = saved.level
        bestScore = saved.score
    }

    var didSetRecord: Bool {
        let scoreBeat = score > baselineScore && score > 0
        let levelBeat = level > baselineLevel && level > 1
        return scoreBeat || levelBeat
    }

    func recordLine() -> String {
        if bestLevel <= 0 && bestScore <= 0 {
            return "还没有纪录"
        }
        if bestLevel <= 0 {
            return "最佳得分 \(Format.score(bestScore))"
        }
        return "最佳 第 \(bestLevel) 关 · \(Format.score(bestScore)) 分"
    }
}

enum Hotspot: Equatable {
    case start
    case again
    case home
    case tile(Int)
}

enum ButtonKind {
    case solid
    case ghost
}

struct Layout {
    var logo = NSRect.zero
    var kicker = NSRect.zero
    var title = NSRect.zero
    var subtitle = NSRect.zero
    var start = NSRect.zero
    var record = NSRect.zero
    var again = NSRect.zero
    var home = NSRect.zero
    var overKicker = NSRect.zero
    var overTitle = NSRect.zero
    var overScore = NSRect.zero
    var overStreak = NSRect.zero
    var overRecord = NSRect.zero
    var columns: [NSRect] = []
    var hint = NSRect.zero
    var board = NSRect.zero
    var plate = NSRect.zero
    var tiles: [NSRect] = []
    var speedLabel = NSRect.zero
    var speedTrack = NSRect.zero
    var footer = NSRect.zero
}

enum Metrics {
    static let preferred = NSSize(width: 880, height: 900)
    static let minimum = NSSize(width: 680, height: 640)
}

final class StageView: NSView {
    let session = Session()
    private var hover: Hotspot?
    private var pressed: Hotspot?
    private var pending: Timer?
    private var pulse: Timer?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        armClock()
    }

    deinit {
        pending?.invalidate()
        pulse?.invalidate()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func resetCursorRects() {
        discardCursorRects()
        let layout = layout(for: bounds.size)
        let spots: [NSRect]
        switch session.phase {
        case .title:
            spots = [layout.start]
        case .playing:
            spots = session.locked ? [] : layout.tiles
        case .over:
            spots = [layout.again, layout.home]
        }
        for rect in spots where !rect.isEmpty {
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(event)
    }

    override func mouseExited(with event: NSEvent) {
        hover = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let hit = hotspot(at: point(from: event))
        if hit == nil {
            window?.performDrag(with: event)
            return
        }
        pressed = hit
        hover = hit
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        hover = hotspot(at: point(from: event))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let hit = hotspot(at: point(from: event))
        let chosen = pressed
        pressed = nil
        hover = hit
        needsDisplay = true
        if let chosen, chosen == hit {
            activate(chosen)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.isARepeat { return }
        switch event.charactersIgnoringModifiers ?? "" {
        case " ", "\r", "\u{3}":
            if session.phase == .title || session.phase == .over {
                startGame()
            }
        case "r", "R":
            startGame()
        case "\u{1b}":
            if session.phase != .title {
                showTitle()
            }
        default:
            break
        }
    }

    @objc func startFromMenu(_ sender: Any?) {
        startGame()
    }

    @objc func returnToTitle(_ sender: Any?) {
        showTitle()
    }

    func forgetRecords() {
        session.bestLevel = 0
        session.bestScore = 0
        session.baselineLevel = 0
        session.baselineScore = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let layout = layout(for: bounds.size)
        drawBackground()
        switch session.phase {
        case .title:
            drawTitle(layout)
        case .playing:
            drawPlay(layout)
        case .over:
            drawOver(layout)
        }
        drawFooter(layout)
    }

    private func startGame() {
        cancelPending()
        session.phase = .playing
        session.level = 1
        session.lives = Game.lives
        session.score = 0
        session.streak = 0
        session.bestStreak = 0
        session.lastGain = 0
        session.baselineLevel = session.bestLevel
        session.baselineScore = session.bestScore
        deal()
    }

    private func showTitle() {
        cancelPending()
        session.phase = .title
        session.locked = false
        session.feedback = .none
        session.frozenSpeed = nil
        session.board = nil
        sync()
    }

    private func deal() {
        session.board = Game.makeBoard(level: session.level, rng: &session.rng)
        session.startedAt = Date()
        session.locked = false
        session.feedback = .none
        session.frozenSpeed = nil
        session.lastGain = 0
        if session.level > 1 {
            session.bestLevel = max(session.bestLevel, session.level)
            session.bestScore = max(session.bestScore, session.score)
            Records.write(level: session.bestLevel, score: session.bestScore)
        }
        sync()
    }

    private func activate(_ hotspot: Hotspot) {
        switch hotspot {
        case .start, .again:
            startGame()
        case .home:
            showTitle()
        case .tile(let index):
            pick(index)
        }
    }

    private func pick(_ index: Int) {
        guard session.phase == .playing, !session.locked, let board = session.board else { return }
        guard layout(for: bounds.size).tiles.indices.contains(index) else { return }
        let elapsed = Date().timeIntervalSince(session.startedAt)
        session.frozenSpeed = max(0, min(1, (Game.speedWindow - elapsed) / Game.speedWindow))
        session.locked = true
        if index == board.oddIndex {
            session.streak += 1
            session.bestStreak = max(session.bestStreak, session.streak)
            session.lastGain = Game.points(level: session.level, seconds: elapsed, streak: session.streak)
            session.score += session.lastGain
            session.feedback = .correct
            sync()
            after(0.42) { [weak self] in
                guard let self else { return }
                self.session.level += 1
                self.deal()
            }
        } else {
            session.lives -= 1
            session.streak = 0
            session.feedback = .wrong(picked: index)
            if session.score > 0 || session.level > 1 {
                session.bestLevel = max(session.bestLevel, session.level)
                session.bestScore = max(session.bestScore, session.score)
                Records.write(level: session.bestLevel, score: session.bestScore)
            }
            let ended = session.lives <= 0
            sync()
            after(0.92) { [weak self] in
                guard let self else { return }
                if ended {
                    self.session.phase = .over
                    self.session.locked = false
                    self.session.feedback = .none
                    self.sync()
                } else {
                    self.deal()
                }
            }
        }
    }

    private func after(_ delay: TimeInterval, _ body: @escaping () -> Void) {
        session.token += 1
        let expected = session.token
        pending?.invalidate()
        pending = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.session.token == expected else { return }
            body()
        }
    }

    private func cancelPending() {
        session.token += 1
        pending?.invalidate()
        pending = nil
    }

    private func sync() {
        switch session.phase {
        case .title, .over:
            window?.title = "绝对色感"
        case .playing:
            window?.title = "绝对色感 · 第 \(session.level) 关"
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func armClock() {
        guard pulse == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.session.phase == .playing, self.session.frozenSpeed == nil else { return }
            self.needsDisplay = true
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        pulse = timer
    }

    private func point(from event: NSEvent) -> NSPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func updateHover(_ event: NSEvent) {
        let next = hotspot(at: point(from: event))
        guard next != hover else { return }
        hover = next
        needsDisplay = true
    }

    private func hotspot(at point: NSPoint) -> Hotspot? {
        let layout = layout(for: bounds.size)
        switch session.phase {
        case .title:
            return layout.start.contains(point) ? .start : nil
        case .playing:
            guard !session.locked else { return nil }
            for (index, rect) in layout.tiles.enumerated() where rect.contains(point) {
                return .tile(index)
            }
            return nil
        case .over:
            if layout.again.contains(point) { return .again }
            if layout.home.contains(point) { return .home }
            return nil
        }
    }

    private func currentSpeed() -> Double {
        if let frozenSpeed = session.frozenSpeed { return frozenSpeed }
        let elapsed = Date().timeIntervalSince(session.startedAt)
        return max(0, min(1, (Game.speedWindow - elapsed) / Game.speedWindow))
    }

    private func layout(for size: NSSize) -> Layout {
        switch session.phase {
        case .title:
            return layoutTitle(size)
        case .playing:
            return layoutPlay(size)
        case .over:
            return layoutOver(size)
        }
    }

    private func layoutTitle(_ size: NSSize) -> Layout {
        var layout = Layout()
        let width = min(520, size.width - 72)
        let x = (size.width - width) / 2
        let logoSide: CGFloat = 26 * 3 + 8 * 2
        let block: CGFloat = 470
        var y = max(72, (size.height - block) / 2)
        layout.logo = NSRect(x: (size.width - logoSide) / 2, y: y + 18, width: logoSide, height: logoSide)
        y += 18 + logoSide + 18 + 28
        layout.kicker = NSRect(x: x, y: y, width: width, height: 20)
        y += 30
        layout.title = NSRect(x: x, y: y, width: width, height: 66)
        y += 74
        layout.subtitle = NSRect(x: x, y: y, width: width, height: 84)
        y += 84 + 28
        layout.start = NSRect(x: (size.width - 220) / 2, y: y, width: 220, height: 54)
        y += 54 + 18
        layout.record = NSRect(x: x, y: y, width: width, height: 24)
        layout.footer = NSRect(x: 20, y: size.height - 36, width: size.width - 40, height: 18)
        return layout
    }

    private func layoutOver(_ size: NSSize) -> Layout {
        var layout = Layout()
        let width = min(520, size.width - 72)
        let x = (size.width - width) / 2
        let block: CGFloat = 360
        var y = max(80, (size.height - block) / 2)
        layout.overKicker = NSRect(x: x, y: y, width: width, height: 20)
        y += 32
        layout.overTitle = NSRect(x: x, y: y, width: width, height: 52)
        y += 64
        layout.overScore = NSRect(x: x, y: y, width: width, height: 28)
        y += 32
        layout.overStreak = NSRect(x: x, y: y, width: width, height: 26)
        y += 36
        layout.overRecord = NSRect(x: x, y: y, width: width, height: 32)
        y += 48
        layout.again = NSRect(x: (size.width - 220) / 2, y: y, width: 220, height: 54)
        y += 66
        layout.home = NSRect(x: (size.width - 220) / 2, y: y, width: 220, height: 54)
        layout.footer = NSRect(x: 20, y: size.height - 36, width: size.width - 40, height: 18)
        return layout
    }

    private func layoutPlay(_ size: NSSize) -> Layout {
        var layout = Layout()
        let outer: CGFloat = 28
        let columnWidth = (size.width - outer * 2) / 3
        layout.columns = (0..<3).map { index in
            NSRect(x: outer + CGFloat(index) * columnWidth, y: 50, width: columnWidth, height: 82)
        }

        let hintHeight: CGFloat = 24
        let hintGap: CGFloat = 10
        let platePad: CGFloat = 22
        let afterPlate: CGFloat = 16
        let speedLabelHeight: CGFloat = 16
        let speedGap: CGFloat = 6
        let barHeight: CGFloat = 4
        let extra = hintHeight + hintGap + platePad + platePad + afterPlate + speedLabelHeight + speedGap + barHeight
        let headerBottom: CGFloat = 142
        let footerTop = size.height - 44
        let maxSide = min(size.width - 48 - platePad * 2, footerTop - headerBottom - extra)
        let side = max(120, maxSide).rounded(.down)
        let cluster = side + extra
        var y = headerBottom + max(0, (footerTop - headerBottom - cluster) / 2)
        layout.hint = NSRect(x: 32, y: y, width: size.width - 64, height: hintHeight)
        y += hintHeight + hintGap + platePad
        layout.board = NSRect(x: ((size.width - side) / 2).rounded(), y: y, width: side, height: side)
        layout.plate = layout.board.insetBy(dx: -platePad, dy: -platePad)
        y = layout.board.maxY + platePad + afterPlate
        let speedWidth = min(240, size.width - 80)
        layout.speedLabel = NSRect(x: (size.width - speedWidth) / 2, y: y, width: speedWidth, height: speedLabelHeight)
        y += speedLabelHeight + speedGap
        layout.speedTrack = NSRect(x: (size.width - speedWidth) / 2, y: y, width: speedWidth, height: barHeight)
        layout.footer = NSRect(x: 20, y: size.height - 32, width: size.width - 40, height: 18)

        let count = session.board?.size ?? Game.gridSize(for: session.level)
        placeTiles(in: layout.board, count: count, into: &layout)
        return layout
    }

    private func placeTiles(in board: NSRect, count: Int, into layout: inout Layout) {
        guard count >= 2 else { return }
        let gap: CGFloat = count <= 4 ? 14 : 9
        let tile = ((board.width - gap * CGFloat(count - 1)) / CGFloat(count)).rounded(.down)
        guard tile >= 8 else { return }
        let used = tile * CGFloat(count) + gap * CGFloat(count - 1)
        let originX = (board.minX + (board.width - used) / 2).rounded()
        let originY = (board.minY + (board.height - used) / 2).rounded()
        var tiles: [NSRect] = []
        tiles.reserveCapacity(count * count)
        for row in 0..<count {
            for column in 0..<count {
                tiles.append(NSRect(
                    x: originX + CGFloat(column) * (tile + gap),
                    y: originY + CGFloat(row) * (tile + gap),
                    width: tile,
                    height: tile
                ))
            }
        }
        layout.tiles = tiles
    }

    private func drawBackground() {
        if let gradient = NSGradient(starting: Palette.lift, ending: Palette.background) {
            gradient.draw(in: bounds, relativeCenterPosition: NSPoint(x: 0, y: 0.08))
        } else {
            Palette.background.setFill()
            bounds.fill()
        }
    }

    private func drawTitle(_ layout: Layout) {
        let plate = layout.logo.insetBy(dx: -18, dy: -18)
        fillRound(plate, radius: 22, color: Palette.plate)
        let tile: CGFloat = 26
        let gap: CGFloat = 8
        for row in 0..<3 {
            for column in 0..<3 {
                let index = row * 3 + column
                let rect = NSRect(
                    x: layout.logo.minX + CGFloat(column) * (tile + gap),
                    y: layout.logo.minY + CGFloat(row) * (tile + gap),
                    width: tile,
                    height: tile
                )
                fillRound(rect, radius: 7, color: index == 8 ? Palette.logoOdd : Palette.logoBase)
            }
        }
        drawText("色觉闯关", in: layout.kicker, font: Fonts.kicker, color: Palette.gold, kern: 3)
        drawText("绝对色感", in: layout.title, font: Fonts.wordmark, color: Palette.paper)
        drawText(
            "每关都是随机配色的方阵，只有一块不一样。\n第 1 关是 3×3，差别明显；之后格子更多，色差更小。\n点错失去一条命，三条命用完本局结束。",
            in: layout.subtitle,
            font: Fonts.body,
            color: Palette.muted,
            lineSpacing: 5
        )
        drawButton(
            layout.start,
            title: "开始闯关",
            kind: .solid,
            hot: hover == .start,
            down: pressed == .start && hover == .start
        )
        drawText(session.recordLine(), in: layout.record, font: Fonts.detail, color: Palette.muted)
    }

    private func drawPlay(_ layout: Layout) {
        guard layout.columns.count == 3 else { return }
        let size = session.board?.size ?? Game.gridSize(for: session.level)
        drawColumn(
            layout.columns[0],
            label: "关卡",
            value: "第 \(session.level) 关",
            detail: "\(size) × \(size) · \(Game.clarity(for: session.level))",
            detailColor: Palette.muted
        )
        let scoreDetail = scoreDetail()
        drawColumn(
            layout.columns[1],
            label: "得分",
            value: Format.score(session.score),
            detail: scoreDetail.text,
            detailColor: scoreDetail.color
        )
        drawText("生命", in: NSRect(x: layout.columns[2].minX, y: layout.columns[2].minY, width: layout.columns[2].width, height: 16), font: Fonts.label, color: Palette.muted, kern: 1.2)
        drawLives(
            in: NSRect(x: layout.columns[2].minX, y: layout.columns[2].minY + 26, width: layout.columns[2].width, height: 22),
            filled: max(0, session.lives)
        )

        let hintColor: NSColor
        let hint: String
        switch session.feedback {
        case .correct:
            hint = "对了"
            hintColor = Palette.gold
        case .wrong:
            hint = "是这一块"
            hintColor = Palette.coral
        case .none:
            hint = "找出颜色不同的一块"
            hintColor = Palette.paper
        }
        drawText(hint, in: layout.hint, font: Fonts.hint, color: hintColor)

        fillRound(layout.plate, radius: 28, color: Palette.plate)
        guard let board = session.board else { return }
        for (index, rect) in layout.tiles.enumerated() {
            let rgb = board.color(at: index)
            let radius = max(8, rect.width * 0.16)
            fillRound(rect, radius: radius, color: rgb.color)
        }
        drawRings(layout)
        drawSpeed(layout)
    }

    private func drawOver(_ layout: Layout) {
        drawText("本局结束", in: layout.overKicker, font: Fonts.kicker, color: Palette.gold, kern: 3)
        drawText("来到第 \(session.level) 关", in: layout.overTitle, font: Fonts.overTitle, color: Palette.paper)
        drawText("得分 \(Format.score(session.score))", in: layout.overScore, font: Fonts.overLine, color: Palette.paper)
        let streak = session.bestStreak > 0 ? "最长连续 \(session.bestStreak)" : "还没有答对"
        drawText(streak, in: layout.overStreak, font: Fonts.detail, color: Palette.muted)
        if session.didSetRecord {
            drawPill("新纪录", in: layout.overRecord)
        } else if session.baselineLevel > 0 || session.baselineScore > 0 {
            let text = "最佳仍是 第 \(max(session.baselineLevel, 1)) 关 · \(Format.score(session.baselineScore)) 分"
            drawText(text, in: layout.overRecord, font: Fonts.detail, color: Palette.muted)
        }
        drawButton(
            layout.again,
            title: "再闯一次",
            kind: .solid,
            hot: hover == .again,
            down: pressed == .again && hover == .again
        )
        drawButton(
            layout.home,
            title: "返回",
            kind: .ghost,
            hot: hover == .home,
            down: pressed == .home && hover == .home
        )
    }

    private func drawFooter(_ layout: Layout) {
        let text: String
        switch session.phase {
        case .title:
            text = "空格开始"
        case .playing:
            text = "点错失去一条命 · R 重来 · esc 返回"
        case .over:
            text = "空格再来 · esc 返回"
        }
        drawText(text, in: layout.footer, font: Fonts.footer, color: Palette.faint)
    }

    private func drawRings(_ layout: Layout) {
        guard let board = session.board, layout.tiles.indices.contains(board.oddIndex) else { return }
        switch session.feedback {
        case .none:
            break
        case .correct:
            ring(layout.tiles[board.oddIndex], Palette.paper)
        case .wrong(let picked):
            if layout.tiles.indices.contains(picked) {
                ring(layout.tiles[picked], Palette.coral)
            }
            ring(layout.tiles[board.oddIndex], Palette.paper)
        }
    }

    private func drawSpeed(_ layout: Layout) {
        drawText("速度加成", in: layout.speedLabel, font: Fonts.footer, color: Palette.muted)
        Palette.faint.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: layout.speedTrack, xRadius: 2, yRadius: 2).fill()
        var filled = layout.speedTrack
        filled.size.width = max(0, layout.speedTrack.width * CGFloat(currentSpeed()))
        guard filled.width > 0.5 else { return }
        Palette.paper.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()
    }

    private func scoreDetail() -> (text: String, color: NSColor) {
        switch session.feedback {
        case .correct where session.lastGain > 0:
            let streak = session.streak >= 2 ? " · 连续 \(session.streak)" : ""
            return ("+\(session.lastGain)\(streak)", Palette.gold)
        default:
            if session.streak >= 2 {
                return ("连续 \(session.streak)", Palette.muted)
            }
            return ("", Palette.muted)
        }
    }

    private func drawColumn(_ rect: NSRect, label: String, value: String, detail: String, detailColor: NSColor) {
        drawText(label, in: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 16), font: Fonts.label, color: Palette.muted, kern: 1.2)
        drawText(value, in: NSRect(x: rect.minX, y: rect.minY + 20, width: rect.width, height: 34), font: Fonts.value, color: Palette.paper)
        drawText(detail, in: NSRect(x: rect.minX, y: rect.minY + 56, width: rect.width, height: 18), font: Fonts.detail, color: detailColor)
    }

    private func drawLives(in rect: NSRect, filled: Int) {
        let diameter: CGFloat = 14
        let gap: CGFloat = 8
        let total = diameter * 3 + gap * 2
        var x = rect.midX - total / 2
        let y = rect.midY - diameter / 2
        for index in 0..<3 {
            let dot = NSRect(x: x, y: y, width: diameter, height: diameter)
            if index < filled {
                Palette.paper.setFill()
                NSBezierPath(ovalIn: dot).fill()
            } else {
                Palette.faint.setStroke()
                let path = NSBezierPath(ovalIn: dot.insetBy(dx: 1, dy: 1))
                path.lineWidth = 1.5
                path.stroke()
            }
            x += diameter + gap
        }
    }

    private func drawButton(_ rect: NSRect, title: String, kind: ButtonKind, hot: Bool, down: Bool) {
        let radius = rect.height / 2
        switch kind {
        case .solid:
            let fill = down ? Palette.pressedPaper : (hot ? Palette.hoverPaper : Palette.paper)
            fillRound(rect, radius: radius, color: fill)
            drawText(title, in: rect, font: Fonts.button, color: Palette.ink)
        case .ghost:
            if down {
                Palette.paper.withAlphaComponent(0.08).setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            }
            let stroke = hot || down ? Palette.paper : Palette.faint
            stroke.setStroke()
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
            path.lineWidth = 1.5
            path.stroke()
            drawText(title, in: rect, font: Fonts.button, color: Palette.paper)
        }
    }

    private func drawPill(_ text: String, in rect: NSRect) {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let width = (text as NSString).size(withAttributes: [.font: font]).width + 28
        let pill = NSRect(x: rect.midX - width / 2, y: rect.midY - 14, width: width, height: 28)
        Palette.gold.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 14, yRadius: 14).fill()
        drawText(text, in: pill, font: font, color: Palette.gold, kern: 1)
    }

    private func ring(_ rect: NSRect, _ color: NSColor) {
        let inset = rect.insetBy(dx: 6, dy: 6)
        let radius = max(6, inset.width * 0.14)
        NSColor.black.withAlphaComponent(0.55).setStroke()
        let under = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        under.lineWidth = 5
        under.stroke()
        color.setStroke()
        let path = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        path.lineWidth = 2.5
        path.stroke()
    }

    private func fillRound(_ rect: NSRect, radius: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
}

extension RGB {
    var color: NSColor {
        NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }
}

@discardableResult
func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .center,
    kern: CGFloat = 0,
    lineSpacing: CGFloat = 2
) -> CGFloat {
    guard !text.isEmpty, rect.width > 1, rect.height > 1 else { return 0 }
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineBreakMode = .byWordWrapping
    style.lineSpacing = lineSpacing
    var attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: style,
    ]
    if kern != 0 {
        attributes[.kern] = kern
    }
    let bounds = (text as NSString).boundingRect(
        with: NSSize(width: rect.width, height: 2000),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attributes
    )
    let drawRect = NSRect(
        x: rect.minX,
        y: rect.midY - bounds.height / 2,
        width: rect.width,
        height: ceil(bounds.height) + 2
    )
    (text as NSString).draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    return bounds.height
}
