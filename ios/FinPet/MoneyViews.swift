import SwiftUI
import Charts

struct MoneyView: View {
    @Binding var profile: Profile
    @State private var income = ""
    @State private var fixed = ""
    @State private var goal = ""
    @State private var title = ""
    @State private var amount = ""
    @State private var region = ""
    @State private var category: Category = .wants
    @State private var status = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Optional budget") {
                    field("Monthly take-home income", text: $income)
                    field("Monthly fixed expenses", text: $fixed)
                    field("Emergency fund goal", text: $goal)
                    Button("Save plan", action: savePlan)
                    if let weekly = profile.weeklyBudget {
                        LabeledContent("Weekly wants budget", value: money(weekly))
                        LabeledContent("Remaining this week", value: money(weekly - profile.weeklySpending))
                    }
                    if let essentials = profile.fixed, essentials > 0 {
                        Text("Example buffer covering three months of entered expenses: \(money(essentials * 3)).")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Log a transaction") {
                    TextField("What was it for?", text: $title)
                    field("Amount in CAD", text: $amount)
                    Picker("Category", selection: $category) {
                        ForEach(Category.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    TextField("City or province (optional)", text: $region)
                    Button("Add transaction", action: logEntry)
                    Button("Add demo transaction") {
                        profile.add(Entry(title: "Demo groceries", amount: 37.40, category: .needs, region: "London, ON"))
                        status = "Demo transaction added."
                    }
                    if !status.isEmpty { Text(status).foregroundStyle(.secondary) }
                }
                Section("Recent transactions") {
                    ForEach(profile.entries.reversed()) { entry in
                        LabeledContent(entry.title, value: money(entry.amount))
                    }
                }
            }
            .navigationTitle("Money")
            .onAppear {
                income = profile.income.map { String($0) } ?? ""
                fixed = profile.fixed.map { String($0) } ?? ""
                goal = profile.goal > 0 ? String(profile.goal) : ""
            }
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text).keyboardType(.decimalPad)
    }

    private func value(_ input: String) -> Double? {
        guard let value = Double(input), value.isFinite, (0...1_000_000_000).contains(value) else { return nil }
        return value
    }

    private func savePlan() {
        guard [income, fixed, goal].allSatisfy({ $0.isEmpty || value($0) != nil }) else {
            status = "Enter valid, non-negative amounts."
            return
        }
        profile.income = value(income)
        profile.fixed = value(fixed)
        profile.goal = value(goal) ?? 0
        status = "Plan saved."
    }

    private func logEntry() {
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, let amount = value(amount), amount > 0 else {
            status = "Enter a description and a positive amount."
            return
        }
        profile.add(Entry(title: label, amount: amount, category: category,
                          region: region.trimmingCharacters(in: .whitespacesAndNewlines)))
        title = ""
        self.amount = ""
        status = "Transaction saved."
    }
}

struct TrendsView: View {
    @Binding var profile: Profile
    @State private var region: String?
    @State private var confidence = 3

    private var regions: [String] { Set(profile.entries.map(\.region).filter { !$0.isEmpty }).sorted() }
    private var spending: [Entry] {
        profile.entries.filter { $0.category != .savings && (region == nil || $0.region == region) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Spending by category") {
                    Picker("Region", selection: $region) {
                        Text("All regions").tag(nil as String?)
                        ForEach(regions, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    Chart([Category.needs, .wants], id: \.self) { category in
                        BarMark(x: .value("Category", category.rawValue),
                                y: .value("CAD", spending.filter { $0.category == category }.reduce(0) { $0 + $1.amount }))
                    }
                    .frame(height: 150)
                }
                Section("Same days last month") {
                    ForEach([Category.needs, .wants], id: \.self) { category in
                        LabeledContent(category.rawValue, value: monthChange(category))
                    }
                }
                Section("Financial confidence") {
                    Stepper("How confident do you feel? \(confidence)/5", value: $confidence, in: 1...5)
                    Button("Save confidence check-in") {
                        profile.confidence.append(Confidence(rating: confidence))
                        profile.checkIn()
                    }
                    if !profile.confidence.isEmpty {
                        Chart(profile.confidence) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Confidence", point.rating))
                            PointMark(x: .value("Date", point.date), y: .value("Confidence", point.rating))
                        }
                        .chartYScale(domain: 1...5)
                        .frame(height: 140)
                    }
                    LabeledContent("Lessons practised", value: "\(profile.lessons.count) of \(curriculum.count)")
                }
            }
            .navigationTitle("Trends")
        }
    }

    private func monthChange(_ category: Category) -> String {
        let calendar = Calendar.current
        guard let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start,
              let lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth),
              let lastMonthDays = calendar.range(of: .day, in: .month, for: lastMonth) else { return "—" }
        let comparableDays = min(calendar.component(.day, from: .now), lastMonthDays.count)
        func subtotal(from start: Date) -> Double {
            guard let end = calendar.date(byAdding: .day, value: comparableDays, to: start) else { return 0 }
            return spending.filter { $0.category == category && $0.date >= start && $0.date < end }
                .reduce(0) { $0 + $1.amount }
        }
        let difference = subtotal(from: thisMonth) - subtotal(from: lastMonth)
        return (difference > 0 ? "+" : "") + money(difference)
    }
}
