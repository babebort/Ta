import XCTest
@testable import AIScreenshotApp

final class KeychainSecretStoreTests: XCTestCase {
    func testSaveReadAndDeleteUsingStandardMacKeychain() throws {
        let store = KeychainSecretStore(service: "com.kangarooking.AIScreenshot.tests.\(UUID().uuidString)")
        let account = "temporary-test-account"
        let value = "temporary-test-secret-\(UUID().uuidString)"

        defer { try? store.delete(account: account) }
        XCTAssertFalse(store.contains(account: account))
        try store.save(value, account: account)
        XCTAssertTrue(store.contains(account: account))
        XCTAssertEqual(try store.read(account: account), value)
        try store.delete(account: account)
        XCTAssertFalse(store.contains(account: account))
    }
}
