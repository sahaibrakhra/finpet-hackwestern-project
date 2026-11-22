import Foundation

struct EverydayLesson {
    let lesson: Lesson
    let example: LessonExample
    let explanation: [String]
    let action: String

    init(_ id: String, _ title: String, _ setup: String, _ example: LessonExample,
         _ explanation: [String], _ action: String, _ questions: [Question]) {
        self.lesson = Lesson(id: id, title: title, briefing: [setup], questions: questions)
        self.example = example
        self.explanation = explanation
        self.action = action
    }
}

enum EverydayLessons {
    static let saveOrInvest = EverydayLesson(
        "invest-save-first", "Save or invest?", "Start with the date you’ll need the money. Then choose where to keep it.",
        LessonExample("Two goals, different deadlines", [("Textbooks due in two months", "Need ready cash"),
            ("A goal many years away", "May have time to invest")], "One person can save and invest for different goals."),
        ["A savings account keeps money easier to reach. Check access and any limits before counting on the account for a bill.",
         "Investing gives money a chance to grow, but an investment can fall just when you need to sell. A long timeline gives you more flexibility, without guaranteeing a recovery."],
        "Write down one goal and when you need the money. Decide how much of that money needs to stay easy to reach.",
        [
            Question("Your tuition is due in six weeks. What feature matters most for that money?", ["Easy access and a stable balance", "A chance of a larger gain next year"], 0, "The tuition deadline stays fixed even if investments fall."),
            Question("Can saving and investing both make sense for one person?", ["Yes, the goals can have different deadlines", "No, you have to pick one"], 0, "Decide separately for each goal."),
            Question("You planned to invest money for years, but you’ll need it this summer. What should you reconsider?", ["How easy it is to get the cash without selling at a loss", "Only the name of the account"], 0, "A new deadline changes what you can afford to risk."),
            Question("True or false? A long timeline guarantees an investment will recover.", ["True", "False"], 1, "Time offers flexibility. A recovery is never guaranteed."),
            Question("Which comes first when choosing where to put money?", ["Pick whatever went up most last month", "Decide what the money is for and when you need it"], 1, "The goal makes the trade-off meaningful.")
        ])

    static let index = EverydayLesson(
        "invest-index", "What the S&P 500 actually does", "The Standard & Poor’s 500 (S&P 500) is a scoreboard for about 500 large U.S. companies. A fund can try to follow that scoreboard.",
        LessonExample("From scoreboard to investment", [("S&P 500 index", "Measures large U.S. companies"),
            ("An index fund", "Tries to follow that measure"), ("What you can buy", "A unit of the fund")],
            "The index itself is a measurement. You buy an investment that tracks it."),
        ["An S&P 500 fund gives you exposure to many companies in one purchase. That spreads company-specific risk compared with owning only one stock.",
         "The fund still focuses on large U.S. companies. Bigger companies generally have more influence, and the whole U.S. stock market can fall. The fund does not automatically include bonds or the rest of the world."],
        "Before considering an index fund, read what it tracks and ask which markets you would still be missing.",
        [
            Question("A friend says they bought the S&P 500. What did they most likely buy?", ["Units of a fund that tracks the index", "The number shown on the index scoreboard"], 0, "An index is a measurement. A fund is an investment you can actually buy."),
            Question("Why might someone prefer this fund to owning a single company’s shares?", ["One company matters less when they own many", "The fund can never fall"], 0, "The benefit is spreading exposure across companies."),
            Question("You want bonds and non-U.S. stocks too. Does this index provide all of that?", ["Yes, 500 companies means every asset is included", "No, it focuses on large U.S. companies"], 1, "A broad spread within the U.S. is different from a spread across countries and investment types."),
            Question("True or false? Every company in the standard S&P 500 has the same influence.", ["True", "False"], 1, "Larger companies generally have more influence."),
            Question("You need your money for a car deposit in two months. What’s a real concern with this fund?", ["U.S. stocks can drop before the deposit is due", "The index only updates once a decade"], 0, "Owning many companies still leaves you exposed to an overall market drop.")
        ])

    static let holdings = EverydayLesson(
        "invest-holdings", "Read what a fund actually owns", "Holdings are the investments inside a fund. Start with what the fund tracks, then check the country and types of investments it owns.",
        LessonExample("Two fictional fund summaries", [("Fund A tracks", "Large U.S. stocks"),
            ("Fund B tracks", "Large U.S. stocks too"), ("What buying both adds", "Another fund with similar exposure")],
            "Different fund names can hide similar baskets."),
        ["An exchange-traded fund (ETF) is a basket of investments you can buy or sell on an exchange. A Canadian fund summary called ETF Facts shows the fund’s goal, examples of what it holds, and its costs.",
         "Compare the two summaries before buying both. A different ticker, the symbol used to look up a fund, does not necessarily give you different investments. A fund traded in Canadian dollars can still hold U.S. companies."],
        "Open a fund summary and find three lines: what the fund follows, where the investments are, and what it costs.",
        [
            Question("Two funds have different names but follow the same U.S. stock index. What should you expect?", ["Many of the same companies", "Automatically twice as many different companies"], 0, "Different funds can track the same basket."),
            Question("You want to add companies outside the United States. What would help you choose?", ["A different logo", "A summary showing holdings in other countries"], 1, "Look for the exposure you want in the actual holdings."),
            Question("A fund trades in Canadian dollars. What can you conclude about its holdings?", ["They must be Canadian", "Check the summary, because they could still be foreign"], 1, "Trading currency and the country of the holdings are different."),
            Question("Which is the best place to start comparing two funds?", ["The fund objective and holdings in ETF Facts", "Which ticker looks familiar"], 0, "The objective and holdings show what you are buying."),
            Question("True or false? Buying a fund removes the need to check what is inside.", ["True", "False"], 1, "Funds can be narrow or broad. Look at the basket before you buy.")
        ])

    static let accountAndFund = EverydayLesson(
        "invest-account-fund", "Choose an account, then a fund", "Think of the account as the container and the fund as one thing you can put inside it.",
        LessonExample("Two separate decisions", [("Choose the container", "Check the account’s tax and deposit rules"),
            ("Choose what goes in", "Check the investment and its risks"), ("Money waiting in the account", "May still be cash")],
            "Opening or funding an account does not always buy an investment."),
        ["A Tax-Free Savings Account (TFSA) is a Canadian account. Depending on where you open one, the account can hold cash or eligible investments.",
         "Depositing cash and buying a fund are separate actions. At a brokerage, where you can buy and sell investments, check whether the cash is still waiting or the fund purchase has completed."],
        "In an example account, practise finding the available cash and the investments already owned.",
        [
            Question("You moved money into an investing account. What should you check next?", ["Whether the money is still cash or a purchase went through", "Assume a fund was bought automatically"], 0, "A deposit alone can leave the money uninvested."),
            Question("What does TFSA describe?", ["A U.S. stock index", "The Canadian account that can hold investments"], 1, "An account sets tax and deposit rules. It is separate from the investments inside."),
            Question("You own the same fund in a different type of account. Which can change?", ["The tax treatment", "Which companies the fund owns, solely because you moved accounts"], 0, "The account can affect your taxes, while the fund has its own holdings."),
            Question("True or false? A stock fund inside a TFSA can still lose value.", ["True", "False"], 0, "Account tax treatment does not guarantee the investment’s value."),
            Question("Before putting money into a TFSA, what should you check?", ["Which website has the nicest colours", "How much you are allowed to put in"], 1, "The deposit uses contribution room.")
        ])

    static let firstOrder = EverydayLesson(
        "invest-first-order", "Practise your first fund purchase", "Use a fictional order screen to learn the steps before you put in real money.",
        LessonExample("Mock order preview", [("Fund symbol", "DEMO, a fictional symbol"), ("Side", "Buy"),
            ("Quantity", "2 units"), ("Estimated amount", "$80 before fees")],
            "Check the fund name, number of units, and total before confirming."),
        ["A ticker is the short code used to look up a fund. Similar codes can lead to different funds, so confirm the full name and what the fund tracks.",
         "An estimated order total may change. Check fees, currency, and available cash before confirming. After sending an order, check its status before placing another copy."],
        "Walk through a practice order and stop at the preview. Identify the fund, account, quantity, and total.",
        [
            Question("The symbol looks right, but the full fund name does not. What should you do?", ["Pause and verify the fund", "Confirm because the symbols are similar"], 0, "The full name and objective help confirm what you are buying."),
            Question("The order preview says Sell. You intend to invest new cash. What must change?", ["The order side to Buy", "The calendar date"], 0, "Buy adds units to your account. Sell disposes of units."),
            Question("Your order status says Pending. What should you do before sending another?", ["Check the status of the first order", "Always send the same order again"], 0, "A second order can leave you buying twice."),
            Question("A mock preview shows three units at $25 with no fees. What should available cash cover?", ["$25", "$75"], 1, "The purchase is for three units, so multiply by three."),
            Question("Where do you check currency and possible charges?", ["The order preview", "Only the company logo"], 0, "Review the actual cost before confirming.")
        ])

    static let routine = EverydayLesson(
        "invest-routine", "Build a habit you can keep", "Pick a contribution you can repeat, and keep money for near-term bills easy to reach.",
        LessonExample("A simple payday routine", [("First", "Keep money for bills accessible"),
            ("Then", "Set a repeatable amount for a long-term goal"), ("Review", "Adjust the amount if income changes")],
            "A routine can be useful even when the first amount is small."),
        ["A regular contribution is simply money you add on a schedule. It helps with consistency, but it does not promise a gain or a better price on any particular day.",
         "If an automatic transfer goes to a brokerage account, check whether it buys the fund too. Some accounts leave the transfer in cash until you place an order."],
        "Choose a starting amount you could keep up during an ordinary month. Put a reminder in your calendar to revisit it.",
        [
            Question("Your pay drops for a month. What is a reasonable change?", ["Lower or pause the contribution to leave enough for bills", "Borrow money to keep the same contribution"], 0, "A repeatable plan can change when cash needs change."),
            Question("You add $15 a week for four weeks. How much did you contribute, before growth?", ["$45", "$60"], 1, "Four $15 contributions total $60."),
            Question("True or false? A regular deposit guarantees a gain.", ["True", "False"], 1, "A routine controls how regularly you save, not how the market moves."),
            Question("The cash balance grows every payday but no fund units appear. What might be happening?", ["The deposit is working but no purchase is scheduled", "Deposits always buy units invisibly"], 0, "Check the account’s purchase settings."),
            Question("When should the plan be revisited?", ["When your goal, deadline, or income changes", "Every time a stock moves"], 0, "Personal changes matter more to the plan than ordinary market movement.")
        ])

    static let housing = EverydayLesson(
        "plan-housing-costs", "Try the 30% housing check", "Canada uses 30% of household income before tax as a housing affordability benchmark. Treat it as a starting point, then check what you actually have left.",
        LessonExample("A first pass at a rental listing", [("Monthly household income before tax", "$3,000"),
            ("30% benchmark", "$900"), ("Rent plus essential utilities in this example", "$950")],
            "This listing runs $50 above the benchmark. That is a prompt to look closer."),
        ["Start with housing costs such as rent and essential utilities. Compare the total to 30% of before-tax household income.",
         "The money that arrives in your bank after tax is different. Compare the actual housing bill with that take-home amount, then leave room for groceries, transport, and other costs. A percentage alone cannot make that decision."],
        "Pick a fictional rental listing and compare rent plus utilities with both the benchmark and the money left after other essentials.",
        [
            Question("A household earns $4,000 a month before tax. What is 30%?", ["$1,200", "$400", "$1,600"], 0, "Multiply $4,000 by 0.30."),
            Question("Rent is $1,000 and essential utilities are $150. What amount should you use in this check?", ["$1,000", "$1,150"], 1, "Include the housing costs you actually pay."),
            Question("Which income does the Canadian benchmark use?", ["Household income before tax", "Only the amount left after groceries"], 0, "The benchmark uses before-tax income. A personal cash check should use take-home pay."),
            Question("A listing is below the benchmark. What should you still check?", ["What is left after housing and other essentials", "Assume it fits every household"], 0, "People with the same rent can have very different remaining costs."),
            Question("True or false? Going slightly above 30% means a rental is automatically impossible.", ["True", "False"], 1, "The benchmark helps you compare. Your actual cash and obligations matter.")
        ])

    static let annuity = EverydayLesson(
        "plan-annuity", "What an annuity is for", "An annuity is a contract that trades savings you have now for payments you receive over time.",
        LessonExample("A fictional retirement plan", [("Regular income already available", "$1,800 per month"),
            ("Essential monthly expenses", "$2,200"), ("Gap to consider", "$400 per month")],
            "This is a gap to plan for, not an annuity quote."),
        ["A life annuity pays as long as you live under the contract. A term-certain annuity pays for a set time instead. Both can help turn a lump sum into more predictable income.",
         "The trade-off is access: money used to buy an annuity may be difficult or impossible to get back as a lump sum. Check fees, inflation protection, and what happens when the person receiving payments dies."],
        "Separate the expenses you must pay every month from costs that vary. That makes it easier to compare regular income with flexible savings.",
        [
            Question("What is someone buying with an annuity?", ["A contract to receive payments over time", "A new chequing account"], 0, "The contract exchanges money now for a stream of payments."),
            Question("Someone wants payments that last as long as they live. Which type is built for that?", ["A term-certain annuity", "A life annuity"], 1, "A life annuity pays for life under its terms."),
            Question("A person needs easy access to the full lump sum next year. What should they check?", ["Whether the contract allows them to access their money", "Assume they can withdraw it any time"], 0, "The contract may restrict access to the original money."),
            Question("Essentials cost $2,500 and regular income is $2,100 per month. What is the monthly gap?", ["$400", "$600"], 0, "Subtract regular income from expenses."),
            Question("If a monthly payment stays fixed and prices rise, what happens?", ["The same payment may buy less", "It must buy exactly the same amount"], 0, "Unless the payments adjust, rising prices reduce what the money buys.")
        ])

    static let all = [saveOrInvest, index, holdings, accountAndFund, firstOrder, routine, housing, annuity]
    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.lesson.id, $0) })
}

extension LessonLibrary {
    static func adjacent(to id: String) -> (previous: Lesson?, next: Lesson?) {
        for unit in units {
            guard let position = unit.lessons.firstIndex(where: { $0.id == id }) else { continue }
            let prior = position > 0 ? unit.lessons[position - 1] : nil
            let next = position + 1 < unit.lessons.count ? unit.lessons[position + 1] : nil
            return (prior, next)
        }
        return (nil, nil)
    }
}

extension Lesson {
    var extraExplanation: [String] {
        if let everyday = EverydayLessons.byID[id] { return everyday.explanation }
        if let workshop = PracticeWorkshop.byID[id] { return [workshop.rule, workshop.reason] }
        switch id {
        case "stock-ownership":
            return ["Owning a share gives you a tiny piece of the company. It doesn’t mean the company owes you your original money back. A dividend, if there is one, comes from the company. When you sell, the sale money comes from the next buyer."]
        case "bond-lending":
            return ["A bond makes you a lender, while a stock makes you a part-owner. The date the borrower is scheduled to repay the original amount is called maturity. The promise still carries risk if the borrower cannot pay."]
        case "investments":
            return ["Diversification means spreading money across different investments. Ten bakeries in one city still share some of the same risks. An exchange-traded fund (ETF) trades on an exchange, but its name alone doesn’t tell you how broad the basket is."]
        case "fund-fees":
            return ["Fund fees can come out of the investment itself, so you may never see a separate bill. Compare funds that hold similar investments, and check whether reported returns already account for fees."]
        case "tfsa":
            return ["Putting money into a Tax-Free Savings Account doesn’t lower the income used to calculate your tax. Keep track of how much you add across every account you own, especially if you take money out and plan to put it back the same year."]
        case "rrsp":
            return ["Check how much you’re allowed to put in on your latest notice of assessment, the summary the Canada Revenue Agency sends after processing a tax return. The money can generally grow without tax while it stays inside. The amount of tax saved now depends on your own tax situation."]
        case "rrsp-withdrawals":
            return ["Before taking money out, ask how much cash you’ll actually receive. When you file taxes, the amount already sent by the bank counts as a prepayment, and your final bill may be higher or lower."]
        case "credit", "card-payment":
            return ["Check the due date and whether your earlier payment has posted. Paying the minimum and clearing the full statement balance are different. With an applicable grace period, paying the full statement balance on time generally avoids interest on eligible purchases."]
        case "compounding":
            return ["This same idea applies when savings interest stays in the account: future interest can be calculated on deposits plus earlier interest. Try starting earlier or saving a little more, and never treat an illustrative growth rate as a promise."]
        default:
            return Array(plainLanguageSteps.dropFirst())
        }
    }
}
