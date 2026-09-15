import Testing
@testable import NotchRate

@Test func versionCompare() {
    #expect(UpdateCheck.isNewer("v0.2.2", than: "0.2.1"))
    #expect(UpdateCheck.isNewer("v0.10.0", than: "0.9.0"))
    #expect(!UpdateCheck.isNewer("v0.2.1", than: "0.2.1"))
    #expect(!UpdateCheck.isNewer("v0.2.0", than: "0.2.1"))
}
