import Foundation

struct BriefingWord: Identifiable {
    let id: String
    let meaning: String
    let search: [String]

    init(_ name: String, _ meaning: String, searching: [String] = []) {
        id = name
        self.meaning = meaning
        search = searching.isEmpty ? [name] : searching
    }
}

struct BeginnerGuide {
    let situation: String
    let words: [BriefingWord]
}

extension Lesson {
    var beginnerGuide: BeginnerGuide {
        switch id {
        case _ where id.hasPrefix("tfsa"):
            BeginnerGuide(situation: "Imagine you’re setting money aside for school or a future purchase. A Tax-Free Savings Account (TFSA) is one place Canadians can put those savings. This lesson shows what to check before you move money.",
                words: [
                    BriefingWord("TFSA", "Short for Tax-Free Savings Account. Think of it as a container for your money or investments. What the money earns inside is generally free of Canadian tax."),
                    BriefingWord("Contribution", "Money you put into the account.", searching: ["contribut", "deposit"]),
                    BriefingWord("Contribution room", "How much more money you are allowed to put in. It’s separate from how much money is already in the account.", searching: ["room", "limit"]),
                    BriefingWord("Withdrawal", "Money you take out of the account.", searching: ["withdraw", "take out", "took out"]),
                    BriefingWord("CRA", "Canada Revenue Agency, the federal agency that administers Canadian tax rules.", searching: ["cra"]),
                    BriefingWord("Direct transfer", "The financial institutions move money from one account to another for you.", searching: ["transfer", "move between"]),
                    BriefingWord("GIC", "Guaranteed Investment Certificate. You typically agree to leave money with a financial institution for a set term, in exchange for interest.", searching: ["gic", "fixed-term"]),
                    BriefingWord("Interest", "Money the account or product pays you for keeping money there.", searching: ["interest", "earn"])
                ])
        case _ where id.hasPrefix("rrsp"):
            BeginnerGuide(situation: "Imagine you’re setting some paycheque money aside for when you stop working. A Registered Retirement Savings Plan (RRSP) is a Canadian account meant for retirement savings. The tax rules matter when you put money in or take it out.",
                words: [
                    BriefingWord("RRSP", "Short for Registered Retirement Savings Plan. Think of it as an account for retirement savings."),
                    BriefingWord("Contribution", "Money you put into the plan.", searching: ["contribut", "deposit"]),
                    BriefingWord("Deduction", "An amount you can subtract when calculating income subject to tax. It is not the same amount as the tax saved.", searching: ["deduct"]),
                    BriefingWord("Contribution room", "The amount you can still put in under the rules.", searching: ["room", "limit"]),
                    BriefingWord("Notice of assessment", "The summary the Canada Revenue Agency sends after it processes a tax return.", searching: ["assessment", "notice", "cra"]),
                    BriefingWord("Gross and net", "Gross is the amount before anything is taken off. Net is what actually reaches your bank account.", searching: ["gross", "net ", "received"]),
                    BriefingWord("Tax withheld", "Money taken out of the payment and sent toward your taxes. Your tax return determines the final amount.", searching: ["withheld", "withhold"]),
                    BriefingWord("Direct transfer", "The institutions move the money between plans for you.", searching: ["transfer"])
                ])
        case _ where id.hasPrefix("fhsa"):
            BeginnerGuide(situation: "Imagine you’re saving to buy your first home. A First Home Savings Account (FHSA) is a Canadian account for people who meet the first-home rules. This lesson shows how to tell what happens when money goes in or comes out.",
                words: [
                    BriefingWord("FHSA", "Short for First Home Savings Account."),
                    BriefingWord("Contribution room", "How much you can still add under the account rules.", searching: ["room"]),
                    BriefingWord("Deduction", "An amount you can subtract when calculating income subject to tax.", searching: ["deduct"]),
                    BriefingWord("Qualifying withdrawal", "Money taken out for a home purchase that meets Canada Revenue Agency conditions.", searching: ["qualify", "withdraw"]),
                    BriefingWord("RRSP", "Registered Retirement Savings Plan. An account intended for retirement savings.", searching: ["rrsp"]),
                    BriefingWord("RRIF", "Registered Retirement Income Fund. A plan used to draw income from retirement savings.", searching: ["rrif"]),
                    BriefingWord("Withholding", "Money taken off a payment and sent toward your taxes before the rest reaches you.", searching: ["withhold", "withheld"])
                ])
        case "credit", "card-payment", "loans",
             _ where id.hasPrefix("credit-"):
            BeginnerGuide(situation: "Imagine you bought something with a credit card or borrowed money for a purchase. The documents tell you how much you owe, when to pay, and which charges can add to the cost.",
                words: [
                    BriefingWord("Statement", "The bill covering a fixed period. It shows the balance at the end of that period and when payment is due.", searching: ["statement"]),
                    BriefingWord("Minimum payment", "The smallest amount required by the due date.", searching: ["minimum"]),
                    BriefingWord("Interest", "What the lender charges for borrowing money."),
                    BriefingWord("Grace period", "Time when eligible purchases generally avoid interest if you pay the full statement balance on time.", searching: ["grace period"]),
                    BriefingWord("Posted", "A charge or payment the card issuer has recorded as complete.", searching: ["post", "pending"]),
                    BriefingWord("Principal", "The amount borrowed, before interest and fees.", searching: ["principal", "loan"]),
                    BriefingWord("Credit limit", "The most the issuer allows you to borrow on the card.", searching: ["limit", "utilization"])
                ])
        case "investments", "fund-fees", "portfolio",
             _ where id.hasPrefix("invest-"):
            BeginnerGuide(situation: "Imagine you have money you won’t need right away and are comparing ways to invest it. Your choice affects how much it might grow, what it costs, and how much it might fall.",
                words: [
                    BriefingWord("Stock", "A small ownership share in a company.", searching: ["stock", "share"]),
                    BriefingWord("Bond", "Money investors lend to a government or company. The borrower promises payments under agreed terms.", searching: ["bond", "coupon"]),
                    BriefingWord("Fund or ETF", "A fund is a basket of investments. An ETF, or exchange-traded fund, is a basket you can buy or sell on a stock exchange.", searching: ["fund", "etf"]),
                    BriefingWord("Portfolio", "The collection of investments you own.", searching: ["portfolio", "allocat", "holdings"]),
                    BriefingWord("Return", "How much an investment gains or loses, including money it pays you.", searching: ["return", "gain", "distribution"]),
                    BriefingWord("Fee", "Money you pay for a service, such as buying or managing an investment.", searching: ["fee", "commission"]),
                    BriefingWord("Downturn", "A period when investments fall in value.", searching: ["downturn", "simulated loss"])
                ])
        default:
            BeginnerGuide(situation: "Imagine planning for a time when you’ll work less or stop working. The goal is to estimate what you’ll spend, when money will come in, and how much savings may need to cover.",
                words: [
                    BriefingWord("Pension", "Regular retirement income you may receive from a workplace or government plan.", searching: ["pension"]),
                    BriefingWord("Income gap", "What you still need to cover after you subtract income from expenses.", searching: ["gap", "shortfall", "bridge", "to cover"]),
                    BriefingWord("Compound growth", "When money you’ve already earned stays invested and can earn more money.", searching: ["compound", "growth", "return"]),
                    BriefingWord("Inflation", "A rise in prices over time. The same money may buy less later.", searching: ["inflation", "prices"]),
                    BriefingWord("Scenario", "A made-up set of numbers used to test what could happen if a plan changes.", searching: ["scenario", "assumption", "hypothetical"])
                ])
        }
    }

    var quickTake: String {
        if let intro = Self.tfsaQuickTakes[id] { return intro }
        if let workshop = PracticeWorkshop.byID[id] { return workshop.rule }
        return briefing.first ?? beginnerGuide.situation
    }

    private static let tfsaQuickTakes = [
        "tfsa": "A Tax-Free Savings Account (TFSA) is a place to save or invest. If the money grows while it’s inside, the growth is generally free of Canadian tax.",
        "tfsa-room": "Contribution room is the amount you can still put in. If you have accounts at two banks, both use the same room.",
        "tfsa-timing": "Taking money out gives you cash today. The room to put that money back generally returns next January.",
        "tfsa-payday": "A payday transfer uses room just like a manual deposit. Compare what you’ve put in, plus the next transfer, with the room you started with.",
        "tfsa-records": "Add up the deposits from every bank. Each bank’s statement shows only what happened there.",
        "tfsa-unused": "Unused room generally rolls into the next year. Think of it as space for future deposits that you haven’t used yet.",
        "tfsa-transfer": "Switching banks? An eligible direct transfer lets the banks move the money without using new contribution room.",
        "tfsa-loss": "A drop in price doesn’t give you more room. If you take out money, the actual withdrawal is what generally adds room back next year.",
        "tfsa-next-year": "Two things can carry into January: room left unused and money you took out last year. Check both before you put more money in.",
        "tfsa-product": "If tuition is due soon, check how much you can actually take out by the deadline. Some investments may have changed in price or be locked in."
    ]

    var plainLanguageSteps: [String] {
        Self.tfsaSteps[id] ?? briefing
    }

    var relevantWords: [BriefingWord] {
        let reading = (plainLanguageSteps + example.rows.map(\.label) + questions.map(\.prompt))
            .joined(separator: " ").lowercased()
        return beginnerGuide.words.filter { word in word.search.contains { reading.contains($0.lowercased()) } }
    }

    private static let tfsaSteps: [String: [String]] = [
        "tfsa": [
            "Picture two things: a container and what you put inside it. The TFSA is the container. Inside it you can keep cash or buy investments, such as a small ownership share in a company.",
            "Here’s the benefit. If your $1,000 grows to $1,200 inside the account, the extra $200 is generally free of Canadian tax, even when you take the money out.",
            "There’s a limit on how much you can put in. Putting money into a TFSA doesn’t lower your taxable income. Taking money out generally gives you that much room back on January 1 next year."
        ],
        "tfsa-room": [
            "Imagine you’re allowed to put $2,000 more into your account. That $2,000 is your contribution room. It is the space for new money, not the amount you already have saved.",
            "Put in $600 and you have $1,400 of space left. Put another $400 into a TFSA at a different bank and you have $1,000 left overall. The two banks share one limit.",
            "Room you don’t use can carry over. Money you take out generally adds space back next year. Keep your own record because the number shown online by the Canada Revenue Agency can miss recent activity."
        ],
        "tfsa-timing": [
            "Jamie wants to take money out for a bill, then put it back. The question is whether there’s enough space left to do that this year.",
            "Jamie had $900 of space and used $600 by putting money in. That leaves $300. Taking out $400 later doesn’t change the $300 right now.",
            "Putting all $400 back now would go $100 over. Next January the $400 taken out usually adds back to the available space. Check for new deposits in any other TFSA before using the room."
        ],
        "tfsa-payday": [
            "Maya set her bank to move money into her TFSA every payday. An automatic deposit uses room just like a deposit she makes by hand.",
            "Add together the $900 already put in and the next $350. Maya will have put in $1,250 for that period.",
            "Compare the total with the room Maya had at the start of the period. A chequing account can have enough cash for the transfer even when the TFSA has too little room."
        ],
        "tfsa-records": [
            "Noah has one TFSA at each of two banks. Both let him see deposits to that bank, so neither screen shows his full picture.",
            "Add deposits from both statements. If Noah put in $1,800 at one bank and $700 at the other, he put in $2,500 overall.",
            "Compare the combined figure with the room he had available. Use a single list so a deposit doesn’t get missed just because it was at the other bank."
        ],
        "tfsa-unused": [
            "Priya didn’t use all her room last year. She wants to know whether the unused space still counts when the new year begins.",
            "Unused space generally carries forward. In this made-up example, she adds $1,200 of unused space to a new annual amount of $5,000 for $6,200.",
            "For a real calculation, also check eligible money taken out last year and deposits already made this year. Use the Canada Revenue Agency’s actual annual amount for the year you’re checking."
        ],
        "tfsa-transfer": [
            "Sam wants to move savings from one bank’s TFSA to another. The way the money travels matters.",
            "If both banks handle an eligible direct transfer, the money generally moves without using new contribution room. Moving $2,200 into an account with $1,800 would give that account $4,000 before charges.",
            "If Sam takes the money out himself and then deposits it at the new bank, the new deposit can use room. Ask the receiving bank to arrange the direct transfer."
        ],
        "tfsa-loss": [
            "Asha bought an investment inside her TFSA. Its price fell from $1,500 by $240, so it’s now worth $1,260.",
            "A fall in price isn’t money taken out. It doesn’t give Asha more space to put money into the account.",
            "If she takes out all $1,260, it’s that $1,260, not the original $1,500, that generally adds back to her room next year."
        ],
        "tfsa-next-year": [
            "Lee starts a fresh calendar year. He has two records from last year: space he never used and money he took out.",
            "Add $650 of unused space and $450 taken out last year. Together they account for $1,100 of room before other changes.",
            "That $1,100 is only part of the answer. Lee also needs to add the new annual amount if eligible and subtract any deposits he already made this year."
        ],
        "tfsa-product": [
            "Lina needs $2,400 for tuition soon. Some of her TFSA money is easy to use, but other money might be invested or held for a set time.",
            "If she can access $1,700 before tuition is due, she still needs $700. The total account balance matters less for this bill than what she can access by the deadline.",
            "Ask when each holding can be turned into cash and whether its value can fall. The TFSA is the account; the cash and investments inside it each have their own terms."
        ]
    ]
}
