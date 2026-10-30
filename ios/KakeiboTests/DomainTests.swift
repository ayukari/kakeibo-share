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

    private func tx(_ day: Int, _ amount: Int64, kind: String = "expense", recurring: String? = nil, vis: String = "group", month: String = "2026-10") -> Txn {
        Txn(id: "t" + String(day) + "-" + String(amount), groupId: "g", kind: kind, amount: amount, occurredOn: month + "-" + String(format: "%02d", day), categoryId: "c", payerMemberId: "m", visibility: vis, recurringId: recurring)
    }

    func testPaceCumulativeSkipsFixedPrivateAndIncome() {
        let m = Money.date("2026-10-01")!
        let t = [tx(1, 1000), tx(1, 500), tx(3, 200), tx(2, 80000, recurring: "r"), tx(2, 999, vis: "private"), tx(4, 5000, kind: "income"), tx(5, 300, month: "2026-09")]
        let c = Insights.variableCumulative(t, month: m)
        XCTAssertEqual(c.count, 31)
        XCTAssertEqual([c[0], c[1], c[2], c[30]], [1500, 1500, 1700, 1700])
        XCTAssertEqual(Insights.fixedTotal(t, month: m), 80000)
    }

    func testPerDayAndDaysLeft() {
        let m = Money.date("2026-10-01")!
        XCTAssertEqual(Insights.daysLeft(month: m, today: Money.date("2026-10-29")!), 3)
        XCTAssertEqual(Insights.daysLeft(month: m, today: Money.date("2026-09-15")!), 31)
        XCTAssertEqual(Insights.daysLeft(month: m, today: Money.date("2026-11-02")!), 0)
        XCTAssertEqual(Insights.perDay(left: 20800, daysLeft: 3), 6933)
        XCTAssertEqual(Insights.perDay(left: -5, daysLeft: 3), 0)
        XCTAssertEqual(Insights.perDay(left: 100, daysLeft: 0), 0)
        XCTAssertEqual(Insights.idealLine(varBudget: 30, len: 3)!, [10, 20, 30])
        XCTAssertNil(Insights.idealLine(varBudget: 0, len: 3))
    }

    func testCalendarStepsAndShortAmounts() {
        XCTAssertEqual([0, 25, 26, 75, 76].map { Insights.step($0, max: 100) }, [0, 1, 2, 3, 4])
        XCTAssertEqual(Insights.short(3200), "3,200")
        XCTAssertEqual(Insights.short(80000), "80k")
        XCTAssertEqual(Insights.short(12400), "12k")
    }

    func testSavingsPaceWords() {
        let g = SavingsGoal(id: "g", groupId: "g", name: "旅行", target: 120000, dueMonth: "2027-09-01", autoAmount: 5000, autoDom: 25, startOn: "2026-10-01")
        func st(done: Bool = false, over: Bool = false, per: Int64? = nil, on: Bool? = nil) -> SavingsStatus {
            SavingsStatus(goalId: "g", saved: 29000, remaining: 91000, ratio: 0.24, done: done, monthsLeft: 12, perMonth: per, overdue: over, onTrack: on, thisMonth: 0)
        }
        XCTAssertEqual(Savings.pace(g, st(done: true)), "目標に届きました。")
        XCTAssertEqual(Savings.pace(g, st(over: true)), "期限（2027年9月）をすぎています。")
        XCTAssertEqual(Savings.pace(g, st(per: 7584, on: false)), "2027年9月までに毎月 ¥7,584・先取りでは ¥2,584 足りません")
        XCTAssertEqual(Savings.pace(g, st(per: 4000, on: true)), "2027年9月までに毎月 ¥4,000・先取りで届きます")
        var g2 = g; g2.dueMonth = nil
        XCTAssertEqual(Savings.pace(g2, st()), "あと ¥91,000・毎月25日に ¥5,000 先取り")
        XCTAssertEqual(Savings.domLabel(99), "月末")
    }

    func testSavingsMilestoneAndEmergency() {
        func r(_ day: String, _ a: Int64) -> PassbookRow { PassbookRow(id: day + String(a), goalId: "g", goalName: "x", day: day, amount: a, kind: "manual", balance: 0) }
        let today = Money.date("2026-10-29")!
        let m = Savings.milestone(target: 100000, rows: [r("2026-09-01", 30000), r("2026-10-05", 25000)], today: today)!
        XCTAssertEqual(m.pct, 50); XCTAssertTrue(m.thisMonth); XCTAssertEqual(m.text, "今月、半分まで来ました（50%）。")
        XCTAssertNil(Savings.milestone(target: 100000, rows: [r("2026-10-01", 1000)], today: today))
        XCTAssertEqual(Savings.milestone(target: 1000, rows: [r("2026-09-01", 1200)], today: today)?.pct, 100)
        XCTAssertEqual(Savings.emergencyTarget([0, 100000, 120000, 110000])?.target, 330000)
        XCTAssertEqual(Savings.emergencyTarget([97000])?.target, 300000)
        XCTAssertNil(Savings.emergencyTarget([0, 0]))
    }

    func testSavingsLeftover() {
        func b(_ cat: String?, _ amount: Int64, _ spent: Int64) -> BudgetStatus {
            BudgetStatus(budgetId: "b", scope: "group", categoryId: cat, memberId: nil, amount: amount, spent: spent, remaining: amount - spent, ratio: Double(spent) / Double(amount), over: spent > amount)
        }
        XCTAssertEqual(Savings.leftover([b("c1", 40000, 36000), b("c2", 5000, 3000), b(nil, 99999, 0)]), 6000)
        XCTAssertNil(Savings.leftover([b("c1", 10000, 12000)]))
        XCTAssertNil(Savings.leftover([]))
    }

    func testCalculatorKeypad() {
        XCTAssertEqual(Calc.evaluate("1200+380"), 1580)
        XCTAssertEqual(Calc.evaluate("1000+500÷2"), 1250)
        XCTAssertEqual(Calc.evaluate("1000÷3"), 333)
        XCTAssertEqual(Calc.evaluate("1200+"), 1200)
        XCTAssertNil(Calc.evaluate("5÷0")); XCTAssertNil(Calc.evaluate("")); XCTAssertNil(Calc.evaluate("−5"))
        var e = ""; for k in ["1", "2", "+", "×", "3", "="] { e = Calc.press(e, k) }
        XCTAssertEqual(e, "36")
        XCTAssertEqual(Calc.press("12", "C"), ""); XCTAssertEqual(Calc.press("12", "⌫"), "1"); XCTAssertEqual(Calc.press("", "00"), ""); XCTAssertEqual(Calc.press("0", "7"), "7")
        XCTAssertTrue(Calc.hasOperator("1+2")); XCTAssertFalse(Calc.hasOperator("12"))
    }

    func testRatioSplit() {
        XCTAssertEqual(Calc.ratioSplit(1000, [60, 40]), [600, 400])
        XCTAssertEqual(Calc.ratioSplit(1000, [34, 33, 33]), [340, 330, 330])
        XCTAssertEqual(Calc.ratioSplit(100, [34, 33, 33]), [34, 33, 33])
        XCTAssertEqual(Calc.ratioSplit(5, [34, 33, 33]), [2, 2, 1])
        XCTAssertEqual(Calc.ratioSplit(7, [50, 50]), [4, 3])
        XCTAssertEqual(Calc.ratioSplit(1000, [0, 100]), [0, 1000])
        XCTAssertEqual(Calc.ratioSplit(1000, [60, 30]), [667, 333])
        XCTAssertEqual(Calc.ratioSplit(1000, [2, 1, 1]), [500, 250, 250])
        XCTAssertEqual(Calc.ratioSplit(1000, [1, 1, 1]), [334, 333, 333])
        XCTAssertNil(Calc.ratioSplit(1000, [0, 0]))
    }
}
