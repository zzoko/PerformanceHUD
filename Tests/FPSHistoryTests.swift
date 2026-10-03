import AppKit

@main struct FPSHistoryTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    static func main() {
        var history = FPSHistory()
        var time = 100.0
        history.append(60, at: time)
        // Irregular arrivals reproduce the shifting oldest point after one minute.
        for index in 0..<1200 {
            time += [0.91, 1.04, 1.12, 0.98][index % 4]
            history.append(60 + sin(Double(index) / 10) * 10, at: time)
            let visible = history.visibleSegments
            check(visible.count == 1, "Continuous readings must remain connected")
            let first = visible[0][0]
            check(abs(first.time - max(100, time - 60)) < 0.000001,
                  "Filled history must reach the exact left boundary")
            check(visible[0].last!.time == time, "Newest sample must reach the right edge")
            check(visible[0].allSatisfy { $0.time >= time - 60 && $0.time <= time }, "No offscreen samples")
            check(history.samples.count <= 68, "Only one boundary predecessor is retained")
        }
        history.reset()
        history.append(0, at: 100)
        history.append(100, at: 102)
        history.advance(to: 161)
        check(history.visibleSegments[0][0].time == 101 && history.visibleSegments[0][0].fps == 50,
              "Boundary value interpolates between real samples")
        check(history.displayRange.lowerBound > 0, "Expired predecessor must not distort the visible range")
        history.advance(to: 163)
        check(history.samples.isEmpty && history.visibleSegments.isEmpty, "Unavailable history ages out completely")

        for explicit in [false, true] {
            history.reset()
            history.append(60, at: 100)
            if explicit { history.markUnavailable(at: 101) }
            history.append(75, at: explicit ? 102 : 105)
            history.advance(to: 161)
            check(history.visibleSegments.first?.first?.time == (explicit ? 102 : 105),
                  "Do not fill a real gap at the left edge")
        }
        history.reset()
        history.append(60, at: 100)
        history.append(61, at: 101)
        history.markUnavailable(at: 102)
        history.append(65, at: 103)
        check(history.visibleSegments.count == 2, "Internal interruptions remain separate")
        history.advance(to: 161)
        check(history.visibleSegments.count == 2 && history.visibleSegments[0][0].time == 101,
              "Exact boundary sample survives without extrapolation")
        history.append(70, at: 90)
        check(history.samples.count == 1 && history.samples[0].time == 90, "Backward clock resets history")
        history.append(.nan, at: 91)
        check(history.samples.count == 1, "Invalid FPS is ignored")
        for index in 0..<1000 { history.append(60, at: 100 + Double(index) / 100) }
        check(history.samples.count <= 256, "Storage remains bounded for bursts")
        print("PASS: jittered 20-minute history, stable left edge, boundary interpolation, visible range, genuine gaps, expiry, clock reset, bounded storage")
    }
}
