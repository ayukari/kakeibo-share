import XCTest
@testable import Kakeibo

// 両 OS とサーバーで共有するテストの値（tests/vectors。テストのバンドルに入れている）
final class DomainTests: XCTestCase {
    private func vector(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: DomainTests.self).url(forResource: name, withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testEqualSplitMatchesSharedVectors() throws {
        let cases = try XCTUnwrap(try vector("splits")["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6)
        for c in cases {
            let amount = Int64(c["amount"] as! Int), n = c["members"] as! Int
            let expected = (c["expected"] as! [Int]).map(Int64.init)
            let got = Money.equalSplit(amount, n)
            XCTAssertEqual(got, expected)
            XCTAssertEqual(got.reduce(0, +), amount)
        }
    }

    func testErrorKindsMatchSharedVectors() throws {
        let cases = try XCTUnwrap(try vector("errors")["cases"] as? [[String: Any]])
        for c in cases {
            let code = c["code"] as? String
            let kind = AppError.fromCode(code, message: "", hint: nil, http: c["http"] as? Int).kind
            XCTAssertEqual(kind.rawValue, c["kind"] as? String, "\(code ?? "nil")/\(c["http"] ?? "")")
        }
    }

    func testParseAcceptsJapaneseInputAndRejectsFractions() {
        XCTAssertEqual(Money.parse("1,200"), 1200)
        XCTAssertEqual(Money.parse("¥１２００円"), 1200)
        XCTAssertNil(Money.parse("12.5"))
        XCTAssertNil(Money.parse("-100"))
        XCTAssertNil(Money.parse(""))
        XCTAssertNil(Money.parse("1e3"))
    }

    func testAmountRange() {
        XCTAssertNotNil(Validate.amount("0"))
        XCTAssertNil(Validate.amount("1"))
        XCTAssertNil(Validate.amount("999,999,999"))
        XCTAssertNotNil(Validate.amount("1000000000"))
    }

    func testFormatYen() {
        XCTAssertEqual(Money.format(1234), "¥1,234")
        XCTAssertEqual(Money.format(-500), "−¥500")
    }

    func testDatesAreJapanTime() {
        let d = Money.date("2026-03-31")!
        XCTAssertEqual(Money.dateString(d), "2026-03-31")
        XCTAssertEqual(Money.dateString(Money.monthStart(d)), "2026-03-01")
        XCTAssertEqual(Money.dateString(Money.addMonths(Money.monthStart(d), 1)), "2026-04-01")
    }

    func testOtherValidations() {
        XCTAssertNotNil(Validate.date(nil))
        XCTAssertNil(Validate.date(Money.todayJST()))
        XCTAssertNotNil(Validate.memo(String(repeating: "a", count: 501)))
        XCTAssertNotNil(Validate.groupName("  "))
        XCTAssertNotNil(Validate.email("abc"))
        XCTAssertNil(Validate.email("a@b.jp"))
        XCTAssertNotNil(Validate.password("1234567"))
        XCTAssertNotNil(Validate.customSplit(1000, [500, 400]))
        XCTAssertNil(Validate.customSplit(1000, [600, 400]))
    }

    func testServerMessages() {
        let v = AppError.fromCode("KB422", message: "amount_invalid", hint: "amount", http: 400)
        XCTAssertEqual(v.kind, .Validation)
        XCTAssertEqual(v.field, "amount")
        XCTAssertTrue(v.userMessage.contains("999,999,999"))
        XCTAssertTrue(AppError(kind: .Network).userMessage.contains("保存はされていません"))
    }

    func testCsvEscapesAndBlocksFormulas() {
        XCTAssertEqual(Csv.cell("=SUM(A1)"), "'=SUM(A1)")
        XCTAssertEqual(Csv.cell("a,b"), "\"a,b\"")
        XCTAssertEqual(Csv.cell("say \"hi\""), "\"say \"\"hi\"\"\"")
        let t = Txn(id: "t1", groupId: "g", kind: "expense", amount: 1000, occurredOn: "2026-10-01", categoryId: "c1", payerMemberId: "m1", memo: "+danger,1", splitMode: "equal")
        let out = Csv.transactions([t], splits: ["t1": [Split(transactionId: "t1", memberId: "m1", amount: 500), Split(transactionId: "t1", memberId: "m2", amount: 500)]],
                                   cat: { _ in "食費" }, member: { $0 == "m1" ? "A" : "B" }, pm: { _ in "" })
        let lines = out.components(separatedBy: "\r\n")
        XCTAssertTrue(lines[0].hasPrefix("日付,種類,金額"))
        XCTAssertEqual(lines[1], "2026-10-01,支出,1000,食費,A,,\"'+danger,1\",グループ,均等,A:500 B:500,t1")
        XCTAssertEqual(Csv.bom.count, 3)
    }

    func testInviteCodeGrouping() {
        XCTAssertEqual(MemberView.grouped("ABCDEFGHJKLM"), "ABCD-EFGH-JKLM")
    }
}
