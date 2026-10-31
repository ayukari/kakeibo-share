import SwiftUI

// ---------- 収支の一覧（リストとカレンダー。月・種類・カテゴリ・払った人・メモの検索・並べ替え） ----------
struct TxnListView: View {
    let ctx: GroupCtx
    @Binding var month: Date
    @State private var state: Loadable<[Txn]> = .loading
    @State private var mode = 0   // 0 = リスト、1 = カレンダー
    @State private var kind = "all"
    @State private var catId: String? = nil
    @State private var payerId: String? = nil
    @State private var query = ""
    @State private var sort = "new"
    @State private var selDay: Int? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                MonthBar(month: $month)
                Segmented(options: ["リスト", "カレンダー"], selected: $mode).padding(.vertical, 4)
                if mode == 0 { filters }
                LoadableView(state: state, retry: load) { all in
                    if mode == 1 { CalendarSection(ctx: ctx, month: month, all: all, selDay: $selDay) }
                    else { list(all) }
                }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
        }
        .background(Color.kBg)
        .searchable(text: $query, prompt: "メモ・カテゴリ・人・金額で探す")
        // タブは 5 つまで（6 つ以上だと iPhone では「その他」にまとめられる）。レポートは「収支」の右上から
        .toolbar { ToolbarItem(placement: .primaryAction) { NavigationLink { ReportView(ctx: ctx, month: $month) } label: { Label("レポート", systemImage: "chart.bar") } } }
        .task(id: "\(month)-\(ctx.refresh)") { selDay = nil; await load() }
        .refreshable { await load() }
    }

    private var filters: some View {
        VStack(spacing: 8) {
            Picker("種類", selection: $kind) { Text("すべて").tag("all"); Text("支出").tag("expense"); Text("収入").tag("income") }.pickerStyle(.segmented)
            HStack {
                Picker("カテゴリ", selection: $catId) {
                    Text("すべて").tag(String?.none)
                    ForEach(ctx.cats.filter { kind == "all" || $0.kind == kind }) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("払った人", selection: $payerId) {
                    Text("全員").tag(String?.none)
                    ForEach(ctx.members) { Text($0.displayName).tag(Optional($0.id)) }
                }
                Picker("並べ替え", selection: $sort) { Text("新しい順").tag("new"); Text("古い順").tag("old"); Text("金額順").tag("amount") }
            }.tint(Color.kSub)
        }
    }

    @ViewBuilder private func list(_ all: [Txn]) -> some View {
        let l = filtered(all)
        let inc = l.filter { $0.kind == "income" }.reduce(Int64(0)) { $0 + $1.amount }
        let exp = l.filter { $0.kind == "expense" }.reduce(Int64(0)) { $0 + $1.signed }
        SectionLabel(text: "\(l.count) 件", trailing: "収入 \(Money.format(inc))・支出 \(Money.format(exp))")
        if l.isEmpty {
            Paper { EmptyBox(title: all.isEmpty ? "この月の記録はありません" : "条件に合う記録はありません", message: all.isEmpty ? "月を変えるか、記録を追加してください" : "絞り込みを変えてみてください") }
        } else {
            ListPaper { ForEach(Array(l.enumerated()), id: \.element.id) { i, t in if i > 0 { DashedLine() }; TxnLink(ctx: ctx, t: t) } }
        }
    }

    // メモ・カテゴリ・払った人・金額（1,200 や ¥1200 も可）で探す
    private func matches(_ t: Txn, _ q: String) -> Bool {
        if t.memo.localizedCaseInsensitiveContains(q) { return true }
        if let c = ctx.cat(t.categoryId), c.name.localizedCaseInsensitiveContains(q) { return true }
        if ctx.memberName(t.payerMemberId).localizedCaseInsensitiveContains(q) { return true }
        return String(t.amount) == q.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "¥", with: "")
    }

    private func filtered(_ all: [Txn]) -> [Txn] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let l = all.filter { t in
            (kind == "all" || t.kind == kind) && (catId == nil || t.categoryId == catId) && (payerId == nil || t.payerMemberId == payerId) &&
            (q.isEmpty || matches(t, q))
        }
        switch sort { case "old": return l.reversed(); case "amount": return l.sorted { $0.amount > $1.amount }; default: return l }
    }

    private func load() async {
        do { state = .ready(try await ctx.repo.transactions(ctx.g, from: month, toExclusive: Money.addMonths(month, 1))) } catch { state = .failed(Repo.map(error)) }
    }
}

// カレンダー（支出が多い日ほど濃い緑。1 色の濃淡だけ）。日を押すと、その日の記録
struct CalendarSection: View {
    let ctx: GroupCtx
    let month: Date
    let all: [Txn]
    @Binding var selDay: Int?

    private func shade(_ step: Int) -> Color {
        switch step {
        case 0: return .kBg
        case 1: return Color.kAccent.opacity(0.18)
        case 2: return Color.kAccent.opacity(0.38)
        case 3: return Color.kAccent.opacity(0.62)
        default: return .kAccent
        }
    }

    var body: some View {
        let days = Insights.dailyExpense(all, month: month)
        let mx = days.max() ?? 0
        let today = Money.todayJST()
        let isCurMonth = Money.monthStart(today) == Money.monthStart(month)
        let first = Money.monthStart(month)
        let firstDow = (Money.calendar.component(.weekday, from: first) + 5) % 7   // 月曜 = 0
        let inc = all.filter { $0.kind == "income" && $0.status == "active" && $0.visibility == "group" }.reduce(Int64(0)) { $0 + $1.amount }
        let exp = days.reduce(0, +)
        let sel = selDay ?? (isCurMonth ? Money.calendar.component(.day, from: today) : nil)
        let m = Money.calendar.component(.month, from: month)
        Paper(padding: 12) {
            HStack(spacing: 4) { ForEach(Array("月火水木金土日".enumerated()), id: \.offset) { _, c in Text(String(c)).font(.system(size: 12)).foregroundStyle(Color.kFaint).frame(maxWidth: .infinity) } }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<(firstDow + days.count), id: \.self) { idx in
                    if idx < firstDow { Color.clear.aspectRatio(1 / 1.05, contentMode: .fit) }
                    else {
                        let day = idx - firstDow + 1, v = days[day - 1], step = Insights.step(v, max: mx)
                        let fg: Color = step >= 3 ? .kAccentInk : .kInk
                        let isToday = isCurMonth && Money.calendar.component(.day, from: today) == day
                        Button { selDay = day } label: {
                            VStack(spacing: 0) {
                                Text("\(day)").font(.system(size: 12, weight: .bold)).foregroundStyle(fg)
                                Spacer(minLength: 0)
                                Text(v > 0 ? Insights.short(v) : "").font(.system(size: 9)).foregroundStyle(fg.opacity(0.85)).lineLimit(1)
                            }.padding(.vertical, 3).frame(maxWidth: .infinity).aspectRatio(1 / 1.05, contentMode: .fit)
                                .background(shade(step), in: RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(day == sel ? Color.kInk : isToday ? Color.kAccent : Color.clear, lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityLabel("\(m)月\(day)日 \(Money.format(v))")
                    }
                }
            }.padding(.top, 4)
            HStack(spacing: 2) {
                Spacer(); FaintText("少ない ")
                ForEach(0..<5, id: \.self) { RoundedRectangle(cornerRadius: 2).fill(shade($0)).frame(width: 14, height: 14) }
                FaintText(" 多い")
            }.padding(.top, 6)
            DashedLine().padding(.vertical, 8)
            HStack {
                VStack(alignment: .leading) { FaintText("収入"); Text(Money.format(inc)).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk) }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading) { FaintText("支出"); Text(Money.format(exp)).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk) }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading) { FaintText("収支"); Text((inc - exp > 0 ? "+" : "") + Money.format(inc - exp)).font(.system(size: 16, weight: .bold)).foregroundStyle(inc - exp < 0 ? Color.kDanger : Color.kInk) }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if let sel {
            let key = String(Money.dateString(first).prefix(7)) + "-" + String(format: "%02d", sel)
            let ls = all.filter { $0.status == "active" && $0.occurredOn == key }
            let dayTotal = ls.filter { $0.kind == "expense" }.reduce(Int64(0)) { $0 + $1.signed }
            SectionLabel(text: "\(m)/\(sel)", trailing: ls.isEmpty ? nil : Money.format(dayTotal))
            if ctx.can("member") {
                NavigationLink { TxnEditView(ctx: ctx, txn: nil, initialDate: Money.calendar.date(byAdding: .day, value: sel - 1, to: first)) } label: {
                    Text("＋ この日に記録する").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk).frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.kCard, in: buttonShape).overlay(buttonShape.stroke(Color.kLine, lineWidth: 1))
                }.buttonStyle(.plain).padding(.bottom, 8)
            }
            if ls.isEmpty { Paper { SubText("この日の記録はありません") } }
            else { ListPaper { ForEach(Array(ls.enumerated()), id: \.element.id) { i, t in if i > 0 { DashedLine() }; TxnLink(ctx: ctx, t: t) } } }
        }
    }
}

// ---------- 取引の入力・編集 ----------
struct TxnEditView: View {
    let ctx: GroupCtx
    let txn: Txn?
    var initialDate: Date? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var requestId = UUID().uuidString.lowercased()   // 同じ入力の再送を二重登録にしない
    @State private var kind = "expense"
    @State private var amount = ""
    @State private var date = Money.todayJST()
    @State private var catId: String? = nil
    @State private var payerId: String? = nil
    @State private var pmId: String? = nil
    @State private var memo = ""
    @State private var isPrivate = false
    @State private var isRefund = false
    @State private var split = "none"
    @State private var equal: Set<String> = []
    @State private var custom: [String: String] = [:]
    @State private var ratio: [String: String] = [:]   // 割合（%）で分けるとき
    @State private var splitsLoaded = true
    @State private var error: String?
    @State private var amountError: String?
    @State private var busy = false
    @State private var similar: [Txn]? = nil
    @State private var askDelete = false
    @State private var started = false
    // 入力を速く: 前回のカテゴリと払った人を覚える・メモからカテゴリを推す・最近の入力（docs/research-deep-2026-10-30.md）
    @State private var history: [Txn] = []
    @State private var catTouched = false
    @State private var showAllCats = false
    @State private var details = false

    private func rememberedCat(_ k: String) -> String? {
        guard let id = UserDefaults.standard.string(forKey: "kakeibo.input.cat.\(ctx.g).\(k)"), let c = ctx.cat(id), c.archivedAt == nil else { return nil }
        return c.id
    }
    private var orderedCats: [Category] {
        InputHints.categoryOrder(history, ctx.cats.filter { $0.kind == kind && ($0.archivedAt == nil || $0.id == txn?.categoryId) })
    }
    private var summary: String {
        var parts: [String] = []
        if let p = ctx.members.first(where: { $0.id == payerId }) { parts.append(p.displayName + (kind == "income" || isRefund ? "が受け取った" : "が払った")) }
        if let pm = ctx.pms.first(where: { $0.id == pmId }) { parts.append(pm.name) }
        if isRefund { parts.append("返金") }
        if isPrivate { parts.append("自分だけ") }
        if kind == "expense" && !isPrivate {
            switch split { case "equal": parts.append("均等に割り勘"); case "ratio": parts.append("割合で割り勘"); case "custom": parts.append("金額で割り勘"); default: break }
        }
        return parts.joined(separator: "・")
    }

    private var splitMembers: [Member] { ctx.members.filter { $0.status == "active" || equal.contains($0.id) || custom[$0.id] != nil } }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Segmented(options: ["支出", "収入"], selected: Binding(get: { kind == "expense" ? 0 : 1 }, set: { kind = $0 == 0 ? "expense" : "income" }))
                    DateStepper(date: $date)
                    let recents = txn == nil ? InputHints.recent(history, kind: kind) : []
                    if !recents.isEmpty {
                        // 最近の入力: 押すと金額・カテゴリ・メモをまとめて入れる（日付は今のまま）
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(recents) { t in
                                    let c = ctx.cat(t.categoryId)
                                    Button {
                                        amount = String(t.amount); catId = t.categoryId; memo = t.memo; catTouched = true; amountError = nil
                                    } label: {
                                        Text("\(c?.icon ?? "") \(Money.format(t.amount)) \(t.memo.isEmpty ? (c?.name ?? "") : t.memo)")
                                            .font(.system(size: 14)).foregroundStyle(Color.kInk).lineLimit(1)
                                            .padding(.horizontal, 10).frame(minHeight: 40)
                                            .background(Color.kCard, in: buttonShape).overlay(buttonShape.stroke(Color.kLine, lineWidth: 1))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    AmountDisplay(expr: amount, error: amountError)
                    CalcKeypad { k in amount = Calc.press(amount, k); amountError = nil }
                }.listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    .onChange(of: kind) { if ctx.cat(catId)?.kind != kind { catId = txn == nil ? rememberedCat(kind) : nil } }
            }
            Section {
                let all = orderedCats
                let shown = showAllCats || all.count <= 8 ? all : Array(all.prefix(8)) + all.dropFirst(8).filter { $0.id == catId }
                CategoryGrid(cats: shown, selected: Binding(get: { catId }, set: { catId = $0; catTouched = true }))
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            } header: {
                HStack {
                    Text("カテゴリ")
                    Spacer()
                    if orderedCats.count > 8 { Button(showAllCats ? "よく使うものだけ" : "すべて（\(orderedCats.count)）") { showAllCats.toggle() }.font(.caption) }
                }
            }
            Section {
                TextField("メモ（任意）", text: $memo)
                    .onChange(of: memo) {
                        // 前に同じメモで使ったカテゴリを選んでおく（自分でカテゴリを選んだあとは変えない）
                        if !catTouched, let id = InputHints.categoryForMemo(history, memo: memo, kind: kind), let c = ctx.cat(id), c.archivedAt == nil { catId = c.id }
                    }
                // くわしく: 払った人・支払い方法・返金・自分だけ（ふだんは閉じておき、決めた内容を 1 行で見せる）
                DisclosureGroup(isExpanded: $details) {
                    if kind == "expense" { Toggle("返金（払い戻し・返品で戻ってきたお金。支出と立替から引きます）", isOn: $isRefund) }
                    Picker(kind == "income" || isRefund ? "受け取った人" : "払った人", selection: $payerId) {
                        ForEach(ctx.members.filter { $0.status == "active" || $0.id == txn?.payerMemberId }) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    Picker("支払い方法（任意）", selection: $pmId) {
                        Text("なし").tag(String?.none)
                        ForEach(ctx.pms.filter { $0.archivedAt == nil || $0.id == txn?.paymentMethodId }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Toggle("自分だけに見せる（グループの集計と精算には入りません）", isOn: $isPrivate)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("くわしく").bold()
                        Text(summary).font(.caption).foregroundStyle(Color.kSub).lineLimit(1)
                    }
                }
            }
            if details && kind == "expense" && !isPrivate {
                Section("割り勘") {
                    Picker("割り勘", selection: $split) { Text("しない").tag("none"); Text("均等").tag("equal"); Text("割合").tag("ratio"); Text("金額").tag("custom") }.pickerStyle(.segmented)
                    let a = Calc.evaluate(amount) ?? 0
                    if split == "equal" {
                        let chosen = splitMembers.filter { equal.contains($0.id) }
                        let shares = Money.equalSplit(a, Swift.max(chosen.count, 1))
                        ForEach(splitMembers) { m in
                            Toggle(isOn: Binding(get: { equal.contains(m.id) }, set: { if $0 { equal.insert(m.id) } else { equal.remove(m.id) } })) {
                                HStack { Text(m.displayName); Spacer(); if let i = chosen.firstIndex(of: m), a > 0 { Text(Money.format(shares[i])).monospacedDigit() } }
                            }
                        }
                        Text("割り切れない 1 円は、参加の早い人から順に負担します（サーバーで計算）").font(.caption)
                    } else if split == "ratio" {
                        let shares = Calc.ratioSplit(a, splitMembers.map { Int(ratio[$0.id] ?? "") ?? 0 })
                        ForEach(Array(splitMembers.enumerated()), id: \.element.id) { i, m in
                            HStack {
                                Text(m.displayName)
                                Spacer()
                                TextField("0", text: Binding(get: { ratio[m.id] ?? "" }, set: { ratio[m.id] = String($0.filter(\.isNumber).prefix(3)) })).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 56)
                                Text(shares != nil && a > 0 ? Money.format(shares![i]) : "").monospacedDigit().frame(width: 88, alignment: .trailing)
                            }
                        }
                        let total = splitMembers.reduce(0) { $0 + (Int(ratio[$1.id] ?? "") ?? 0) }
                        let ratioText = splitMembers.map { ratio[$0.id] ?? "0" }.joined(separator: ":")
                        Text(total > 0 ? "比 \(ratioText) で分けます（60:40 の % でも、大人 2・子ども 1 の口数でも）" : "割合を入れてください").foregroundStyle(total > 0 ? Color.income : Color.over)
                    } else if split == "custom" {
                        ForEach(splitMembers) { m in
                            AmountField(label: "\(m.displayName)の負担", text: Binding(get: { custom[m.id] ?? "" }, set: { custom[m.id] = $0 }))
                        }
                        let sum = splitMembers.reduce(Int64(0)) { $0 + (custom[$1.id].flatMap(Money.parse) ?? 0) }
                        Text(sum == a ? "合計が金額と合っています" : "合計 \(Money.format(sum))（あと \(Money.format(a - sum))）").foregroundStyle(sum == a ? Color.income : Color.over)
                    }
                }
            }
            if txn != nil { Section { Button("この記録を消す", role: .destructive) { askDelete = true }.disabled(busy) } }
        }
        .safeAreaInset(edge: .bottom) {
            // 下に固定: 誤りの知らせと保存ボタン（スクロールしなくても押せる）
            VStack(spacing: 6) {
                if let error { Text(error).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("txnError") }
                Button { trySave() } label: {
                    HStack { Spacer(); if busy { ProgressView() } else { Text(kind == "income" ? "収入を記録する" : (isRefund ? "返金を記録する" : "支出を記録する")).bold().foregroundStyle(Color.kAccentInk) }; Spacer() }
                        .frame(minHeight: 52).background(Color.kAccent, in: buttonShape)
                }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("save")
            }
            .padding(.horizontal, 16).padding(.vertical, 8).background(Color.kBg)
        }
        .navigationTitle(txn == nil ? "記録する" : "取引の編集")
        .toolbar { if txn == nil { ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } } } }
        .task { await start() }
        .alert("似た記録があります", isPresented: Binding(get: { similar != nil }, set: { if !$0 { similar = nil } })) {
            Button("それでも保存") { similar = nil; if let t = input() { save(t) } }
            Button("やめる", role: .cancel) { similar = nil }
        } message: {
            Text("同じ日・同じ金額の記録が \(similar?.count ?? 0) 件あります。" + (similar ?? []).prefix(3).map { "\n・\(ctx.memberName($0.createdByMember ?? $0.payerMemberId))が記録: \(Money.format($0.amount)) \(ctx.cat($0.categoryId)?.name ?? "") \($0.memo)" }.joined() + "\n二重に入れていないか確かめてください。")
        }
        .confirmationDialog("記録を消しますか", isPresented: $askDelete, titleVisibility: .visible) {
            Button("消す", role: .destructive) { remove() }
        } message: { Text("操作の履歴には残ります。") }
    }

    private func start() async {
        guard !started else { return }
        started = true
        let act = ctx.activeMembers
        for (i, m) in act.enumerated() { ratio[m.id] = String(100 / max(1, act.count) + (i < 100 % max(1, act.count) ? 1 : 0)) }
        guard let t = txn else {
            payerId = ctx.me?.id; equal = Set(act.map(\.id)); if let d = initialDate { date = d }
            catId = rememberedCat(kind)
            if let pid = UserDefaults.standard.string(forKey: "kakeibo.input.payer.\(ctx.g)"), act.contains(where: { $0.id == pid }) { payerId = pid }
            history = (try? await ctx.repo.recentTransactions(ctx.g, limit: 300)) ?? []
            return
        }
        catTouched = true
        kind = t.kind; amount = String(t.amount); date = Money.date(t.occurredOn) ?? date; catId = t.categoryId; payerId = t.payerMemberId
        pmId = t.paymentMethodId; memo = t.memo; isPrivate = t.visibility == "private"; isRefund = t.refund; split = t.splitMode
        details = t.paymentMethodId != nil || isPrivate || isRefund || t.splitMode != "none" || t.payerMemberId != ctx.me?.id
        if t.splitMode != "none" {
            splitsLoaded = false
            do {
                let ss = try await ctx.repo.splits([t.id])
                equal = Set(ss.map(\.memberId)); for s in ss { custom[s.memberId] = String(s.amount) }
                splitsLoaded = true
            } catch { self.error = "割り勘の内訳を読めませんでした: \(Repo.map(error).userMessage)" }
        }
    }

    private func input() -> TxnInput? {
        let v = Calc.evaluate(amount)
        amountError = v == nil ? "金額は 1 円以上の整数で入れてください" : Validate.amount(String(v!)); error = nil
        let a = v ?? 0
        let shares = splitMembers.compactMap { custom[$0.id].flatMap(Money.parse) }
        let problem = firstProblem(a: a, shares: shares)
        if let problem { if problem != amountError { error = problem }; return nil }   // 金額の誤りは入力欄の下に出す
        let mode = (kind == "income" || isPrivate) ? "none" : (split == "ratio" ? "custom" : split)
        let ratioShares: [String: Int64] = split == "ratio" ? Dictionary(uniqueKeysWithValues: zip(splitMembers.map(\.id), Calc.ratioSplit(a, splitMembers.map { Int(ratio[$0.id] ?? "") ?? 0 }) ?? []).filter { $0.1 > 0 }) : [:]
        return TxnInput(id: txn?.id, version: txn?.version, clientRequestId: requestId, kind: kind, amount: a, occurredOn: Money.dateString(date),
                        categoryId: catId!, payerMemberId: payerId!, paymentMethodId: pmId, memo: memo.trimmingCharacters(in: .whitespacesAndNewlines),
                        visibility: isPrivate ? "private" : "group", splitMode: mode,
                        equalMembers: splitMembers.map(\.id).filter { equal.contains($0) },
                        customShares: split == "ratio" ? ratioShares : custom.compactMapValues { Money.parse($0) }.filter { $0.value > 0 },
                        isRefund: kind == "expense" && isRefund)
    }

    // 入力の誤りを上から順に調べ、最初の 1 つを返す（金額の誤りは入力欄の下に出す）
    private func firstProblem(a: Int64, shares: [Int64]) -> String? {
        if let e = amountError { return e }
        if let e = Validate.date(date) { return e }
        if catId == nil { return "カテゴリを選んでください" }
        if payerId == nil { return "払った人を選んでください" }
        if let e = Validate.memo(memo) { return e }
        if split == "equal" && equal.isEmpty { return "割り勘する人を選んでください" }
        if split == "custom", let e = Validate.customSplit(a, shares) { return e }
        if split == "ratio" && Calc.ratioSplit(a, splitMembers.map { Int(ratio[$0.id] ?? "") ?? 0 }) == nil { return "割合を 1 以上で入れてください" }
        if !splitsLoaded { return "割り勘の内訳を読み込めていません" }
        return nil
    }

    private func save(_ t: TxnInput) {
        busy = true
        Task { @MainActor in
            do {
                _ = try await ctx.repo.saveTransaction(ctx.g, t)
                if txn == nil {
                    UserDefaults.standard.set(t.categoryId, forKey: "kakeibo.input.cat.\(ctx.g).\(t.kind)")
                    UserDefaults.standard.set(t.payerMemberId, forKey: "kakeibo.input.payer.\(ctx.g)")
                }
                ctx.app.toast = txn == nil ? "保存しました" : "変更を保存しました"
                ctx.refresh += 1
                dismiss()
            } catch { self.error = Repo.map(error).userMessage }
            busy = false
        }
    }

    private func trySave() {
        guard let t = input() else { return }
        if txn != nil { save(t); return }
        busy = true
        Task { @MainActor in
            do {
                let s = try await ctx.repo.similar(ctx.g, amount: t.amount, date: t.occurredOn, category: t.categoryId)
                busy = false
                if s.isEmpty { save(t) } else { similar = s }
            } catch { busy = false; self.error = Repo.map(error).userMessage }
        }
    }

    private func remove() {
        guard let t = txn else { return }
        busy = true
        Task { @MainActor in
            do { try await ctx.repo.deleteTransaction(t.id, version: t.version); ctx.app.toast = "消しました"; ctx.refresh += 1; dismiss() }
            catch { self.error = Repo.map(error).userMessage }
            busy = false
        }
    }
}
