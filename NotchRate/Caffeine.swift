import IOKit.pwr_mgt

/// Keeps display and system awake via a power assertion; released with the process.
@MainActor
enum Caffeine {
    private static var id: IOPMAssertionID = 0

    static var on: Bool {
        get { id != 0 }
        set {
            guard newValue != on else { return }
            if newValue {
                IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn), "NotchRate: keep awake" as CFString, &id)
            } else {
                IOPMAssertionRelease(id)
                id = 0
            }
        }
    }
}
