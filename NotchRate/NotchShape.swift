import SwiftUI

/// Notch silhouette: top corners flare outward into the bezel, bottom corners
/// round inward. Cubic quarter-circles, same element list at every size, so
/// Core Animation can interpolate between any two of them.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    /// Radii follow the height: a closed island keeps the notch's own small corners, an open one
    /// reaches the full flare and `cardRadius`, so the corners grow continuously while it opens.
    static func forHeight(_ h: CGFloat, notch: Bool, cardRadius: CGFloat) -> NotchShape {
        NotchShape(topRadius: notch ? min(14, h * 0.19) : 0, bottomRadius: min(cardRadius, h * 0.34))
    }

    func path(in r: CGRect) -> Path {
        let t = min(topRadius, r.width / 4, r.height / 2)
        let b = max(0, min(bottomRadius, (r.width - 2 * t) / 2, r.height - t))
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.corner(to: CGPoint(x: r.minX + t, y: r.minY + t), via: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - b))
        p.corner(to: CGPoint(x: r.minX + t + b, y: r.maxY), via: CGPoint(x: r.minX + t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t - b, y: r.maxY))
        p.corner(to: CGPoint(x: r.maxX - t, y: r.maxY - b), via: CGPoint(x: r.maxX - t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
        p.corner(to: CGPoint(x: r.maxX, y: r.minY), via: CGPoint(x: r.maxX - t, y: r.minY))
        p.closeSubpath()
        return p
    }
}

private extension Path {
    /// Quarter circle from the current point to `end`, bending around the square corner `via`.
    mutating func corner(to end: CGPoint, via c: CGPoint) {
        let k: CGFloat = 0.5523, start = currentPoint ?? end
        addCurve(to: end, control1: CGPoint(x: start.x + (c.x - start.x) * k, y: start.y + (c.y - start.y) * k),
                 control2: CGPoint(x: end.x + (c.x - end.x) * k, y: end.y + (c.y - end.y) * k))
    }
}

/// Collapsed notch body plus one blob slot per side, drawn through blur + alpha threshold so blobs melt into
/// the notch (Dynamic Island style). Per side, `merge` 0 = blob out at rest, 1 = absorbed (or absent):
/// animating it pops a new blob out of the notch and pulls it back in on expand. The open card itself is
/// the canvas's Core Animation silhouette, drawn underneath.
struct GooBody: View, @preconcurrency Animatable {
    var shape: NotchShape
    var blob: CGFloat  // diameter
    var gap: CGFloat
    var slack: Bool    // frame has blob room on both sides
    var left: CGFloat
    var right: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(left, right) }
        set { left = newValue.first; right = newValue.second }
    }

    var body: some View {
        Canvas { ctx, size in
            let l = max(0, min(1, left)), r = max(0, min(1, right))
            let inset = slack ? blob + gap : 0
            let body = CGRect(x: inset, y: 0, width: size.width - 2 * inset, height: size.height)
            if min(l, r) < 1 {
                var goo = ctx
                goo.addFilter(.alphaThreshold(min: 0.5, color: .black))
                goo.addFilter(.blur(radius: 2 + 24 * max(l * (1 - l), r * (1 - r))))  // gooey only mid-transition
                goo.drawLayer { c in
                    c.fill(shape.path(in: body), with: .color(.black))
                    for (m, leading) in [(l, true), (r, false)] where m < 1 {
                        let stretch = blob * 1.8 * m * (1 - m)  // elongates toward the notch while moving
                        let travel = m * (gap + blob)           // slides in under the notch
                        let x = leading ? travel : size.width - blob - travel - stretch
                        c.fill(Ellipse().path(in: CGRect(x: x, y: 0, width: blob + stretch, height: blob)), with: .color(.black))
                    }
                }
            }
            ctx.fill(shape.path(in: body), with: .color(.black))  // crisp edges over the blurred pass
        }
    }
}
