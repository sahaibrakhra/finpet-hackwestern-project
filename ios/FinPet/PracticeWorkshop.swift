import Foundation

// Each workshop combines a worked calculation, a transfer exercise, a fact
// check, and a decision that can be made from the example.
struct PracticeWorkshop {
    let id: String
    let title: String
    let context: String
    let rule: String
    let first: (String, Int)
    let second: (String, Int)
    let operation: Operation
    let result: String
    let change: (String, Int)
    let statement: String
    let isTrue: Bool
    let decision: String
    let best: String
    let alternative: String
    let reason: String

    enum Operation: String {
        case add = "+", subtract = "−", multiply = "×"

        func apply(_ a: Int, _ b: Int) -> Int {
            switch self {
            case .add: a + b
            case .subtract: a - b
            case .multiply: a * b
            }
        }
    }

    init(_ id: String, _ title: String, _ context: String, _ rule: String,
         _ first: (String, Int), _ operation: Operation, _ second: (String, Int),
         _ result: String, _ change: (String, Int), _ statement: String, _ isTrue: Bool,
         _ decision: String, _ best: String, _ alternative: String, _ reason: String) {
        self.id = id
        self.title = title
        self.context = context
        self.rule = rule
        self.first = first
        self.second = second
        self.operation = operation
        self.result = result
        self.change = change
        self.statement = statement
        self.isTrue = isTrue
        self.decision = decision
        self.best = best
        self.alternative = alternative
        self.reason = reason
    }

    private func calculation(_ value: Int) -> String {
        "\(first.1.formatted()) \(operation.rawValue) \(value.formatted()) = \(operation.apply(first.1, value).formatted())"
    }

    private func calculationQuestion(_ prompt: String, value: Int, position: Int) -> Question {
        let answer = operation.apply(first.1, value)
        let mistakes = [max(first.1, value), abs(first.1 - value), first.1 + value, answer + 10, answer + 20]
        var options: [Int] = []
        for mistake in mistakes where mistake != answer && !options.contains(mistake) {
            options.append(mistake)
            if options.count == 2 { break }
        }
        options.insert(answer, at: position)
        return Question(prompt, options.map { "$" + $0.formatted() }, position, "The calculation is \(calculation(value)).")
    }

    var example: LessonExample {
        func display(_ field: (String, Int)) -> (String, String) {
            let money = field.0.hasSuffix(" (CAD)")
            let label = money ? String(field.0.dropLast(6)) : field.0
            return (label, (money ? "$" : "") + field.1.formatted())
        }
        return LessonExample("Worked example", [display(first), display(second),
              (result, "$" + operation.apply(first.1, second.1).formatted())],
              calculation(second.1))
    }

    var lesson: Lesson {
        Lesson(id: id, title: title, briefing: [
            context, rule, reason
        ], questions: [
            calculationQuestion("Using the example, calculate the amount for “\(result.lowercased()).”",
                                value: second.1, position: 1),
            Question("True or false? \(statement)", ["True", "False"], isTrue ? 0 : 1, rule),
            Question(decision, [alternative, best], 1, reason),
            calculationQuestion(change.0, value: change.1, position: 0),
            Question("Why does this situation matter when you make a decision?",
                     [reason, "The larger number is enough to make the decision on its own."],
                     0, reason)
        ])
    }

    static let byID = Dictionary(uniqueKeysWithValues:
        (tfsa + rrsp + fhsa + credit + investing + planning).map { ($0.id, $0) }
    )

    static let tfsa: [Self] = [
        .init("tfsa-payday", "Check room on payday", "A payday transfer is scheduled for Friday. Maya checks how much room remains before the new transfer.", "Add the proposed contribution to deposits already made when comparing them with available room for the period.", ("Deposits made this year (CAD)", 900), .add, ("Proposed deposit (CAD)", 350), "Total deposits", ("What are total deposits if the new deposit is $500 instead?", 500), "An automatic transfer counts as a contribution.", true, "What should Maya check before payday?", "Compare total deposits with the room available at the start of the period.", "Check the balance of her chequing account only.", "Available cash and available contribution room are separate constraints."),
        .init("tfsa-records", "Reconcile two bank records", "Noah deposits at two institutions and needs one combined record.", "Contribution room is shared across TFSAs. Add contributions across institutions before comparing the total with your available room.", ("Deposits at Bank A (CAD)", 1800), .add, ("Deposits at Bank B (CAD)", 700), "Combined deposits", ("If Bank B lists $950, what is the combined total?", 950), "Each bank provides a separate contribution limit.", false, "Which record should Noah maintain?", "One ledger covering every TFSA.", "Separate totals with no combined check.", "A combined ledger catches deposits that do not appear on the other institution’s statement."),
        .init("tfsa-unused", "Carry unused room forward", "Priya starts a new year with unused room and a new annual amount. The figures are hypothetical.", "Unused room can carry forward. Add the new annual amount and any qualifying prior-year withdrawals when calculating room, then subtract current-year contributions.", ("Unused room carried forward (CAD)", 1200), .add, ("Illustrative annual amount (CAD)", 5000), "Room before new deposits", ("What if the illustrative annual amount were $5,500?", 5500), "Unused room generally expires at year-end.", false, "Where should Priya get the actual annual amount?", "Verify the applicable year with the CRA.", "Assume the worksheet’s hypothetical amount applies.", "Annual amounts can vary. Check the relevant year and your own contribution and withdrawal records."),
        .init("tfsa-transfer", "Move a TFSA between banks", "Sam is consolidating accounts. He asks the institutions to move an eligible transfer directly.", "A qualifying direct TFSA transfer between issuers generally does not use new room. Withdrawing and redepositing yourself can use room.", ("Balance at receiving institution (CAD)", 1800), .add, ("Qualifying direct transfer (CAD)", 2200), "Receiving balance before fees", ("If the direct transfer is $900, what is the receiving balance before fees?", 900), "The same rule always applies if Sam withdraws and redeposits the cash himself.", false, "What should Sam request?", "Ask the receiving institution to arrange a qualifying direct transfer.", "Withdraw to chequing and redeposit regardless of room.", "A qualifying direct transfer can move the assets without creating a new contribution."),
        .init("tfsa-loss", "Separate a loss from a withdrawal", "Asha buys an investment in her TFSA. Its value falls, so she checks whether that changes her contribution records.", "A decline in investment value generally does not create contribution room. A withdrawal generally adds back the amount actually withdrawn next year.", ("Investment value before decline (CAD)", 1500), .subtract, ("Decline in value (CAD)", 240), "Current investment value", ("What is the value if the investment lost $350 instead?", 350), "A price decline alone gives Asha new room.", false, "Which amount matters if Asha later withdraws all of it?", "Record the amount actually withdrawn.", "Record the original purchase price as the withdrawal.", "Track contribution room and the market value of holdings separately."),
        .init("tfsa-next-year", "Build a January room estimate", "Lee has unused room and took cash out last year. This worksheet isolates those two sources before the new annual amount.", "Add unused room and any prior-year amount eligible to be added back. Also account for the current annual amount and this year’s contributions to get available room.", ("Unused room from last year (CAD)", 650), .add, ("Last year’s withdrawal (CAD)", 450), "Subtotal from prior-year activity", ("If last year’s withdrawal was $700, what is the subtotal?", 700), "This subtotal always equals all room available for the new year.", false, "What should Lee do before contributing?", "Include the current annual amount and subtract any deposits already made this year.", "Use the subtotal as the final figure in every case.", "A partial calculation can still leave out another source of room or recent contributions."),
        .init("tfsa-product", "Match a holding to a deadline", "A tuition deposit is due soon. Lina compares her TFSA’s cash balance with the amount due.", "A TFSA is the account. The liquidity and risk come from the holding inside it, including any terms on a fixed-term product.", ("Tuition deposit due (CAD)", 2400), .subtract, ("Usable cash available (CAD)", 1700), "Amount still needed", ("If usable cash is $2,100, what amount is still needed?", 2100), "Every investment inside a TFSA has the same access terms.", false, "What should Lina check first?", "Confirm which holdings can be accessed by the tuition deadline.", "Assume all holdings can be turned into cash immediately at their original value.", "A near-term deadline makes access and potential price changes relevant.")
    ]

    static let rrsp: [Self] = [
        .init("rrsp-room", "Read your notice before contributing", "Kai wants to contribute again this year and checks unused, already-reported contributions.", "Use the available contribution room shown in the RRSP section of the notice. Deduction limit and available room can differ when contributions are already reported but undeducted.", ("Illustrative deduction limit (CAD)", 4500), .subtract, ("Unused contributions already reported (CAD)", 1100), "Illustrative available room", ("What if unused contributions already reported are $1,500?", 1500), "Deduction limit and available contribution room always mean the same thing.", false, "Which figure should Kai verify before a new deposit?", "Available contribution room and deposits made since the notice.", "The deduction limit by itself.", "Existing undeducted contributions can already use room."),
        .init("rrsp-deduction", "Compare contribution and deduction", "Morgan makes an eligible RRSP contribution. In this example, only part is claimed as a deduction this year.", "A contribution is money put into the account. An eligible deduction is the amount claimed on the tax return. Track any eligible contributions left undeducted.", ("Eligible contribution (CAD)", 3000), .subtract, ("Deduction claimed this year (CAD)", 1800), "Contribution left undeducted", ("If Morgan claims $2,200 instead, what remains undeducted?", 2200), "The contribution and the deduction must always be identical in the same year.", false, "What should Morgan retain?", "Contribution receipts and a record of what was claimed.", "Only the ending account value.", "The account’s market value does not show how much of an eligible contribution has already been deducted."),
        .init("rrsp-matching", "Read a workplace match", "A fictional employer matches an employee’s monthly contribution up to a stated amount. The plan’s payroll deposit record shows both sides.", "Add both deposits to measure what goes into the plan. Check the plan rules and applicable room before changing payroll deductions.", ("Employee monthly deposit (CAD)", 80), .add, ("Employer monthly match (CAD)", 60), "Total monthly plan deposit", ("If the employer match is $80, what goes in that month?", 80), "The employer deposit never appears in total plan savings.", false, "What should the employee verify before raising the amount?", "The employer’s match cap and the plan’s treatment of contributions.", "Assume every workplace matches every dollar.", "Plans differ in eligibility, caps, and how contributions are reported."),
        .init("rrsp-transfer", "Compare moving and withdrawing", "Two institutions offer to consolidate an RRSP. Pat compares the tracked balances after an eligible direct transfer.", "An eligible direct RRSP transfer is not ordinarily treated as a withdrawal. Closing the account and taking the money personally generally is.", ("Existing receiving balance (CAD)", 2400), .add, ("Eligible direct transfer (CAD)", 1600), "Receiving balance before fees", ("If the direct transfer is $900, what is the receiving balance before fees?", 900), "A cheque made out to you is always equivalent to an eligible direct transfer.", false, "What should Pat request?", "Have the institutions process the direct transfer.", "Cash out the RRSP and assume there is no withholding.", "How money moves matters to the tax treatment."),
        .init("rrsp-slip", "Reconcile a withdrawal slip", "Ali receives a statement with gross proceeds and withholding and checks that it matches the cash received.", "Gross withdrawal and tax withheld are separate figures. Subtract withholding to reconcile the net deposit. Ordinary withdrawals are generally included in taxable income at the gross amount.", ("Gross withdrawal (CAD)", 1600), .subtract, ("Tax withheld (CAD)", 160), "Net bank deposit", ("If $240 were withheld, what would reach the bank?", 240), "The gross amount is the amount before withholding.", true, "Which records should Ali compare?", "The tax slip, withdrawal confirmation, and bank deposit.", "Only the amount deposited in the bank.", "The bank deposit alone does not show the gross income or tax prepaid."),
        .init("rrsp-cash", "Compare cash received with a bill", "A withdrawal has already been quoted, and Jordan needs to know how much of a bill would still be uncovered.", "Use net cash to assess the spending gap. The withholding amount remains separate from the cash received and may differ from the final tax.", ("Expense due (CAD)", 1900), .subtract, ("Net payment quoted (CAD)", 1500), "Cash still needed", ("If the net payment is $1,720, what is still needed?", 1720), "The quoted gross withdrawal can always be used as cash on hand.", false, "Which amount should Jordan use to cover the bill?", "Use the net payment and compare it with the amount due.", "Use the gross amount regardless of withholding.", "Withholding reduces the immediate cash available for the bill."),
        .init("rrsp-growth", "Read contributions versus growth", "An account statement shows a beginning balance, new deposits, and a closing balance. The example assumes no withdrawals.", "Subtract the starting balance plus deposits from the ending balance to estimate the remaining change. That change can include investment gains or losses and fees.", ("Ending balance (CAD)", 8500), .subtract, ("Starting balance plus deposits (CAD)", 8200), "Net change beyond deposits", ("If starting balance plus deposits is $8,100, what is the remaining change?", 8100), "All increase in the account balance is a new contribution.", false, "What should the learner use to check contribution room?", "Actual contribution receipts.", "The increase in the market value of the RRSP.", "Investment growth does not count as a new contribution.")
    ]
}
