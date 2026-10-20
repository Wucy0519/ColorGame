import Foundation

// 闯关：第 1 关 3×3，之后每关边长 +1，到 8×8 为止。
// 色差用 OKLab 距离，随关卡变小。每一盘的底色和差异方向都重新随机。

struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    func channelGap(to other: RGB) -> Double {
        max(abs(r - other.r), abs(g - other.g), abs(b - other.b))
    }
}

struct OKLab: Equatable {
    var L: Double
    var a: Double
    var b: Double
}

enum Axis: String, Equatable {
    case lightness
    case chroma
    case hue
    case mixed

    var label: String {
        switch self {
        case .lightness: return "明度"
        case .chroma: return "纯度"
        case .hue: return "色相"
        case .mixed: return "综合"
        }
    }
}

struct Board: Equatable {
    var level: Int
    var size: Int
    var base: RGB
    var odd: RGB
    var oddIndex: Int
    var axis: Axis
    var distance: Double
    var attempts: Int
    var synthesized: Bool

    var count: Int { size * size }

    func color(at index: Int) -> RGB {
        index == oddIndex ? odd : base
    }
}

struct SplitMix64: Equatable {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    static func random() -> SplitMix64 {
        var generator = SystemRandomNumberGenerator()
        return SplitMix64(seed: generator.next())
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func int(below limit: Int) -> Int {
        precondition(limit > 0)
        return Int(next() % UInt64(limit))
    }

    mutating func sign() -> Double {
        next() & 1 == 0 ? -1 : 1
    }
}

enum ColorScience {
    static func linearize(_ channel: Double) -> Double {
        if channel <= 0.04045 {
            return channel / 12.92
        }
        return pow((channel + 0.055) / 1.055, 2.4)
    }

    static func delinearize(_ channel: Double) -> Double {
        if channel <= 0.0031308 {
            return 12.92 * channel
        }
        return 1.055 * pow(channel, 1 / 2.4) - 0.055
    }

    static func oklab(from rgb: RGB) -> OKLab {
        let r = linearize(rgb.r)
        let g = linearize(rgb.g)
        let b = linearize(rgb.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return OKLab(
            L: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    static func rgb(from lab: OKLab) -> RGB? {
        let l = lab.L + 0.3963377774 * lab.a + 0.2158037573 * lab.b
        let m = lab.L - 0.1055613458 * lab.a - 0.0638541728 * lab.b
        let s = lab.L - 0.0894841775 * lab.a - 1.2914855480 * lab.b
        let l3 = l * l * l
        let m3 = m * m * m
        let s3 = s * s * s
        let linear = [
            4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
            -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
            -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3,
        ]
        let limit = 0.0015
        guard linear.allSatisfy({ $0.isFinite && $0 >= -limit && $0 <= 1 + limit }) else { return nil }
        let rgb = RGB(
            r: clamp(delinearize(clamp(linear[0], 0, 1)), 0, 1),
            g: clamp(delinearize(clamp(linear[1], 0, 1)), 0, 1),
            b: clamp(delinearize(clamp(linear[2], 0, 1)), 0, 1)
        )
        guard rgb.r.isFinite, rgb.g.isFinite, rgb.b.isFinite else { return nil }
        let back = oklab(from: rgb)
        guard distance(lab, back) < 0.01 else { return nil }
        return rgb
    }

    static func distance(_ p: OKLab, _ q: OKLab) -> Double {
        let dL = p.L - q.L
        let da = p.a - q.a
        let db = p.b - q.b
        return sqrt(dL * dL + da * da + db * db)
    }

    static func quantize(_ rgb: RGB) -> RGB {
        RGB(r: quantize(rgb.r), g: quantize(rgb.g), b: quantize(rgb.b))
    }

    private static func quantize(_ channel: Double) -> Double {
        (clamp(channel, 0, 1) * 255).rounded() / 255
    }
}

enum Game {
    static let lives = 3
    static let speedWindow = 7.5

    static func gridSize(for level: Int) -> Int {
        min(8, max(3, max(level, 1) + 2))
    }

    static func delta(for level: Int) -> Double {
        let step = Double(max(level, 1) - 1)
        return 0.016 + 0.164 * exp(-0.55 * step)
    }

    static func clarity(for level: Int) -> String {
        switch max(level, 1) {
        case 1: return "明显"
        case 2: return "清楚"
        case 3...4: return "细看"
        case 5...7: return "微弱"
        default: return "极微"
        }
    }

    static func points(level: Int, seconds: Double, streak: Int) -> Int {
        let safeLevel = max(1, level)
        let base = 40 + safeLevel * 25
        let elapsed = max(0, seconds)
        let speed = max(0, min(1, (speedWindow - elapsed) / speedWindow))
        let speedPoints = Int((Double(base) * speed).rounded())
        let streakPoints = min(max(streak - 1, 0), 15) * 12
        return base + speedPoints + streakPoints
    }

    static func makeBoard(level: Int, rng: inout SplitMix64) -> Board {
        let level = max(1, level)
        let size = gridSize(for: level)
        let target = delta(for: level)
        let axis: Axis = level == 1 ? .mixed : [.lightness, .chroma, .hue][rng.int(below: 3)]
        for attempt in 1...72 {
            if let board = sample(level: level, size: size, target: target, axis: axis, attempts: attempt, rng: &rng) {
                return board
            }
        }
        return fallback(level: level, size: size, target: target, axis: axis, rng: &rng)
    }

    static func runSelfTest() {
        var failed = 0
        func check(_ condition: Bool, _ message: String) {
            if condition {
                print("ok \(message)")
            } else {
                fputs("FAIL \(message)\n", stderr)
                failed += 1
            }
        }

        let white = oklabRoundtrip(RGB(r: 1, g: 1, b: 1))
        check(white != nil && abs(white!.L - 1) < 1e-5 && abs(white!.a) < 1e-5 && abs(white!.b) < 1e-5, "white maps to OKLab 1,0,0")
        let black = ColorScience.oklab(from: RGB(r: 0, g: 0, b: 0))
        check(abs(black.L) < 1e-6 && abs(black.a) < 1e-6 && abs(black.b) < 1e-6, "black maps to OKLab 0,0,0")
        let red = ColorScience.oklab(from: RGB(r: 1, g: 0, b: 0))
        check(abs(red.L - 0.627955) < 0.002, "red lightness \(red.L)")
        check(abs(red.a - 0.224863) < 0.002, "red green-red \(red.a)")
        check(abs(red.b - 0.125846) < 0.002, "red blue-yellow \(red.b)")

        let sample = RGB(r: 0.2, g: 0.5, b: 0.8)
        if let back = ColorScience.rgb(from: ColorScience.oklab(from: sample)) {
            check(abs(back.r - sample.r) < 1e-4 && abs(back.g - sample.g) < 1e-4 && abs(back.b - sample.b) < 1e-4, "sRGB roundtrip")
        } else {
            check(false, "sRGB roundtrip")
        }

        var previousDelta = 999.0
        for level in 1...12 {
            let delta = delta(for: level)
            check(delta < previousDelta, "delta decreases at level \(level)")
            previousDelta = delta
            check(gridSize(for: level) == min(8, level + 2), "grid \(level) is \(min(8, level + 2))")
        }
        check(gridSize(for: 1) == 3, "level 1 is 3x3")
        check(gridSize(for: 2) == 4, "level 2 is 4x4")
        check(gridSize(for: 9) == 8, "grid caps at 8")
        check(clarity(for: 1) == "明显" && clarity(for: 2) == "清楚", "clarity labels")
        check(delta(for: 1) > 0.16 && delta(for: 2) < delta(for: 1) && delta(for: 2) > 0.08, "level 1 is obvious and level 2 is milder")

        check(points(level: 1, seconds: 0, streak: 1) > points(level: 1, seconds: 8, streak: 1), "fast answers score more")
        check(points(level: 2, seconds: 1, streak: 5) > points(level: 2, seconds: 1, streak: 1), "streak scores more")
        check(points(level: 4, seconds: 1, streak: 2) > points(level: 1, seconds: 1, streak: 2), "higher levels score more")

        var first = SplitMix64(seed: 99)
        var second = SplitMix64(seed: 99)
        check(makeBoard(level: 3, rng: &first) == makeBoard(level: 3, rng: &second), "same seed rebuilds the same board")

        var maxAttempts = 0
        let levels = [1, 2, 3, 5, 8]
        for level in levels {
            for seed in 1...24 {
                var rng = SplitMix64(seed: UInt64(seed * 100 + level))
                let board = makeBoard(level: level, rng: &rng)
                maxAttempts = max(maxAttempts, board.attempts)
                check(board.size == gridSize(for: level), "size level \(level) seed \(seed)")
                check(board.oddIndex >= 0 && board.oddIndex < board.count, "odd index level \(level) seed \(seed)")
                let different = (0..<board.count).filter { board.color(at: $0) != board.base }
                check(different.count == 1 && different[0] == board.oddIndex, "exactly one odd tile level \(level) seed \(seed)")
                for color in [board.base, board.odd] {
                    let inside = [color.r, color.g, color.b].allSatisfy { (0...1).contains($0) }
                    check(inside, "channels in range level \(level) seed \(seed)")
                }
                let quantizedBase = ColorScience.quantize(board.base)
                let quantizedOdd = ColorScience.quantize(board.odd)
                check(quantizedBase != quantizedOdd, "8-bit keeps the odd tile level \(level) seed \(seed)")
                check(!board.synthesized, "sampled in gamut level \(level) seed \(seed)")
                if !board.synthesized {
                    let ratio = board.distance / delta(for: level)
                    check(ratio > 0.82 && ratio < 1.18, "distance ratio \(String(format: "%.3f", ratio)) level \(level) seed \(seed)")
                }
                if level == 1 {
                    check(board.axis == Axis.mixed, "level 1 uses a mixed shift")
                    check(board.base.channelGap(to: board.odd) >= 0.06, "level 1 channel gap seed \(seed)")
                }
                if level == 2 {
                    check(board.base.channelGap(to: board.odd) >= 0.035, "level 2 channel gap seed \(seed)")
                }
                let baseLab = ColorScience.oklab(from: board.base)
                let oddLab = ColorScience.oklab(from: board.odd)
                if hypot(baseLab.a, baseLab.b) > 0.03 && hypot(oddLab.a, oddLab.b) > 0.03 {
                    var hueGap = abs(atan2(baseLab.b, baseLab.a) - atan2(oddLab.b, oddLab.a))
                    if hueGap > Double.pi { hueGap = 2 * Double.pi - hueGap }
                    check(hueGap < 0.42, "same color family level \(level) seed \(seed) hue \(String(format: "%.1f", hueGap * 180 / Double.pi))°")
                }
            }
        }

        for level in 1...8 {
            print("level \(level)  \(gridSize(for: level))×\(gridSize(for: level))  Δ \(String(format: "%.3f", delta(for: level)))  \(clarity(for: level))")
        }
        print("max sample attempts \(maxAttempts)")

        if failed > 0 {
            fputs("\(failed) checks failed\n", stderr)
            exit(1)
        }
        print("self-test passed")
    }

    private static func oklabRoundtrip(_ rgb: RGB) -> OKLab? {
        let lab = ColorScience.oklab(from: rgb)
        guard ColorScience.rgb(from: lab) != nil else { return nil }
        return lab
    }

    private static func sample(level: Int, size: Int, target: Double, axis: Axis, attempts: Int, rng: inout SplitMix64) -> Board? {
        guard let baseLab = baseColor(axis: axis, delta: target, rng: &rng),
              let oddLab = shifted(baseLab, axis: axis, delta: target, rng: &rng),
              inRange(baseLab), inRange(oddLab),
              let base = ColorScience.rgb(from: baseLab),
              let odd = ColorScience.rgb(from: oddLab) else { return nil }
        let measured = ColorScience.distance(ColorScience.oklab(from: base), ColorScience.oklab(from: odd))
        guard measured.isFinite, target > 0 else { return nil }
        let ratio = measured / target
        guard ratio > 0.88 && ratio < 1.12 else { return nil }
        let quantizedBase = ColorScience.quantize(base)
        let quantizedOdd = ColorScience.quantize(odd)
        guard quantizedBase != quantizedOdd else { return nil }
        let quantizedDistance = ColorScience.distance(ColorScience.oklab(from: quantizedBase), ColorScience.oklab(from: quantizedOdd))
        guard quantizedDistance >= target * 0.72 else { return nil }
        if level == 1 {
            guard base.channelGap(to: odd) >= 0.065 else { return nil }
        } else if level == 2 {
            guard base.channelGap(to: odd) >= 0.04 else { return nil }
        }
        return Board(
            level: level,
            size: size,
            base: base,
            odd: odd,
            oddIndex: rng.int(below: size * size),
            axis: axis,
            distance: measured,
            attempts: attempts,
            synthesized: false
        )
    }

    private static func inRange(_ lab: OKLab) -> Bool {
        lab.L >= 0.48 && lab.L <= 0.88 && lab.a.isFinite && lab.b.isFinite
    }

    private static func baseColor(axis: Axis, delta: Double, rng: inout SplitMix64) -> OKLab? {
        let hue = rng.unit() * 2 * Double.pi
        switch axis {
        case .lightness:
            let low = 0.50 + delta
            let high = 0.86 - delta
            guard high > low + 0.01 else { return nil }
            let lightness = low + rng.unit() * (high - low)
            let chroma = 0.02 + rng.unit() * 0.045
            return OKLab(L: lightness, a: cos(hue) * chroma, b: sin(hue) * chroma)
        case .chroma:
            let lightness = 0.56 + rng.unit() * 0.2
            let chroma = delta + 0.03 + rng.unit() * 0.06
            return OKLab(L: lightness, a: cos(hue) * chroma, b: sin(hue) * chroma)
        case .hue:
            let lightness = 0.62 + rng.unit() * 0.12
            let chroma = 0.08 + rng.unit() * 0.06
            return OKLab(L: lightness, a: cos(hue) * chroma, b: sin(hue) * chroma)
        case .mixed:
            let lightness = 0.64 + rng.unit() * 0.04
            let chroma = 0.055 + rng.unit() * 0.03
            return OKLab(L: lightness, a: cos(hue) * chroma, b: sin(hue) * chroma)
        }
    }

    private static func shifted(_ base: OKLab, axis: Axis, delta: Double, rng: inout SplitMix64) -> OKLab? {
        switch axis {
        case .lightness:
            return OKLab(L: base.L + rng.sign() * delta, a: base.a, b: base.b)
        case .chroma:
            let chroma = hypot(base.a, base.b)
            guard chroma > 0.02 else { return nil }
            let next = chroma + rng.sign() * delta
            guard next > 0.015 else { return nil }
            let scale = next / chroma
            return OKLab(L: base.L, a: base.a * scale, b: base.b * scale)
        case .hue:
            // 色相只转一个小角度，剩下的差别放到明度上，避免早关直接换成另一种颜色。
            let chroma = hypot(base.a, base.b)
            guard chroma > 0.03 else { return nil }
            let sign = rng.sign()
            let maxAngle = 20.0 * Double.pi / 180
            let maxChord = 2 * chroma * sin(maxAngle / 2)
            let hueChord = min(delta, maxChord)
            let lightChord = sqrt(max(0, delta * delta - hueChord * hueChord))
            let theta = 2 * asin(min(1, hueChord / (2 * chroma))) * sign
            let hue = atan2(base.b, base.a) + theta
            let lightSign = (base.L + sign * lightChord) >= 0.52 && (base.L + sign * lightChord) <= 0.84 ? sign : -sign
            return OKLab(L: base.L + lightSign * lightChord, a: cos(hue) * chroma, b: sin(hue) * chroma)
        case .mixed:
            // 第 1 关保持同一色相，只把明度和纯度拉开，所以差别明显，但仍然是同一种颜色。
            let lightnessShare = 0.84
            let chromaShare = sqrt(1 - lightnessShare * lightnessShare)
            let chroma = hypot(base.a, base.b)
            guard chroma > 0.02 else { return nil }
            let lightnessShift = delta * lightnessShare
            let chromaShift = delta * chromaShare
            var sign = rng.sign()
            func fits(_ direction: Double) -> Bool {
                let nextLightness = base.L + direction * lightnessShift
                let nextChroma = chroma + direction * chromaShift
                return nextLightness >= 0.52 && nextLightness <= 0.84 && nextChroma > 0.035 && nextChroma < 0.2
            }
            if !fits(sign) { sign = -sign }
            guard fits(sign) else { return nil }
            let scale = (chroma + sign * chromaShift) / chroma
            return OKLab(L: base.L + sign * lightnessShift, a: base.a * scale, b: base.b * scale)
        }
    }

    private static func fallback(level: Int, size: Int, target: Double, axis: Axis, rng: inout SplitMix64) -> Board {
        let shift = min(0.2, max(0.05, target))
        let base = RGB(r: 0.56, g: 0.63, b: 0.61)
        let odd = RGB(r: clamp(base.r + shift, 0, 1), g: clamp(base.g - shift * 0.25, 0, 1), b: base.b)
        let distance = ColorScience.distance(ColorScience.oklab(from: base), ColorScience.oklab(from: odd))
        return Board(
            level: level,
            size: size,
            base: base,
            odd: odd,
            oddIndex: rng.int(below: size * size),
            axis: axis,
            distance: distance,
            attempts: 72,
            synthesized: true
        )
    }
}

private func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
    min(high, max(low, value))
}
