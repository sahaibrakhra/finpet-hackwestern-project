import SwiftUI
import Pow

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
        LearningUnit(title: "Investing basics", lessons: [stockOwnership, bondLending, investments, fundFees, portfolio] +
                     PracticeWorkshop.investing.filter { !["invest-risk-cash", "invest-fees-after"].contains($0.id) }.map(\.lesson)),
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

    static let stockOwnership = Lesson(id: "stock-ownership", title: "Own a piece of a company", briefing: [
        "Mina pays $20 for one share of a bakery. A share is a small piece of ownership in a company.",
        "The bakery pays Mina $1 while Mina owns the share. That $1 is a dividend, a payment the bakery can choose to make to its owners. Later, a different investor buys Mina’s share for $23. The $23 comes from that buyer. The $1 came from the bakery.",
        "Mina got $24 back altogether, but spent $20 to buy the share. The gain is $24 minus $20, or $4 before fees and taxes. If the next buyer offers only $15 and the bakery pays no dividend, selling gives Mina a $5 loss."
    ], questions: [
        Question("You buy one share in a bakery. What did you buy?", ["A small piece of ownership", "A loan the bakery must repay", "A promise of free bread"], 0, "A share makes you a part-owner of the business."),
        Question("The bakery pays Mina $1, and another investor pays Mina $23 for the share. Which payment is the dividend?", ["The $23 from the investor", "The $1 from the bakery"], 1, "The company pays the dividend. The other investor pays the sale price."),
        Question("You buy a share for $20, receive $1, and sell for $23. What did you gain before fees and taxes?", ["$3", "$4", "$24"], 1, "You made $3 when you sold it and received $1 while you owned it."),
        Question("True or false? Owning a share guarantees you’ll receive a dividend.", ["True", "False"], 1, "Companies can pay, change, or skip dividends."),
        Question("If you paid $20 and sell for $15 without receiving cash along the way, what happens?", ["You lose $5", "You still gain $5", "The company must pay the price back"], 0, "The sale returns $5 less than you paid.")
    ])

    static let bondLending = Lesson(id: "bond-lending", title: "Lend money by buying a bond", briefing: [
        "A city needs money for a bridge. Leo buys a $100 bond from the city. Leo is lending $100 to the city, which promises $4 in interest plus the $100 back in a year.",
        "The date when the city is scheduled to repay the $100 is called maturity. If Leo keeps the bond until then and the city pays as promised, Leo receives $104. The extra $4 is the gain. The other $100 is Leo’s original money coming back.",
        "If Leo needs cash sooner, Leo can try to sell the bond. The next buyer gets the city’s promised payments. If similar new bonds pay more interest, the buyer may offer less than $100 for Leo’s bond. In that case, Leo’s sale price is the buyer’s offer, not the $100 the city promises to repay at maturity."
    ], questions: [
        Question("You buy a bond from a city that is building a bridge. What are you doing?", ["Buying part of the city", "Lending money to the city"], 1, "A bond is a loan to the borrower."),
        Question("The city borrows $100 and promises $4 of interest. If both are paid, how much do you receive altogether?", ["$4", "$100", "$104"], 2, "You receive your $100 back plus $4 of interest."),
        Question("The bond reaches maturity. What does that mean?", ["The scheduled repayment date arrived", "You become a part-owner"], 0, "Maturity is the scheduled date for paying back the original amount."),
        Question("True or false? The borrower might fail to make a promised payment.", ["True", "False"], 0, "A promise to pay can be broken if the borrower cannot pay."),
        Question("Similar new bonds pay more interest. Why might a buyer offer less than $100 for Leo’s bond?", ["Leo’s bond still promises less interest than the new bonds", "The city must raise the interest on Leo’s bond"], 0, "A buyer comparing the old and new bonds may want a lower purchase price to make up for the lower payments.")
    ])

    static let investments = Lesson(id: "investments", title: "Buy a basket of investments", briefing: [
        "Asha has $100 to invest. Asha could buy shares in one bakery or buy part of a fund that owns shares in a bakery, a grocer, and other companies. A fund combines money from many investors to buy those shares.",
        "Compare the same bakery loss. If Asha puts $100 directly into bakery shares and the shares fall 20%, Asha loses $20. If Asha puts $100 into a fund and only $10 of that investment is tied to the bakery, the bakery’s 20% drop costs $2, assuming the other companies stay flat.",
        "That spreading is called diversification. It softens the impact of one company falling, but the fund can still lose money if many companies fall. An exchange-traded fund (ETF) is a fund that you can buy or sell on a stock exchange, a marketplace for investments."
    ], questions: [
        Question("What do you buy when you buy part of a fund?", ["One company chosen at random", "A share in a basket of investments"], 1, "The fund owns the basket. You own a part of the fund."),
        Question("Asha has $10 tied to the bakery through the fund. Bakery shares fall 20% and everything else stays flat. How much does Asha lose?", ["$20", "$2", "$10"], 1, "The 20% drop applies only to the $10 tied to the bakery. Twenty percent of $10 is $2."),
        Question("You own one bakery stock and it falls. Why might a broad basket fall less?", ["The bakery is only one piece of the basket", "Funds can’t lose money"], 0, "The other holdings can do differently from the bakery."),
        Question("True or false? A fund can lose value even if it holds many companies.", ["True", "False"], 0, "A drop can affect many companies at once."),
        Question("Two funds have different names. How can you tell if they mostly own the same things?", ["Compare what they hold", "Compare the logos"], 0, "The list of investments shows whether the baskets overlap.")
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
    @Environment(\.mascotPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var celebrate = false

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
                    if !finished { pet.frame(width: 49) }
                }.foregroundStyle(muted)
                if (started || isReview) && !finished { lessonTabs }
                if briefing {
                    briefingContent
                } else if finished {
                    resultContent
                } else {
                    questionContent
                }
            }.padding(20)
        }
        .id(briefing ? -1 : (finished ? questionOrder.count : index))
        .changeEffect(.feedback(hapticNotification: .success), value: score)
        .changeEffect(.feedback(hapticNotification: .warning), value: missed.count)
        .foregroundStyle(ink).background(palette.paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            ActionButton(title: buttonTitle, secondary: !briefing && selected == nil && !finished, action: advance)
                .disabled(!briefing && selected == nil && !finished)
                .padding(.horizontal, 20).padding(.vertical, 8).background(palette.paper)
        }
    }

    private var resultContent: some View {
        VStack(spacing: 10) {
            Text(isReview ? "Review Complete!" : "Lesson Complete!")
                .font(.system(.largeTitle, weight: .black))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            GeometryReader { stage in
                let size = min(stage.size.width, stage.size.height)
                resultPet
                    .frame(width: size, height: size)
                    .changeEffect(.jump(height: 8), value: celebrate, isEnabled: celebrate && !reduceMotion)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .containerRelativeFrame(.vertical) { height, _ in height * 0.60 }

            Text(resultRemark)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("\(score) of \(questionOrder.count) correct")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity)
        .task {
            await Task.yield()
            celebrate = true
        }
    }

    private var resultRemark: String {
        if score == questionOrder.count { return "Flawless. I was ready to explain, but sure, steal my thunder." }
        if score * 2 >= questionOrder.count { return "A few plot twists, but you stuck the landing." }
        return "Well, that was a plot twist. We’ll get them in review."
    }

    /// Under 50% correct: sad (loops). 50% or more: dance (plays once, holds the last frame).
    private var resultPet: some View {
        var shown = pet
        shown.mood = Double(score) / Double(max(questionOrder.count, 1)) < 0.5 ? .cry : .dance
        return shown
    }

    private var lessonTabs: some View {
        HStack(spacing: 6) {
            lessonTab("Briefing", isSelected: briefing) { showingBriefing = true }
            lessonTab("Questions", isSelected: !briefing) { showingBriefing = false }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
    }

    private func lessonTab(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 9)
                .foregroundStyle(isSelected ? palette.accent : muted)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(isSelected ? palette.accent : .clear).frame(height: 2)
                }
        }.buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var briefingContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(lesson.title).font(.system(.largeTitle, design: .serif, weight: .semibold))
            let steps = lesson.plainLanguageSteps
            if let walkthrough = LessonWalkthrough.byLesson[lesson.id] {
                LessonWalkthroughView(walkthrough: walkthrough)
            } else {
                if let setup = steps.first { Text(setup).font(.body) }
                exampleCard
            }

            DisclosureGroup("Read the full explanation") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        Text(step).font(.body).lineSpacing(2)
                    }
                    if LessonWalkthrough.byLesson[lesson.id] != nil { exampleCard }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }.font(.subheadline).tint(forest)

            let glossary = lesson.abbreviations + lesson.relevantWords
            if !glossary.isEmpty {
                DisclosureGroup("Look up a word") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(glossary) { word in
                            (Text(word.id + "  ").bold() + Text(word.meaning))
                                .font(.subheadline)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }.font(.subheadline).tint(forest)
            }
            if let chart = lesson.chart {
                DisclosureGroup("See the numbers as a chart") { exampleChart(chart).padding(.top, 8) }
                    .font(.subheadline).tint(forest)
            }
        }
    }

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(lesson.title).font(.subheadline.bold()).foregroundStyle(muted)
            Text(question.prompt).font(.system(.title2, design: .serif, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
            ForEach(question.choices.indices, id: \.self) { option in
                Button { selected = option } label: {
                    HStack(spacing: 12) {
                        Image(systemName: answerIcon(option)).foregroundStyle(answerColor(option))
                            .frame(width: 23)
                        Text(question.choices[option]).font(.body.weight(.medium))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 5)
                        if checked && option == question.correct {
                            Text("Correct").font(.caption.bold()).foregroundStyle(forest)
                        } else if checked && selected == option {
                            Text("Your answer").font(.caption.bold()).foregroundStyle(.red)
                        }
                    }
                    .frame(minHeight: 49)
                    .padding(.horizontal, 12)
                    .background(answerBackground(option), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .bottomLeading) { Rectangle().fill(palette.rule).frame(height: 1) }
                    .contentShape(Rectangle())
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
            Text(lesson.example.title).font(.headline).foregroundStyle(palette.accent)
            ForEach(Array(lesson.example.rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider() }
                HStack(alignment: .top, spacing: 10) {
                    Text(row.label)
                    Spacer(minLength: 8)
                    Text(row.value).bold().multilineTextAlignment(.trailing)
                }.font(.subheadline)
            }
            Text(lesson.example.note).font(.footnote).foregroundStyle(muted)
        }.frame(maxWidth: .infinity, alignment: .leading).petCard(palette.panel, radius: 12)
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
        return selected == option ? palette.panel : .clear
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
