extension LessonLibrary {
    static let appliedExamples: [String: LessonExample] = [
        "tfsa-timing": LessonExample("Jamie’s TFSA ledger", [
            ("Available room before May", "$900"), ("May deposit", "−$600"),
            ("July withdrawal", "$400"), ("Room left this year", "$300")
        ], "The $400 withdrawal is added back next calendar year. Until then, only $300 is available if there are no other transactions."),
        "rrsp-compare": LessonExample("Two illustrative withdrawal quotes", [
            ("Quote A: gross / withheld / net", "$1,000 / $100 / $900"),
            ("Quote B: gross / withheld / net", "$1,200 / $120 / $1,080"),
            ("Cash needed", "$1,000")
        ], "Use the net amount to plan your cash. Use the gross amount and withholding to check the tax slip."),
        "fhsa-plan": LessonExample("Two funding routes", [
            ("Option A", "$2,000 cash contribution"), ("Option B", "$2,000 direct RRSP transfer"),
            ("FHSA room used by either option", "$2,000")
        ], "Only the eligible cash contribution can create a new FHSA deduction. A direct transfer moves existing savings."),
        "card-payment": LessonExample("Sample statement and payment history", [
            ("Statement balance", "$500"), ("Minimum due June 18", "$25"),
            ("Payment already posted", "$120"), ("New purchase after statement date", "$40")
        ], "The $40 is outside this statement. The remaining statement balance is $500 minus $120."),
        "portfolio": LessonExample("Hypothetical $1,000 portfolios", [
            ("Portfolio A: stocks / bonds / cash", "20% / 60% / 20%"),
            ("Portfolio B: stocks / bonds / cash", "80% / 15% / 5%"),
            ("Stock shock only", "−20% on stocks")
        ], "Multiply the dollar amount in stocks by 20%. For this exercise, bonds and cash stay flat."),
        "retirement-gap": LessonExample("Illustrative early retirement income", [
            ("Annual spending", "$30,000"), ("Annual income before pension", "$12,000"),
            ("Pension starts", "3 years later"), ("Pension income after it starts", "$10,000/year")
        ], "Assume the other income continues and costs stay constant. This simplified example excludes returns and taxes.")
    ]

    static let tfsaTiming = Lesson(id: "tfsa-timing", title: "Plan a TFSA recontribution", briefing: [
        "Read the ledger in date order. Subtract a deposit from available contribution room immediately.",
        "A withdrawal gives you cash but generally adds room back on January 1 of the next calendar year. To put it back sooner, you need room you already have.",
        "Compare the amount you want to deposit with this year’s available room. Keep a record across every TFSA you own."
    ], questions: [
        Question("After the May deposit, how much room remains?", ["$300", "$600", "$900"], 0, "Subtract $600 from the $900 of available room."),
        Question("What is Jamie’s available room immediately after withdrawing $400 in July?", ["$700", "$300", "$0"], 1, "The withdrawal does not change this year’s room."),
        Question("Jamie wants to redeposit all $400 in August. How much would exceed the room shown?", ["$0", "$100", "$400"], 1, "$400 is $100 more than the $300 available."),
        Question("How much room does that July withdrawal generally add back next January?", ["$300", "$400", "$700"], 1, "The withdrawal itself adds back $400. Other sources of room are calculated separately."),
        Question("Jamie finds a separate $150 TFSA deposit made elsewhere this year. What current room is left?", ["$150", "$300", "$450"], 0, "The second account shares the same room. Subtract $150 from $300.")
    ])

    static let rrspCompare = Lesson(id: "rrsp-compare", title: "Plan for what you’ll receive", briefing: [
        "Compare a withdrawal quote’s gross amount, tax withheld, and cash you actually receive. Subtract withholding from gross to get the net payment.",
        "For an ordinary RRSP withdrawal, the gross amount is generally included in income. Withholding is credited toward tax, and final tax can differ.",
        "Use realistic quotes from your institution to compare how much you would withdraw and whether you have enough net cash."
    ], questions: [
        Question("Which quote provides at least $1,000 in cash?", ["A only", "B only", "Both"], 1, "Quote B nets $1,080. Quote A nets $900."),
        Question("How much more does B remove from the RRSP?", ["$20", "$180", "$200"], 2, "Compare gross withdrawals of $1,200 and $1,000."),
        Question("How much cash is left after paying the $1,000 expense using quote B?", ["$80", "$120", "$200"], 0, "Subtract $1,000 from the $1,080 received."),
        Question("What gross amount would generally count as income for B?", ["$1,080", "$1,200", "$120"], 1, "Withholding changes your cash proceeds, while the gross amount is generally included in income."),
        Question("Does $120 withheld settle the exact final tax?", ["Always", "No, reconcile it on your tax return"], 1, "The final result depends on your full tax situation.")
    ])

    static let fhsaPlan = Lesson(id: "fhsa-plan", title: "Compare cash and RRSP transfers", briefing: [
        "Before adding money, check whether you qualify to open an FHSA and how much participation room you have.",
        "A cash contribution and a direct transfer from an RRSP are different funding routes. Both generally use FHSA room. Only the eligible cash contribution can create a new FHSA deduction.",
        "Ask your institutions to arrange a direct transfer. Withdrawing the money from an RRSP yourself generally has different tax consequences."
    ], questions: [
        Question("If you have $2,000 of available room, how much is left after choosing Option A?", ["$0", "$1,000", "$2,000"], 0, "A $2,000 cash contribution uses the $2,000 of room."),
        Question("With the same starting room, how much is left after choosing Option B?", ["$0", "$2,000"], 0, "A direct transfer also generally uses FHSA room."),
        Question("Which can create a new FHSA deduction?", ["The eligible cash contribution", "The direct RRSP transfer", "Both"], 0, "The direct RRSP transfer is excluded from the FHSA deduction."),
        Question("Can you do both $2,000 transactions with only $2,000 of room?", ["Yes", "No"], 1, "Together they would use $4,000 of room."),
        Question("How should you arrange Option B?", ["Ask the institutions for a direct transfer", "Take an ordinary RRSP withdrawal yourself"], 0, "A direct transfer and an ordinary withdrawal have different tax treatment.")
    ])

    static let cardPayment = Lesson(id: "card-payment", title: "Work out what to pay", briefing: [
        "Riley’s credit card bill shows $500 owed when the billing period ended. That snapshot is the statement balance. Riley has already paid $120 toward that bill.",
        "The $120 payment leaves $380 on this bill. Later, Riley spends $40 on groceries. The card app might now say $420 is owed in total, but only $380 is left from the bill due June 18. The $40 purchase came after the bill was made.",
        "Riley’s $120 payment covered the $25 minimum, the least the card company requires. Clearing the rest of the bill by June 18 is a different goal. If the card’s purchase grace period applies, paying the full bill on time generally avoids purchase interest."
    ], questions: [
        Question("How much of the statement balance remains after the $120 payment?", ["$380", "$420", "$500"], 0, "$500 minus $120 leaves $380."),
        Question("Which amount belongs to the next statement period in this example?", ["The $40 new purchase", "The original $500 statement"], 0, "The $40 purchase happened after the statement date."),
        Question("How much more should be paid by June 18 to clear this statement?", ["$25", "$380", "$420"], 1, "The remaining statement balance is $380. The later purchase is separate."),
        Question("Did the $120 posted payment cover the $25 minimum?", ["Yes", "No"], 0, "$120 exceeds the minimum, but it did not clear the statement."),
        Question("If you pay only another $100, what remains from this statement before interest?", ["$280", "$380", "$0"], 0, "$380 minus $100 leaves $280.")
    ])

    static let portfolio = Lesson(id: "portfolio", title: "Stress-test an investment mix", briefing: [
        "To turn an allocation into dollars, multiply the portfolio’s value by the percentage in each asset. An 80% stock allocation in a $1,000 portfolio means $800 is exposed to stocks.",
        "A hypothetical downturn can help you compare exposure. A 20% fall means multiplying the amount in stocks by 0.20 to find the loss.",
        "Match your analysis to when the money is needed. Real stock, bond, and fund prices can change, and this exercise holds bonds and cash flat to isolate stock exposure."
    ], questions: [
        Question("How many dollars in Portfolio A are invested in stocks?", ["$200", "$600", "$800"], 0, "Twenty percent of $1,000 is $200."),
        Question("How much does Portfolio A lose in the exercise?", ["$20", "$40", "$200"], 1, "Twenty percent of its $200 stock holding is $40."),
        Question("How much does Portfolio B lose?", ["$20", "$80", "$160"], 2, "Twenty percent of its $800 stock holding is $160."),
        Question("What is Portfolio B worth after the simulated decline?", ["$840", "$960", "$1,160"], 0, "Subtract the $160 loss from $1,000."),
        Question("If you need the money for tuition next term, what should you test?", ["Whether a decline would leave enough cash when tuition is due", "Whether the stock names sound familiar"], 0, "Time horizon and the ability to cover the expense matter.")
    ])

    static let retirementGap = Lesson(id: "retirement-gap", title: "Map an income gap", briefing: [
        "Calculate the annual shortfall by subtracting expected annual income from expenses. List when each income source begins.",
        "Multiply the pre-pension annual shortfall by the number of bridge years to estimate its total under fixed assumptions.",
        "Recalculate after the pension starts and test a higher-spending scenario. This exercise isolates cash flow so you can see which assumptions matter."
    ], questions: [
        Question("What is the annual gap before the pension starts?", ["$12,000", "$18,000", "$30,000"], 1, "$30,000 of spending minus $12,000 of income leaves $18,000."),
        Question("What is the three-year gap under the example assumptions?", ["$18,000", "$36,000", "$54,000"], 2, "Multiply $18,000 by three years."),
        Question("After the $10,000 pension begins, what total annual income is available?", ["$10,000", "$22,000", "$30,000"], 1, "Add the pension to the $12,000 of ongoing income."),
        Question("What annual gap remains after the pension starts?", ["$8,000", "$12,000", "$18,000"], 0, "Subtract $22,000 from $30,000."),
        Question("If annual spending rises to $33,000, what is the new three-year pre-pension gap?", ["$57,000", "$63,000", "$99,000"], 1, "The annual gap becomes $21,000. Multiply by three.")
    ])
}
