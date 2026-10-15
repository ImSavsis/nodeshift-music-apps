import XCTest

extension XCTestCase {
    @MainActor
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
