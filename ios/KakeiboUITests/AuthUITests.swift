import XCTest

// 画面のテスト（通信しない範囲）。接続先が未設定のビルドでも、設定済みのビルドでも動く
final class AuthUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testLaunchShowsLoginOrConfigMessage() {
        let app = XCUIApplication()
        app.launch()
        let configMissing = app.staticTexts["接続先が設定されていません"]
        let login = app.buttons["submit"]
        XCTAssertTrue(configMissing.waitForExistence(timeout: 10) || login.waitForExistence(timeout: 10))
    }

    func testLoginValidatesEmailBeforeNetwork() throws {
        let app = XCUIApplication()
        app.launch()
        let email = app.textFields["email"]
        guard email.waitForExistence(timeout: 10) else { throw XCTSkip("接続先が未設定のビルドなのでログイン画面がない") }
        email.tap()
        email.typeText("not-an-email")
        app.buttons["submit"].tap()
        XCTAssertTrue(app.staticTexts["メールアドレスの形が正しくありません"].waitForExistence(timeout: 5))
    }
}
