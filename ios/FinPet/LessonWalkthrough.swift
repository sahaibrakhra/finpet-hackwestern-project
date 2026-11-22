import SwiftUI

struct LessonWalkthrough {
    struct Actor {
        let name: String
        let icon: String
    }

    struct Beat {
        let title: String
        let amount: String
        let note: String
        let direction: Direction
        let rightActor: Actor?

        enum Direction {
            case forward, backward, up, down, still

            var icon: String? {
                switch self {
                case .forward: "arrow.right"
                case .backward: "arrow.left"
                case .up: "arrow.up"
                case .down: "arrow.down"
                case .still: nil
                }
            }

            var isVertical: Bool { self == .up || self == .down }
        }

        init(_ title: String, _ amount: String, _ note: String, _ direction: Direction, rightActor: Actor? = nil) {
            self.title = title
            self.amount = amount
            self.note = note
            self.direction = direction
            self.rightActor = rightActor
        }
    }

    let left: Actor
    let right: Actor
    let beats: [Beat]

    init(_ left: Actor, _ right: Actor, _ beats: [Beat]) {
        self.left = left
        self.right = right
        self.beats = beats
    }

    static func forLesson(_ id: String) -> Self? {
        byLesson[id] ?? PracticeWorkshop.byID[id]?.walkthrough
    }

    private static let byLesson: [String: Self] = [
        "stock-ownership": Self(
            Actor(name: "Mina", icon: "person.fill"), Actor(name: "Bakery", icon: "storefront"),
            [
                Beat("Buy one share", "$20", "Mina pays a seller $20 for a tiny piece of the bakery.", .forward,
                     rightActor: Actor(name: "Seller", icon: "person.fill")),
                Beat("Get a dividend", "$1", "The bakery pays Mina $1 while Mina owns the share.", .backward),
                Beat("Sell the share", "$23", "A new investor pays Mina $23 for the share.", .backward,
                     rightActor: Actor(name: "New investor", icon: "person.fill")),
                Beat("Work out the gain", "+$4", "Mina gets $24 back in total. Subtract the $20 Mina originally spent.", .up)
            ]
        ),
        "bond-lending": Self(
            Actor(name: "Leo", icon: "person.fill"), Actor(name: "City", icon: "building.columns"),
            [
                Beat("Lend the city money", "$100", "Leo buys a bond, which is a loan to the city.", .forward),
                Beat("Get paid a year later", "$104", "If the city pays as promised, Leo gets the $100 back plus $4 for lending it.", .backward),
                Beat("What did Leo buy?", "A loan", "The city promised to pay Leo back. Leo didn’t buy a piece of the city or its bridge.", .still)
            ]
        ),
        "investments": Self(
            Actor(name: "Bakery shares", icon: "storefront"), Actor(name: "Mixed fund", icon: "basket"),
            [
                Beat("Start with the same amount", "$100", "Asha can put all $100 in the bakery or buy a basket of investments called a fund.", .still),
                Beat("Compare the two choices", "One vs. many", "The first choice depends on one bakery. The fund includes the bakery and other businesses.", .still),
                Beat("The bakery struggles", "Risk spreads", "A bakery problem can hit the one-stock choice hard. The bakery is just one part of the mixed fund.", .down)
            ]
        ),
        "invest-index": Self(
            Actor(name: "Index", icon: "list.bullet.rectangle"), Actor(name: "Fund", icon: "basket"),
            [
                Beat("Start with a scoreboard", "S&P 500", "The Standard & Poor’s 500 measures how large U.S. companies’ stocks are doing.", .still),
                Beat("A fund follows the scoreboard", "Index fund", "The fund buys investments to try to follow the index.", .forward),
                Beat("You buy part of the fund", "One unit", "One fund can give you a piece of many companies instead of depending on one company alone.", .still)
            ]
        ),
        "invest-holdings": Self(
            Actor(name: "Fund A", icon: "basket"), Actor(name: "Fund B", icon: "basket.fill"),
            [
                Beat("Open both fund summaries", "ETF Facts", "An exchange-traded fund’s summary shows what the fund follows and what it owns.", .still),
                Beat("Check what both funds follow", "Large U.S. stocks", "The funds have different names but follow similar baskets of companies.", .still),
                Beat("Check what’s missing", "Same market", "If your goal is to add companies from elsewhere, look for holdings outside the United States.", .still)
            ]
        ),
        "plan-housing-costs": Self(
            Actor(name: "Before tax", icon: "banknote"), Actor(name: "Housing", icon: "house"),
            [
                Beat("Start with household income", "$3,000", "Use the monthly amount before tax for this benchmark.", .still),
                Beat("Take 30% of that amount", "$900", "Multiply $3,000 by 0.30 for a first-pass comparison.", .down),
                Beat("Compare the full housing cost", "$950", "Rent plus essential utilities is $50 above the benchmark in this example. Now check what is left after tax and other essentials.", .up)
            ]
        ),
        "plan-annuity": Self(
            Actor(name: "Savings", icon: "archivebox"), Actor(name: "Regular income", icon: "calendar"),
            [
                Beat("Start with a lump sum", "Savings now", "An annuity uses some savings to buy a contract for future payments.", .forward),
                Beat("The contract pays over time", "Monthly income", "A life annuity pays while the person lives under the contract. A term-certain annuity pays for a set time.", .backward),
                Beat("Check the trade-off", "Cash access", "A regular payment can help cover bills, but getting the original money back may be difficult or impossible.", .still)
            ]
        ),
        "rrsp": Self(
            Actor(name: "Sam", icon: "person.fill"), Actor(name: "Retirement savings", icon: "archivebox"),
            [
                Beat("Put money aside", "$2,000", "Sam saves $2,000 in a Registered Retirement Savings Plan (RRSP).", .forward),
                Beat("Take $2,000 off the tax calculation", "$48,000", "Sam earns $50,000. Claiming the $2,000 deduction leaves $48,000 in this example.", .down),
                Beat("A deduction changes the tax bill", "$400", "If the tax on that $2,000 would have been 20%, Sam saves $400 in tax in this example.", .still),
                Beat("Take money out later", "Tax later", "Money Sam takes out normally counts as income in the year Sam receives it.", .backward)
            ]
        ),
        "rrsp-withdrawals": Self(
            Actor(name: "Jo’s account", icon: "archivebox"), Actor(name: "Jo and the tax agency", icon: "person.fill"),
            [
                Beat("Request money from the account", "$1,000", "Jo asks the bank to take out $1,000. The full amount leaves the retirement account.", .forward),
                Beat("The bank splits it", "$900 + $100", "Jo gets $900. The bank sends $100 toward Jo’s taxes.", .still),
                Beat("Report the full amount", "$1,000", "Jo generally reports $1,000 as income. The $100 counts as tax already paid.", .still)
            ]
        ),
        "tfsa": Self(
            Actor(name: "You", icon: "person.fill"), Actor(name: "Savings account", icon: "archivebox"),
            [
                Beat("Put money in", "$1,000", "A Tax-Free Savings Account (TFSA) can hold cash or investments. Deposits use some of the amount you’re allowed to put in.", .forward),
                Beat("The investment grows", "$1,200", "The extra $200 is growth. Growth doesn’t count as money you put in.", .up),
                Beat("Take money out", "$1,200", "The growth is generally free of Canadian tax. The amount taken out generally adds back to your room next year.", .backward)
            ]
        ),
        "tfsa-timing": Self(
            Actor(name: "Jamie", icon: "person.fill"), Actor(name: "Savings account", icon: "archivebox"),
            [
                Beat("Put money in", "$600", "Jamie starts with $900 of space to add money. After adding $600, Jamie has $300 of space left.", .forward),
                Beat("Take cash out", "$400", "Jamie takes out $400. The space to put more in this year stays at $300.", .backward),
                Beat("Choose when to put it back", "$300 now", "Putting all $400 back now would go $100 over. The $400 taken out generally adds room next January.", .still)
            ]
        ),
        "card-payment": Self(
            Actor(name: "Riley", icon: "person.fill"), Actor(name: "Card company", icon: "creditcard"),
            [
                Beat("The bill closes", "$500", "Riley’s bill shows $500. That snapshot is the statement balance.", .still),
                Beat("Pay part of the bill", "$120", "Riley pays $120. Only $380 remains on the bill due June 18.", .forward),
                Beat("Buy groceries after the bill closes", "$40", "The later purchase raises the current balance to $420. The amount left on the June 18 bill is still $380.", .up)
            ]
        ),
        "tfsa-room": Self(
            Actor(name: "Bank A", icon: "building.columns"), Actor(name: "Bank B", icon: "building.columns"),
            [
                Beat("Start with one shared limit", "$2,000", "Contribution room is how much more you can put into all of your Tax-Free Savings Accounts combined.", .still),
                Beat("Put $600 into Bank A", "$1,400 left", "The $600 uses some of your shared room.", .down),
                Beat("Put $400 into Bank B", "$1,000 left", "The second deposit uses the same room. A second account doesn’t give you a second limit.", .down)
            ]
        ),
        "fund-fees": Self(
            Actor(name: "Fund A", icon: "chart.bar"), Actor(name: "Fund B", icon: "chart.bar.xaxis"),
            [
                Beat("Both investments gain $50", "+$50 each", "Imagine you put $1,000 into each fund and each earns the same $50 before fees.", .up),
                Beat("Take out the fees", "−$10 vs. −$2", "In this simplified example, a 1% fee on $1,000 costs $10 and a 0.2% fee costs $2.", .down),
                Beat("Compare the gains you keep", "$40 vs. $48", "Subtract the fee from each $50 gain. Fees are one part of choosing a fund.", .still)
            ]
        ),
        "credit": Self(
            Actor(name: "Cardholder", icon: "person.fill"), Actor(name: "Card company", icon: "creditcard"),
            [
                Beat("Read the bill", "$500", "The statement balance is the amount owed when the card company made the bill.", .still),
                Beat("Pay only the minimum", "$25", "The minimum is the smallest required payment, not the whole bill.", .forward),
                Beat("See what remains", "$475 left", "The balance drops by $25. The remaining $475 may collect interest.", .down)
            ]
        ),
        "retirement-gap": Self(
            Actor(name: "Before pension", icon: "calendar"), Actor(name: "After pension", icon: "calendar.badge.checkmark"),
            [
                Beat("Start with spending", "$30,000/year", "The plan already has $12,000 of yearly income, leaving $18,000 to cover each year.", .still),
                Beat("Cover three years", "$54,000", "At $18,000 per year, three years before the pension starts add up to $54,000.", .up),
                Beat("The pension starts", "$8,000/year", "The new $10,000 pension brings total income to $22,000. The yearly gap falls to $8,000.", .down)
            ]
        ),
        "compounding": Self(
            Actor(name: "Year one", icon: "calendar"), Actor(name: "Year two", icon: "calendar.badge.plus"),
            [
                Beat("Start with $100", "$100", "Assume the investment grows 10% each year for this example.", .still),
                Beat("Leave the first gain invested", "$110", "The investment grows $10 in year one. The next year starts at $110.", .forward),
                Beat("Earn growth on the gain too", "$121", "Ten percent of $110 is $11. The extra dollar comes from leaving the first year’s gain invested.", .up)
            ]
        )
    ]
}

struct LessonWalkthroughView: View {
    let walkthrough: LessonWalkthrough
    @Environment(\.mascotPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var travel: CGFloat = 0
    @State private var moveTask: Task<Void, Never>?

    private var beat: LessonWalkthrough.Beat { walkthrough.beats[index] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("See it happen", systemImage: "play.circle").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(index + 1) of \(walkthrough.beats.count)").font(.footnote.monospacedDigit()).foregroundStyle(muted)
            }
            diagram
            Text(beat.title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(beat.note).font(.body)
                .accessibilityAddTraits(.updatesFrequently)

            HStack(spacing: 9) {
                Button { show(index - 1) } label: {
                    Image(systemName: "chevron.left").font(.subheadline.bold())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).disabled(index == 0)
                .accessibilityLabel("Previous step")
                HStack(spacing: 5) {
                    ForEach(walkthrough.beats.indices, id: \.self) { position in
                        Capsule().fill(position == index ? palette.accent : palette.rule)
                            .frame(width: position == index ? 16 : 5, height: 5)
                    }
                }.accessibilityHidden(true)
                Spacer()
                Button {
                    show(index + 1 == walkthrough.beats.count ? 0 : index + 1)
                } label: {
                    Text(index + 1 == walkthrough.beats.count ? "Replay" : "Next step")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .foregroundStyle(.white)
                        .background(palette.accent, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 14))
        .onAppear { animate(beat.direction) }
        .onDisappear { moveTask?.cancel() }
    }

    private var diagram: some View {
        HStack(alignment: .top, spacing: 10) {
            actor(walkthrough.left)
            GeometryReader { lane in
                let bounds = max(0, lane.size.width - 74)
                ZStack {
                    if beat.direction == .forward || beat.direction == .backward {
                        Capsule().fill(palette.rule).frame(height: 2)
                    }
                    HStack(spacing: 4) {
                        if let icon = beat.direction.icon {
                            Image(systemName: icon).font(.caption.weight(.bold))
                        }
                        Text(beat.amount)
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .lineLimit(1).minimumScaleFactor(0.65)
                    }
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 7).padding(.vertical, 6)
                    .background(palette.paper, in: Capsule())
                    .offset(x: beat.direction.isVertical ? 0 : travel * bounds * 0.24,
                            y: beat.direction.isVertical ? travel * 10 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(height: 55)
            actor(beat.rightActor ?? walkthrough.right)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(beat.amount)
    }

    private func actor(_ actor: LessonWalkthrough.Actor) -> some View {
        VStack(spacing: 5) {
            Image(systemName: actor.icon).font(.system(size: 17, weight: .medium))
                .frame(width: 43, height: 43)
                .background(palette.paper, in: Circle())
            Text(actor.name).font(.caption.weight(.medium)).multilineTextAlignment(.center)
        }
        .foregroundStyle(palette.accent)
        .frame(width: 65)
    }

    private func show(_ position: Int) {
        guard walkthrough.beats.indices.contains(position) else { return }
        index = position
        animate(beat.direction)
    }

    private func animate(_ direction: LessonWalkthrough.Beat.Direction) {
        moveTask?.cancel()
        travel = 0
        guard !reduceMotion, direction != .still else { return }
        let sign: CGFloat = direction == .forward || direction == .down ? 1 : -1
        travel = -sign
        moveTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(35)) } catch { return }
            withAnimation(.easeInOut(duration: 0.54)) { travel = sign }
        }
    }
}
