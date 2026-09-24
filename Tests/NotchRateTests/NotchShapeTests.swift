import CoreGraphics
import Testing
@testable import NotchRate

/// Core Animation only interpolates paths with the same element list; a mismatch snaps instead of springing.
@Test func notchShapeMorphsBetweenSizes() {
    func kinds(_ size: CGSize) -> [CGPathElementType] {
        var out: [CGPathElementType] = []
        NotchShape.forHeight(size.height, notch: true, cardRadius: 28)
            .path(in: CGRect(origin: .zero, size: size)).cgPath.applyWithBlock { out.append($0.pointee.type) }
        return out
    }
    #expect(kinds(CGSize(width: 290, height: 32)) == kinds(CGSize(width: 340, height: 300)))
    let closed = NotchShape.forHeight(32, notch: true, cardRadius: 28), open = NotchShape.forHeight(300, notch: true, cardRadius: 28)
    #expect(closed.topRadius < open.topRadius && closed.bottomRadius < open.bottomRadius && open.bottomRadius == 28)
    #expect(NotchShape.forHeight(300, notch: false, cardRadius: 28).topRadius == 0)
}
