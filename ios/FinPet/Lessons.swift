import SwiftUI

struct Lesson: Identifiable {
    let id: String
    let title: String
    let scenarios: [Scenario]
}

struct Scenario {
    let question: String
    let answers: [String]
    let correct: Int
    let explanation: String
}

let curriculum = [
    Lesson(id: "buffer", title: "Emergency funds", scenarios: [
        Scenario(question: "Your laptop needs a $180 repair. Your emergency fund has $250. How much would be left if you used it?",
                 answers: ["$70", "$180", "$430"], correct: 0,
                 explanation: "Your buffer would cover the repair and leave $70. Saving $20 weekly would restore it in nine weeks."),
        Scenario(question: "Your $400 buffer paid for a $160 repair. How many $40 weekly contributions rebuild it?",
                 answers: ["Two", "Four", "Ten"], correct: 1,
                 explanation: "Rebuilding requires replacing the $160 you used. At $40 a week it takes four weeks.")
    ]),
    Lesson(id: "budget", title: "Flexible budgets", scenarios: [
        Scenario(question: "You have $80 after essentials. An unexpected $25 transit cost comes up. What amount can you still allocate?",
                 answers: ["$80", "$55"], correct: 1, explanation: "Set aside the $25 transit cost first. You have $55 left to allocate."),
        Scenario(question: "A $120 textbook is due in six weeks. How much would you set aside weekly to cover it?",
                 answers: ["$10", "$20", "$30"], correct: 1, explanation: "Six contributions of $20 cover the $120 bill.")
    ]),
    Lesson(id: "accounts", title: "TFSAs and RRSPs", scenarios: [
        Scenario(question: "You’re comparing a TFSA and an RRSP. Which account generally lets you make tax-free withdrawals?",
                 answers: ["TFSA", "RRSP"], correct: 0, explanation: "TFSA withdrawals are generally tax-free. RRSP withdrawals are generally taxable, while qualifying contributions can be deductible."),
        Scenario(question: "A friend calls a TFSA a type of stock. What is it?",
                 answers: ["A single stock", "A registered account that can hold eligible investments"], correct: 1,
                 explanation: "A TFSA is an account. Its holdings can include eligible investments such as cash, GICs, or stocks.")
    ]),
    Lesson(id: "credit", title: "Credit and borrowing", scenarios: [
        Scenario(question: "Your card statement is $500. It contains only eligible purchases and has a grace period. What typically avoids interest on those purchases?",
                 answers: ["Pay the full statement balance by the due date", "Pay only the minimum"], correct: 0,
                 explanation: "Paying in full by the due date generally preserves the purchase grace period. Check the card agreement for the exact terms."),
        Scenario(question: "Two $1,000 loans have different fees and payment schedules. What should you compare?",
                 answers: ["Monthly payment only", "Total repayment amount and affordability"], correct: 1,
                 explanation: "A lower payment can come with a longer term and higher total cost. Compare fees and total repayment too.")
    ]),
    Lesson(id: "investing", title: "Stocks, bonds, and funds", scenarios: [
        Scenario(question: "In a toy market, stocks fall 20% and bonds and cash stay flat. Which stock/bond/cash mix loses more?",
                 answers: ["20/60/20", "80/15/5"], correct: 1, explanation: "Here, the mixes fall about 4% and 16%, respectively. Real bond prices can also move. These mixes are illustrations."),
        Scenario(question: "Two diversified funds hold similar investments. What can make their results differ over time?",
                 answers: ["Fees", "Whether you name the account"], correct: 0,
                 explanation: "ETFs and mutual funds can both pool investments. Compare holdings, fees, and how the fund trades.")
    ]),
    Lesson(id: "retirement", title: "Retirement and time horizons", scenarios: [
        Scenario(question: "Alex wants to retire at 55 instead of 65. What would make the plan more realistic?",
                 answers: ["Model ten extra years of expenses and when other income starts", "Assume the same timeline"], correct: 0,
                 explanation: "Retiring earlier can mean fewer years to save and more years to cover. Model the gap using several assumptions about returns and expenses."),
        Scenario(question: "Two savers invest the same amounts at the same hypothetical positive return. One starts ten years earlier. What advantage does that create?",
                 answers: ["More time for growth to compound", "A guaranteed return"], correct: 0,
                 explanation: "Growth can itself earn returns over time. Actual investment returns vary.")
    ])
]

struct LessonsView: View {
    @Binding var profile: Profile
    @State private var request = ""
    @State private var savedRequest = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily practice") {
                    ForEach(curriculum) { lesson in
                        NavigationLink {
                            PracticeView(profile: $profile, lesson: lesson)
                        } label: {
                            LabeledContent(lesson.title, value: schedule(lesson))
                        }
                    }
                }
                Section("What do you want to learn?") {
                    TextField("Suggest a topic", text: $request)
                    Button("Save suggestion") {
                        let topic = request.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !topic.isEmpty else { return }
                        profile.requests.append(topic)
                        request = ""
                        savedRequest = true
                    }
                    if savedRequest { Text("Suggestion saved on this device.").foregroundStyle(.secondary) }
                }
                Section("Learning sources") {
                    Link("FCAC · Financial Basics", destination: URL(string: "https://www.canada.ca/en/financial-consumer-agency/services/financial-basics.html")!)
                }
            }
            .navigationTitle("Learn")
        }
    }

    private func schedule(_ lesson: Lesson) -> String {
        guard let progress = profile.lessons[lesson.id] else { return "New" }
        return progress.due <= .now ? "Review due" : progress.due.formatted(date: .abbreviated, time: .omitted)
    }
}

struct PracticeView: View {
    @Binding var profile: Profile
    let lesson: Lesson
    @State private var choice: Int?
    @State private var exercise: Scenario?

    var body: some View {
        Form {
            if let scenario = exercise {
                Section(profile.name.isEmpty ? "Your mascot asks" : "\(profile.name) asks") {
                    Text(scenario.question)
                    ForEach(scenario.answers.indices, id: \.self) { index in
                        Button(scenario.answers[index]) { answer(index, scenario: scenario) }
                            .disabled(choice != nil)
                    }
                }
                if let choice {
                    Section(choice == scenario.correct ? "You got it" : "Here’s the trade-off") {
                        Text(scenario.explanation)
                        if let record = profile.lessons[lesson.id] {
                            Text("Next review: \(record.due.formatted(date: .abbreviated, time: .omitted))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(lesson.title)
        .onAppear {
            if exercise == nil {
                let level = profile.lessons[lesson.id]?.level ?? 0
                exercise = lesson.scenarios[level % lesson.scenarios.count]
            }
        }
    }

    private func answer(_ index: Int, scenario: Scenario) {
        choice = index
        let previous = profile.lessons[lesson.id]
        guard previous == nil || previous!.due <= .now else { return }
        let correct = index == scenario.correct
        let intervals = [1, 3, 7, 14]
        let level = previous?.level ?? 0
        let days = correct ? intervals[min(level, intervals.count - 1)] : 1
        let due = Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now
        profile.lessons[lesson.id] = ProgressRecord(level: correct ? level + 1 : 0, due: due)
        profile.xp += 10
        profile.treats += 1
        profile.checkIn()
    }
}
