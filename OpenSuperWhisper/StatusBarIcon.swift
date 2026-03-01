import AppKit

enum StatusBarIcon {

    /// Creates the static menu bar icon: side-profile lips with sound wave arcs.
    /// - Parameters:
    ///   - size: Icon size in points (default 18x18 — standard macOS menu bar)
    ///   - wavesCount: Number of wave arcs to draw (0-3). Use for animation frames.
    /// - Returns: Template NSImage suitable for NSStatusBarButton.
    static func create(size: NSSize = NSSize(width: 18, height: 18), wavesCount: Int = 3) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()

            let lineWidth: CGFloat = 1.5
            let w = rect.width
            let h = rect.height

            // -- Mouth/face profile (left side) --
            // Simplified side profile: nose tip → upper lip → mouth opening → lower lip → chin
            let profile = NSBezierPath()
            profile.lineWidth = lineWidth
            profile.lineCapStyle = .round
            profile.lineJoinStyle = .round

            // Start from nose tip area
            let noseX: CGFloat = w * 0.15
            let noseY: CGFloat = h * 0.72

            profile.move(to: NSPoint(x: noseX, y: noseY))
            // Down to upper lip
            profile.line(to: NSPoint(x: w * 0.28, y: h * 0.62))
            // Upper lip curve
            profile.curve(to: NSPoint(x: w * 0.38, y: h * 0.55),
                          controlPoint1: NSPoint(x: w * 0.32, y: h * 0.60),
                          controlPoint2: NSPoint(x: w * 0.36, y: h * 0.56))
            // Mouth opening (slight gap)
            profile.move(to: NSPoint(x: w * 0.38, y: h * 0.50))
            // Lower lip curve
            profile.curve(to: NSPoint(x: w * 0.28, y: h * 0.38),
                          controlPoint1: NSPoint(x: w * 0.36, y: h * 0.44),
                          controlPoint2: NSPoint(x: w * 0.32, y: h * 0.40))
            // Down to chin
            profile.line(to: NSPoint(x: w * 0.18, y: h * 0.22))

            profile.stroke()

            // -- Sound wave arcs (right side) --
            let waveCenterX: CGFloat = w * 0.40
            let waveCenterY: CGFloat = h * 0.52
            let startAngle: CGFloat = -40
            let endAngle: CGFloat = 40
            let baseRadius: CGFloat = w * 0.14
            let radiusStep: CGFloat = w * 0.12

            let clampedWaves = max(0, min(wavesCount, 3))
            for i in 0..<clampedWaves {
                let radius = baseRadius + CGFloat(i) * radiusStep
                let arc = NSBezierPath()
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                arc.appendArc(
                    withCenter: NSPoint(x: waveCenterX, y: waveCenterY),
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle
                )
                arc.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Pre-generates animation frames for recording indicator.
    /// Returns 4 frames: 0 waves, 1 wave, 2 waves, 3 waves.
    static func createAnimationFrames(size: NSSize = NSSize(width: 18, height: 18)) -> [NSImage] {
        (0...3).map { create(size: size, wavesCount: $0) }
    }
}
