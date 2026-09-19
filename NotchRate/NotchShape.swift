import SwiftUI

/// Notch silhouette: top corners flare outward into the bezel, bottom corners
/// round inward. Geometry after DynamicNotchKit (MIT).
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + topRadius, y: r.minY + topRadius),
                       control: CGPoint(x: r.minX + topRadius, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + topRadius, y: r.maxY - bottomRadius))
        p.addQuadCurve(to: CGPoint(x: r.minX + topRadius + bottomRadius, y: r.maxY),
                       control: CGPoint(x: r.minX + topRadius, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - topRadius - bottomRadius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - topRadius, y: r.maxY - bottomRadius),
                       control: CGPoint(x: r.maxX - topRadius, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - topRadius, y: r.minY + topRadius))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY),
                       control: CGPoint(x: r.maxX - topRadius, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Notch body plus one blob slot per side, drawn through blur + alpha threshold so blobs melt into
/// the notch (Dynamic Island style). Per side, `merge` 0 = blob out at rest, 1 = absorbed (or absent):
/// animating it pops a new blob out of the notch and pulls it back in on expand.
struct GooBody: View, @preconcurrency Animatable {
    var shape: NotchShape
    var blob: CGFloat  // diameter
    var gap: CGFloat
    var slack: Bool    // frame has blob room on both sides (not animated: it jumps with the window)
    var reach: CGFloat // 0 collapsed, 1 expanded: body takes the slack over, faster than the blobs travel
    var left: CGFloat
    var right: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { .init(shape.animatableData, .init(reach, .init(left, right))) }
        set { shape.animatableData = newValue.first; reach = newValue.second.first; left = newValue.second.second.first; right = newValue.second.second.second }
    }

    var body: some View {
        Canvas { ctx, size in
            let l = max(0, min(1, left)), r = max(0, min(1, right))
            let inset = slack ? (blob + gap) * max(0, 1 - 1.6 * reach) : 0  // body reaches out to a blob before it lands
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
