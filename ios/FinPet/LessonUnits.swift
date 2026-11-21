import Foundation

struct LearningUnit {
    let title: String
    let lessons: [Lesson]
}

struct LessonExample {
    let title: String
    let rows: [(label: String, value: String)]
    let note: String

    init(_ title: String, _ rows: [(String, String)], _ note: String) {
        self.title = title
        self.rows = rows
        self.note = note
    }
}

extension Lesson {
    var source: URL? {
        let path: String
        switch id {
        case "tfsa":
            path = "revenue-agency/services/tax/individuals/topics/tax-free-savings-account/what.html"
        case "tfsa-room":
            path = "revenue-agency/services/tax/individuals/topics/tax-free-savings-account/contributing/calculate-room.html"
        case "rrsp":
            path = "revenue-agency/services/tax/individuals/topics/rrsps-related-plans/registered-retirement-savings-plan-rrsp.html"
        case "rrsp-withdrawals":
            path = "revenue-agency/services/tax/individuals/topics/rrsps-related-plans/making-withdrawals.html"
        case "fhsa":
            path = "revenue-agency/services/tax/individuals/topics/first-home-savings-account/tax-deductions-fhsa-contributions.html"
        case "fhsa-withdrawals":
            path = "revenue-agency/services/tax/individuals/topics/first-home-savings-account/withdrawals-transfers-out-your-fhsas.html"
        case "investments", "fund-fees":
            path = "financial-consumer-agency/services/savings-investments/investing-basics.html"
        default:
            path = "financial-consumer-agency/services/financial-basics.html"
        }
        return URL(string: "https://www.canada.ca/en/" + path)
    }

    var example: LessonExample {
        switch id {
        case "tfsa":
            LessonExample("Example TFSA account", [("Starting value", "$1,000"), ("Current value", "$1,200"),
                ("Growth inside the account", "$200"), ("Canadian tax on growth", "Generally $0")],
                "Growth and contribution room are separate. The $200 gain did not count as a contribution.")
        case "tfsa-room":
            LessonExample("Contribution room worksheet", [("Room before deposits", "$2,000"),
                ("Deposit at Bank A", "−$600"), ("Deposit at Bank B", "−$400"), ("Remaining room", "$1,000")],
                "Both accounts share the same contribution room.")
        case "rrsp":
            LessonExample("Illustrative RRSP deduction", [("Income before deduction", "$50,000"),
                ("Eligible deduction claimed", "−$2,000"), ("Income after this deduction", "$48,000")],
                "This shows the effect of one deduction. Your final tax bill depends on your full return.")
        case "rrsp-withdrawals":
            LessonExample("Example withdrawal receipt", [("Gross withdrawal", "$1,000"), ("Illustrative withholding", "−$100"),
                ("Cash received", "$900")], "The withholding is a prepayment. The gross withdrawal is generally reported as income.")
        case "credit":
            LessonExample("Sample credit card statement", [("Statement balance", "$500.00"), ("Minimum payment", "$25.00"),
                ("Payment due", "December 14"), ("Balance after minimum payment", "$475.00")],
                "The remaining balance is shown before interest or any new purchases.")
        case "loans":
            LessonExample("Two example $1,000 loans", [("Loan A", "10 × $110 = $1,100"),
                ("Loan B", "12 × $100 = $1,200"), ("Extra total paid on Loan B", "$100")],
                "The smaller monthly payment comes with a higher total cost in this example.")
        case "fhsa":
            LessonExample("Example FHSA contribution record", [("Cash contribution", "$2,000"),
                ("Direct RRSP transfer", "$1,000"), ("Potential deduction from these deposits", "$2,000")],
                "A direct RRSP transfer is excluded from the deduction and generally uses available FHSA room.")
        case "fhsa-withdrawals":
            LessonExample("Compare three routes", [("Qualifying first-home withdrawal", "Tax-free"),
                ("Ordinary withdrawal", "Generally taxable"), ("Eligible direct transfer to RRSP", "Generally no immediate tax")],
                "The rules depend on the type of transaction. Check the criteria before taking money out.")
        case "investments":
            LessonExample("What you own", [("Stock", "A share in a company"), ("Bond", "Debt issued by a borrower"),
                ("Broad fund", "A basket of investments")], "The holdings and fees tell you more about a fund than its name.")
        case "fund-fees":
            LessonExample("Same hypothetical $1,000 invested", [("Gross gain at 5%", "$50"),
                ("Illustrative fee at 1%", "$10"), ("Illustrative fee at 0.2%", "$2")],
                "This simplified example applies fees to the starting balance. Real funds calculate and charge fees differently.")
        case "compounding":
            LessonExample("Hypothetical growth at 10%", [("Start", "$100"), ("After year one", "$110"),
                ("After year two", "$121")], "In year two, the $10 earned in year one also grows.")
        default:
            LessonExample("Early retirement timeline", [("Target retirement", "Age 55"), ("Example pension starts", "Age 65"),
                ("Years to bridge", "10")], "A plan needs to account for which income sources are available during the gap.")
        }
    }
}

extension LessonLibrary {
    static let tfsaRoom = Lesson(id: "tfsa-room", title: "Track your contribution room", briefing: [
        "Contribution room is the amount you can contribute across all of your TFSAs. Each deposit uses some of that room right away.",
        "Unused room can carry forward. Withdrawals are generally added back the following calendar year.",
        "Use your own transaction records to check room. The CRA’s displayed amount can lag recent transactions."
    ], questions: [
        Question("You have $2,000 of room and deposit $600. What remains?", ["$1,400", "$2,000", "$2,600"], 0, "Subtract the deposit from your available contribution room."),
        Question("You deposit another $400 at a different bank. What remains?", ["$1,400", "$1,000", "$600"], 1, "Contribution room is shared across both accounts."),
        Question("Can unused TFSA room carry forward?", ["Yes", "No"], 0, "Unused room can carry into a later year."),
        Question("You just made a deposit and the online figure hasn’t changed. What should you check?", ["Your records of contributions and withdrawals", "Your debit card’s expiry date"], 0, "Your records help account for transactions the displayed figure may not reflect yet."),
        Question("Does a withdrawal immediately restore room?", ["Yes", "Generally the following calendar year"], 1, "A withdrawal generally creates new room on January 1 of the following year.")
    ])

    static let rrsp = Lesson(id: "rrsp", title: "RRSP basics", briefing: [
        "An RRSP is a Canadian registered retirement savings plan. It may hold eligible investments such as cash, GICs, stocks, or funds.",
        "Eligible contributions you claim as deductions can reduce taxable income. Check the RRSP information on your latest CRA notice of assessment before contributing.",
        "Growth generally isn’t taxed while it stays inside the RRSP. Ordinary withdrawals are generally taxable."
    ], questions: [
        Question("What is an RRSP?", ["A registered retirement savings plan", "A type of company share"], 0, "The plan can hold eligible investments."),
        Question("You earn $50,000 and claim an eligible $2,000 deduction. What is income after that deduction alone?", ["$48,000", "$50,000", "$52,000"], 0, "The example subtracts the deduction from income."),
        Question("Where can you check your CRA RRSP information?", ["Your latest notice of assessment", "A credit card receipt"], 0, "The notice provides details relevant to your available room and deduction."),
        Question("When is investment growth generally taxed?", ["Each year while it stays in the plan", "When funds are withdrawn"], 1, "An RRSP generally defers tax while the money remains in the plan."),
        Question("Does a $2,000 deduction necessarily put $2,000 in your pocket?", ["Yes", "No, it generally reduces taxable income"], 1, "Tax savings depend on your tax situation.")
    ])

    static let rrspWithdrawals = Lesson(id: "rrsp-withdrawals", title: "Read an RRSP withdrawal", briefing: [
        "An ordinary RRSP withdrawal is generally included in taxable income. The financial institution usually withholds some tax before paying you.",
        "The gross withdrawal is the amount taken out. The net payment is what reaches you after withholding.",
        "Withholding is a prepayment. The final tax result is calculated on the tax return."
    ], questions: [
        Question("You take out $1,000 and $100 is withheld. What reaches you?", ["$900", "$1,000", "$1,100"], 0, "The net payment is the gross withdrawal minus withholding."),
        Question("Which amount is generally included in income in this example?", ["$900", "$1,000"], 1, "The gross withdrawal is generally reported."),
        Question("What is withholding?", ["A prepayment toward tax", "The final calculation of all tax owed"], 0, "Your full return determines the final result."),
        Question("Who usually withholds tax on an ordinary withdrawal?", ["The financial institution", "Your employer"], 0, "The institution generally withholds tax when it pays you."),
        Question("Could your final tax on this withdrawal differ from the amount withheld?", ["Yes", "No"], 0, "Other income and details on the return can affect the result.")
    ])

    static let loans = Lesson(id: "loans", title: "Compare two loans", briefing: [
        "The principal is the amount borrowed. Total repayment includes the principal plus interest and any fees you pay.",
        "For fixed equal payments, multiply the payment by the number of payments, then include any fees paid separately.",
        "Look at both affordability and total repayment. A smaller monthly payment can come from a longer repayment term."
    ], questions: [
        Question("What is the principal on a $1,000 loan?", ["$1,000", "The monthly payment"], 0, "Principal is the amount borrowed."),
        Question("What do ten payments of $110 total?", ["$1,000", "$1,100", "$1,200"], 1, "Ten times $110 is $1,100."),
        Question("What do twelve payments of $100 total?", ["$1,100", "$1,200", "$1,000"], 1, "Twelve times $100 is $1,200."),
        Question("Which example has the smaller payment but greater total cost?", ["Loan A", "Loan B"], 1, "The extra two payments make Loan B cost more overall."),
        Question("If a $30 fee is paid separately, does it count toward the total?", ["Yes", "No"], 0, "Include fees paid separately when comparing total cost.")
    ])

    static let fundFees = Lesson(id: "fund-fees", title: "Compare fund fees", briefing: [
        "ETFs and mutual funds pool money to hold investments. Funds can hold different assets or follow different strategies.",
        "Ongoing fees reduce the amount you keep. Compare fees alongside holdings and risk, and check for trading charges.",
        "To estimate a fee in this simplified example, multiply the starting investment amount by the fee percentage."
    ], questions: [
        Question("What is 1% of $1,000?", ["$1", "$10", "$100"], 1, "Multiply $1,000 by 0.01."),
        Question("What is 0.2% of $1,000?", ["$2", "$20"], 0, "Multiply $1,000 by 0.002."),
        Question("With $50 of gross gain and a $10 illustrative fee, what remains?", ["$40", "$50", "$60"], 0, "The fee reduces the gain by $10."),
        Question("Can two funds have different holdings even if they charge the same fee?", ["Yes", "No"], 0, "Funds can follow different strategies at the same fee level."),
        Question("What should you compare besides fees?", ["Holdings and risk", "Just the fund’s name"], 0, "Holdings and risk describe what you’re investing in.")
    ])
}

struct LessonChart {
    let title: String
    let bars: [(label: String, value: Double)]
    var maximum: Double { bars.map(\.value).max() ?? 1 }
}

extension Lesson {
    var chart: LessonChart? {
        switch id {
        case "tfsa-room":
            LessonChart(title: "Watch the room shrink", bars: [("Starting room", 2000), ("After Bank A", 1400), ("After Bank B", 1000)])
        case "credit":
            LessonChart(title: "After the minimum payment", bars: [("Statement balance", 500), ("Paid", 25), ("Still owed", 475)])
        case "loans":
            LessonChart(title: "Total repayment", bars: [("Loan A", 1100), ("Loan B", 1200)])
        case "fund-fees":
            LessonChart(title: "Illustrative annual fees", bars: [("1% example", 10), ("0.2% example", 2)])
        case "compounding":
            LessonChart(title: "Growth over two years", bars: [("Start", 100), ("Year 1", 110), ("Year 2", 121)])
        default:
            nil
        }
    }
}

extension LessonLibrary {
    static let fhsa = Lesson(id: "fhsa", title: "FHSA basics", briefing: [
        "The First Home Savings Account is a Canadian registered account for eligible first-time home buyers. A cash contribution is generally deductible within the applicable rules.",
        "A direct transfer from an RRSP generally uses FHSA participation room, but it does not create a new deduction.",
        "Opening an account and making a qualifying withdrawal have separate eligibility requirements. Check the CRA’s current rules for each step."
    ], questions: [
        Question("What is an FHSA designed to help with?", ["Saving for an eligible first home", "Paying a credit card bill"], 0, "The FHSA is designed for eligible first-time home buyers."),
        Question("What can an eligible cash contribution generally do?", ["Create a tax deduction", "Guarantee investment returns"], 0, "Eligible cash contributions are generally deductible."),
        Question("Does a direct RRSP transfer create a new FHSA deduction?", ["Yes", "No"], 1, "A direct RRSP transfer is not deductible as an FHSA contribution."),
        Question("In the example, $2,000 is contributed in cash and $1,000 is transferred directly from an RRSP. How much could be deductible?", ["$3,000", "$2,000", "$1,000"], 1, "Only the eligible cash contribution is potentially deductible in the example."),
        Question("Are the opening and qualifying-withdrawal criteria identical?", ["Yes", "Check each set of criteria separately"], 1, "The CRA distinguishes between opening and taking a qualifying withdrawal.")
    ])

    static let fhsaWithdrawals = Lesson(id: "fhsa-withdrawals", title: "Choose a withdrawal route", briefing: [
        "A qualifying FHSA withdrawal for an eligible home purchase is tax-free when the CRA’s conditions are met.",
        "An ordinary withdrawal that does not qualify is generally taxable. Label and record the transaction accurately.",
        "An eligible direct transfer to your RRSP or RRIF can generally be made without immediate tax. Ask the institutions to handle the transfer and verify that the conditions apply."
    ], questions: [
        Question("If all qualifying-withdrawal conditions are met, how is the withdrawal treated?", ["Tax-free", "Always taxable"], 0, "A qualifying withdrawal is tax-free."),
        Question("How is an ordinary withdrawal generally treated?", ["It is generally taxable", "It is automatically tax-free"], 0, "The qualifying-withdrawal treatment depends on meeting the conditions."),
        Question("What is a potential route if you decide not to buy a home?", ["An eligible direct transfer to an RRSP or RRIF", "Treat all withdrawals as qualifying"], 0, "A direct transfer may be available under the applicable rules."),
        Question("What should you check before a qualifying home withdrawal?", ["The CRA’s current qualifying conditions", "Just the balance on your statement"], 0, "The conditions determine whether the withdrawal qualifies."),
        Question("Who can help carry out a direct transfer?", ["The account institutions", "A store that accepts your debit card"], 0, "The institutions process and record the direct transfer.")
    ])
}
