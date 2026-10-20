import AppKit

@main
enum AbsoluteSenseMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            Game.runSelfTest()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
            Snapshot.write(to: CommandLine.arguments[index + 1])
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.appearance = NSAppearance(named: .darkAqua)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let stage = StageView()
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = makeWindow()
        buildMenu()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(stage)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Metrics.preferred),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "绝对色感"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.backgroundColor = Palette.background
        window.appearance = NSAppearance(named: .darkAqua)
        window.colorSpace = .sRGB
        window.tabbingMode = .disallowed
        window.contentView = stage
        let visible = NSScreen.main?.visibleFrame.size ?? Metrics.preferred
        let fitted = NSSize(
            width: min(Metrics.preferred.width, max(640, visible.width - 40)),
            height: min(Metrics.preferred.height, max(640, visible.height - 16))
        )
        window.contentMinSize = NSSize(width: min(Metrics.minimum.width, fitted.width), height: min(Metrics.minimum.height, fitted.height))
        window.setContentSize(fitted)
        window.center()
        return window
    }

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于绝对色感", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "清除纪录…", action: #selector(clearRecords), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出绝对色感", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let gameItem = NSMenuItem()
        let gameMenu = NSMenu(title: "游戏")
        gameMenu.addItem(withTitle: "开始闯关", action: #selector(StageView.startFromMenu(_:)), keyEquivalent: "n").target = stage
        gameMenu.addItem(withTitle: "返回开始", action: #selector(StageView.returnToTitle(_:)), keyEquivalent: "").target = stage
        gameItem.submenu = gameMenu
        main.addItem(gameItem)

        NSApp.mainMenu = main
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "绝对色感"
        alert.informativeText = "方阵里只有一块颜色不同。第 1 关是 3×3，差别比较明显；第 2 关是 4×4，差别更小。之后边长继续增加，直到 8×8，色差也会一路收紧。\n\n颜色每次都重新随机。点中不同的那一块进入下一关，点错失去一条命，并短暂标出正确答案。三条命用完即结束。答得越快，连对越多，得分越高。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func clearRecords() {
        let alert = NSAlert()
        alert.messageText = "清除纪录？"
        alert.informativeText = "最佳关卡和得分会回到零。"
        alert.addButton(withTitle: "清除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Records.clear()
        stage.forgetRecords()
    }
}

enum Snapshot {
    static func write(to directory: String) {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            fputs("无法创建目录 \(directory)\n", stderr)
            exit(1)
        }

        var lines: [String] = []
        func save(_ name: String, size: NSSize, _ configure: (StageView) -> String) {
            let view = StageView(frame: NSRect(origin: .zero, size: size))
            let note = configure(view)
            let image = NSImage(size: size, flipped: true) { _ in
                view.draw(view.bounds)
                return true
            }
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                fputs("截图失败 \(name)\n", stderr)
                exit(1)
            }
            do {
                try png.write(to: url.appendingPathComponent(name))
            } catch {
                fputs("写入失败 \(name)\n", stderr)
                exit(1)
            }
            lines.append("\(name)  \(note)")
        }

        let preferred = Metrics.preferred
        save("title.png", size: preferred) { view in
            view.session.bestLevel = 6
            view.session.bestScore = 2480
            return "title with record"
        }
        save("title-fresh.png", size: preferred) { _ in
            "title without record"
        }
        save("level1.png", size: preferred) { view in
            install(view, level: 1, seed: 11, score: 0, lives: 3, streak: 0)
        }
        save("level1-b.png", size: preferred) { view in
            install(view, level: 1, seed: 28, score: 0, lives: 3, streak: 0)
        }
        save("level1-wrong.png", size: preferred) { view in
            let note = install(view, level: 1, seed: 11, score: 0, lives: 2, streak: 0)
            if let board = view.session.board {
                let picked = board.oddIndex == 0 ? 1 : 0
                view.session.feedback = .wrong(picked: picked)
                view.session.locked = true
                view.session.frozenSpeed = 0.6
            }
            return note + " wrong"
        }
        save("level2.png", size: preferred) { view in
            install(view, level: 2, seed: 19, score: 180, lives: 3, streak: 2)
        }
        save("level4.png", size: preferred) { view in
            install(view, level: 4, seed: 4, score: 960, lives: 2, streak: 3)
        }
        save("level8.png", size: preferred) { view in
            install(view, level: 8, seed: 8, score: 4200, lives: 1, streak: 6)
        }
        save("over.png", size: preferred) { view in
            view.session.phase = .over
            view.session.level = 7
            view.session.score = 1860
            view.session.bestStreak = 4
            view.session.baselineLevel = 4
            view.session.baselineScore = 900
            view.session.bestLevel = 7
            view.session.bestScore = 1860
            return "over new record"
        }
        save("compact.png", size: NSSize(width: 720, height: 680)) { view in
            install(view, level: 2, seed: 3, score: 180, lives: 3, streak: 2)
        }

        let manifest = lines.joined(separator: "\n") + "\n"
        try? manifest.write(to: url.appendingPathComponent("manifest.txt"), atomically: true, encoding: .utf8)
        print(manifest)
    }

    private static func install(_ view: StageView, level: Int, seed: UInt64, score: Int, lives: Int, streak: Int) -> String {
        var rng = SplitMix64(seed: seed)
        let board = Game.makeBoard(level: level, rng: &rng)
        view.session.phase = .playing
        view.session.level = level
        view.session.score = score
        view.session.lives = lives
        view.session.streak = streak
        view.session.board = board
        view.session.startedAt = Date()
        let base = board.base
        let odd = board.odd
        return String(
            format: "L%d %d×%d odd=%d %@ Δ=%.3f gap=%.3f base=%.3f,%.3f,%.3f odd=%.3f,%.3f,%.3f",
            level,
            board.size,
            board.size,
            board.oddIndex,
            board.axis.label,
            board.distance,
            base.channelGap(to: odd),
            base.r, base.g, base.b,
            odd.r, odd.g, odd.b
        )
    }
}
