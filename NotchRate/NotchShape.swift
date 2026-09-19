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

/// Notch body plus up to one side blob per side, drawn through blur + alpha threshold so the
/// blobs melt into the notch as `merge` runs 0 → 1 (Dynamic Island style). Diameter 0 = no blob.
struct GooBody: View, @preconcurrency Animatable {
    var shape: NotchShape
    var left: CGFloat
    var right: CGFloat
    var gap: CGFloat
    var merge: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { .init(shape.animatableData, merge) }
        set { shape.animatableData = newValue.first; merge = newValue.second }
    }

    var body: some View {
        Canvas { ctx, size in
            let m = max(0, min(1, merge))
            let d = max(left, right)
            let inset = (d + gap) * max(0, 1 - 1.6 * m)  // body reaches out to the blob before it lands
            let body = CGRect(x: inset, y: 0, width: size.width - 2 * inset, height: size.height)
            if d > 0 {
                var goo = ctx
                goo.addFilter(.alphaThreshold(min: 0.5, color: .black))
                goo.addFilter(.blur(radius: 2 + 24 * m * (1 - m)))  // gooey only mid-transition
                goo.drawLayer { l in
                    l.fill(shape.path(in: body), with: .color(.black))
                    let stretch = d * 1.8 * m * (1 - m)  // elongates toward the notch while moving
                    let travel = merge * (gap + d)       // slides in under the notch
                    if right > 0 { l.fill(Ellipse().path(in: CGRect(x: size.width - right - travel - stretch, y: 0, width: right + stretch, height: right)), with: .color(.black)) }
                    if left > 0 { l.fill(Ellipse().path(in: CGRect(x: travel, y: 0, width: left + stretch, height: left)), with: .color(.black)) }
                }
            }
            ctx.fill(shape.path(in: body), with: .color(.black))  // crisp edges over the blurred pass
        }
    }
}
