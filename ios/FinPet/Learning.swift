import SwiftUI

struct Lesson: Identifiable {
    let id: String
    let title: String
    let briefing: [String]
    let questions: [Question]
}

struct Question {
    let prompt: String
    let choices: [String]
    let correct: Int
    let feedback: String

    init(_ prompt: String, _ choices: [String], _ correct: Int, _ feedback: String) {
        self.prompt = prompt
        self.choices = choices
        self.correct = correct
        self.feedback = feedback
    }
}

enum LessonLibrary {
    static let daily = units.flatMap(\.lessons)
    static let units = [
        LearningUnit(title: "Investing basics", lessons: [investments, fundFees, portfolio] + PracticeWorkshop.investing.map(\.lesson)),
        LearningUnit(title: "Tax-Free Savings Accounts", lessons: [tfsa, tfsaRoom, tfsaTiming] + PracticeWorkshop.tfsa.map(\.lesson)),
        LearningUnit(title: "Registered Retirement Savings Plans", lessons: [rrsp, rrspWithdrawals, rrspCompare] + PracticeWorkshop.rrsp.map(\.lesson)),
        LearningUnit(title: "First Home Savings Accounts", lessons: [fhsa, fhsaWithdrawals, fhsaPlan] + PracticeWorkshop.fhsa.map(\.lesson)),
        LearningUnit(title: "Credit and borrowing", lessons: [credit, cardPayment, loans] + PracticeWorkshop.credit.map(\.lesson)),
        LearningUnit(title: "Long-term planning", lessons: [compounding, retirement, retirementGap] + PracticeWorkshop.planning.map(\.lesson))
    ]

    static let tfsa = Lesson(id: "tfsa", title: "TFSA basics", briefing: [
        "A Tax-Free Savings Account is a Canadian registered account. It can hold eligible investments, including cash, GICs, and some stocks or funds.",
        "You generally pay no Canadian tax on investment growth or withdrawals in a TFSA. Contributions use contribution room and are not tax-deductible.",
        "The amount you withdraw is generally added back to your contribution room on January 1 of the next year."
    ], questions: [
        Question("My $1,000 in a TFSA grew to $1,200. How much Canadian tax do I generally owe on the gain?", ["$0", "$30", "$200"], 0, "Investment growth inside a TFSA is generally tax-free in Canada."),
        Question("What is a TFSA?", ["A stock", "A registered account", "A type of loan"], 1, "The TFSA is the account. Its investments are the things it holds."),
        Question("When does a withdrawal generally create new contribution room?", ["Right away", "Never", "January 1 of the next year"], 2, "The withdrawn amount is added back the following calendar year."),
        Question("Can you generally deduct a TFSA contribution from taxable income?", ["Yes", "No"], 1, "TFSA contributions are not tax-deductible."),
        Question("You withdraw $300 and have no room left this year. What should you check before putting it back?", ["Your available contribution room", "The account’s nickname"], 0, "Replacing a withdrawal in the same year still requires available room.")
    ])

    static let credit = Lesson(id: "credit", title: "Credit card statements", briefing: [
        "A statement shows what you owed at the end of a billing cycle and when payment is due.",
        "The minimum payment is the smallest required payment. A remaining balance may accrue interest. With an applicable purchase grace period, paying the full statement balance by the due date generally avoids purchase interest.",
        "For borrowing decisions, compare the total repayment cost and fees along with the monthly payment."
    ], questions: [
        Question("What does a statement payment due date tell you?", ["When that payment is due", "When the card expires"], 0, "Use the due date to plan when the payment must arrive."),
        Question("Alex owes $500 and pays the $25 minimum. What remains before interest and new charges?", ["$0", "$475", "$525"], 1, "The minimum payment reduces the balance by $25."),
        Question("An eligible purchase has a grace period. Which action generally avoids interest?", ["Pay only the minimum", "Pay after the deadline", "Pay the full statement balance on time"], 2, "The full on-time statement payment generally preserves the purchase grace period."),
        Question("Two loans have the same monthly payment. What else should you compare?", ["Total repayment and fees", "The colour of the card"], 0, "A lower cost can come from fewer payments or smaller fees."),
        Question("You paid part of your statement. What can happen to the remaining balance?", ["It automatically disappears", "It may accrue interest"], 1, "Check the agreement for the interest rate and terms.")
    ])

    static let investments = Lesson(id: "investments", title: "What investments hold", briefing: [
        "A stock represents ownership in a company. A bond represents money lent to an issuer.",
        "ETFs and mutual funds pool investments. A fund may spread your money across many holdings. Check what it holds and what it costs.",
        "Diversification reduces reliance on a single holding, and investments can still lose value."
    ], questions: [
        Question("What does a share of stock represent?", ["Ownership in a company", "A guaranteed interest payment"], 0, "A share represents partial ownership."),
        Question("Which investment represents lending to an issuer?", ["A stock", "A bond"], 1, "A bond is a form of debt issued to raise money."),
        Question("Which investment spreads exposure across multiple companies?", ["A single company’s shares", "A fund that holds many companies"], 1, "Check the fund’s holdings to see how widely it spreads exposure."),
        Question("What can reduce the value you keep from a fund’s returns?", ["Its name", "The fund’s fees"], 1, "Fees reduce the return that stays with the investor."),
        Question("Can a diversified ETF lose value?", ["Yes", "No"], 0, "Diversification spreads exposure, while overall markets can still fall.")
    ])

    static let compounding = Lesson(id: "compounding", title: "Make growth compound", briefing: [
        "Compounding happens when growth stays invested and can earn further growth.",
        "At a hypothetical 10% annual return, $100 becomes $110 after a year and $121 after two years. The second year earns growth on both the original amount and the first year’s growth.",
        "Actual returns can vary or be negative. Fees and inflation can change what you keep and what it buys."
    ], questions: [
        Question("At a hypothetical 10% return, what does $100 become after one year?", ["$110", "$120", "$90"], 0, "Ten percent of $100 is $10, giving $110."),
        Question("At the same hypothetical rate, what does $110 become in the next year?", ["$120", "$121", "$111"], 1, "Ten percent of $110 is $11, giving $121."),
        Question("What made the second year’s gain $11 instead of $10?", ["A guaranteed bonus", "A larger starting balance"], 1, "The first year’s growth stayed invested."),
        Question("What effect can fees have over time?", ["They leave less invested to compound", "They guarantee gains"], 0, "Fees reduce the balance that can earn future growth."),
        Question("Does a 10% example promise that you’ll earn 10%?", ["Yes", "No"], 1, "It illustrates the math. Real returns vary.")
    ])

    static let retirement = Lesson(id: "retirement", title: "Plan for an earlier retirement", briefing: [
        "A retirement plan compares the spending you expect with the income and savings you can draw on.",
        "Retiring earlier usually gives savings fewer years to build and more years to cover. Some income sources may start later than your chosen retirement date.",
        "Try multiple scenarios so you can see what changes if costs rise or returns are lower."
    ], questions: [
        Question("How many extra years does retiring at 55 add compared with 65?", ["Five", "Ten", "Twenty"], 1, "Moving the date forward ten years adds ten years to cover, all else equal."),
        Question("Retirement starts at 55 and a fictional pension begins at 65. What would you plan for?", ["Funding that ten-year gap", "Receiving the pension immediately"], 0, "Identify which income sources are available in each year."),
        Question("What does a lower assumed investment return do to projected savings, all else equal?", ["Raises the projection", "Lowers the projection"], 1, "Less growth means a lower projected balance."),
        Question("Why include rising prices in a plan?", ["Future money may buy less", "Prices always fall"], 0, "Inflation can increase the amount needed to cover the same expenses."),
        Question("What best tests whether a plan holds up?", ["One optimistic forecast", "Several spending and return scenarios"], 1, "Comparing scenarios shows which assumptions matter most.")
    ])
}

struct Quiz: View {
    let pet: Pet
    let lesson: Lesson
    let completed: (Int, [Int]) -> Void
    var reviewQuestions: [Int] = []
    let close: () -> Void
    @State private var showingBriefing: Bool?
    @State private var started = false
    @State private var missed: [Int] = []
    @State private var index = 0
    @State private var selected: Int?
    @State private var checked = false
    @State private var score = 0
    @State private var finished = false

    private var isReview: Bool { !reviewQuestions.isEmpty }
    private var briefing: Bool { showingBriefing ?? !isReview }
    private var questionOrder: [Int] { isReview ? reviewQuestions : Array(lesson.questions.indices) }
    private var question: Question { lesson.questions[questionOrder[index]] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Close lesson")
                    if !briefing && !finished {
                        Meter(progress: Double(index + 1) / Double(questionOrder.count), background: line)
                        Text("\(index + 1)/\(questionOrder.count)").font(.subheadline.bold())
                    } else {
                        Spacer()
                    }
                    pet.frame(width: 49)
                }.foregroundStyle(muted)
                if (started || isReview) && !finished { lessonTabs }
                if briefing {
                    briefingContent
                } else if finished {
                    Text(isReview ? "Review complete" : "Challenge complete").font(.largeTitle.bold())
                    pet.frame(width: 120)
                    Text("\(score) of \(questionOrder.count) correct").font(.headline)
                } else {
                    questionContent
                }
            }.padding(20)
        }
        .id(briefing ? -1 : (finished ? questionOrder.count : index))
        .foregroundStyle(ink).background(cream.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            ActionButton(title: buttonTitle, secondary: !briefing && selected == nil && !finished, action: advance)
                .disabled(!briefing && selected == nil && !finished)
                .padding(.horizontal, 20).padding(.vertical, 8).background(cream)
        }
    }

    private var lessonTabs: some View {
        HStack(spacing: 6) {
            lessonTab("Briefing", isSelected: briefing) { showingBriefing = true }
            lessonTab("Questions", isSelected: !briefing) { showingBriefing = false }
        }.padding(4).background(mint, in: RoundedRectangle(cornerRadius: 14))
    }

    private func lessonTab(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(isSelected ? .white : .clear, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(isSelected ? forest : muted)
        }.buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var briefingContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Briefing").font(.subheadline.bold()).foregroundStyle(forest)
            Text(lesson.title).font(.system(.largeTitle, design: .serif, weight: .semibold))
            Text(lesson.quickTake).font(.title3.weight(.medium))
            exampleCard
            DisclosureGroup("Explanation and key terms") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(lesson.beginnerGuide.situation)
                    ForEach(lesson.plainLanguageSteps, id: \.self) { Text($0) }
                    if !lesson.relevantWords.isEmpty {
                        Divider()
                        ForEach(lesson.relevantWords) { word in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(word.id).font(.subheadline.bold())
                                Text(word.meaning).font(.subheadline).foregroundStyle(muted)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }.font(.subheadline).tint(forest)
            if let chart = lesson.chart {
                DisclosureGroup("See the numbers as a chart") { exampleChart(chart).padding(.top, 8) }
                    .font(.subheadline).tint(forest)
            }
        }
    }

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(lesson.title).font(.subheadline.bold()).foregroundStyle(muted)
            Text(question.prompt).font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading).petCard()
            ForEach(question.choices.indices, id: \.self) { option in
                Button { selected = option } label: {
                    HStack {
                        Image(systemName: answerIcon(option)).foregroundStyle(answerColor(option))
                        Text(question.choices[option]).font(.headline)
                        Spacer()
                        if checked && option == question.correct {
                            Text("Correct").font(.caption.bold()).foregroundStyle(forest)
                        } else if checked && selected == option {
                            Text("Your answer").font(.caption.bold()).foregroundStyle(.red)
                        }
                    }.petCard(answerBackground(option), radius: 16)
                }.buttonStyle(.plain).disabled(checked)
            }
            if checked {
                VStack(alignment: .leading, spacing: 5) {
                    Text(selected == question.correct ? "Correct!" : "Incorrect").font(.headline)
                    if selected != question.correct {
                        Text("Correct answer: " + question.choices[question.correct]).font(.subheadline.bold())
                    }
                    Text(question.feedback).font(.subheadline)
                }.frame(maxWidth: .infinity, alignment: .leading).petCard(mint)
            }
        }
    }

    private var exampleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lesson.example.title).font(.headline).foregroundStyle(forest)
            ForEach(Array(lesson.example.rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider() }
                HStack(alignment: .top, spacing: 10) {
                    Text(row.label)
                    Spacer(minLength: 8)
                    Text(row.value).bold().multilineTextAlignment(.trailing)
                }.font(.subheadline)
            }
            Text(lesson.example.note).font(.footnote).foregroundStyle(muted)
        }.frame(maxWidth: .infinity, alignment: .leading).petCard(mint)
        .accessibilityElement(children: .contain)
    }

    private func exampleChart(_ chart: LessonChart) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(chart.title).font(.headline)
            ForEach(Array(chart.bars.enumerated()), id: \.offset) { _, bar in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(bar.label)
                        Spacer()
                        Text(bar.value, format: .currency(code: "CAD").precision(.fractionLength(0))).bold()
                    }.font(.footnote)
                    Meter(progress: bar.value / chart.maximum, background: mint)
                        .accessibilityHidden(true)
                }.accessibilityElement(children: .combine)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).petCard()
    }

    private func answerIcon(_ option: Int) -> String {
        if checked && option == question.correct { return "checkmark.circle.fill" }
        if checked && selected == option { return "xmark.circle.fill" }
        return selected == option ? "largecircle.fill.circle" : "circle"
    }

    private func answerColor(_ option: Int) -> Color {
        checked && selected == option && option != question.correct ? .red : forest
    }

    private func answerBackground(_ option: Int) -> Color {
        if checked && option == question.correct { return mint }
        if checked && selected == option { return .red.opacity(0.10) }
        return selected == option ? mint : .white
    }

    private var buttonTitle: String {
        if briefing { return started || isReview ? "Back to questions" : "Start questions" }
        if finished { return "Done" }
        if !checked { return "Check" }
        return index == questionOrder.count - 1 ? "See result" : "Continue"
    }

    private func advance() {
        if briefing { started = true; showingBriefing = false; return }
        if finished { close(); return }
        guard let selected else { return }
        if !checked {
            checked = true
            if selected == question.correct { score += 1 }
            else { missed.append(questionOrder[index]) }
        } else if index == questionOrder.count - 1 {
            finished = true
            completed(score, missed)
        } else {
            index += 1
            self.selected = nil
            checked = false
        }
    }
}
