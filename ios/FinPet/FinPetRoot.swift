import SwiftUI
import PhotosUI

private enum Page: String, CaseIterable {
    case home = "Home", learn = "Learn", money = "Money", friends = "Friends"
    var icon: String {
        switch self {
        case .home: "house"
        case .learn: "leaf"
        case .money: "checkmark.shield"
        case .friends: "person.2"
        }
    }
}

private enum Sheet: String, Identifiable {
    case setup, lesson, purchases
    var id: String { rawValue }
}

struct FinPetRoot: View {
    @AppStorage("finpet.ref.name") private var name = "Loonie"
    @AppStorage("finpet.ref.color") private var color: PetColor = .leaf
    @AppStorage("finpet.ref.accessory") private var accessory = "Scarf"
    @AppStorage("finpet.ref.personality") private var personality = "Just tryna be normal"
    @AppStorage("finpet.ref.photo") private var photo = Data()
    @AppStorage("finpet.ref.savings") private var savings = 1240.0
    @AppStorage("finpet.ref.tasks") private var tasks = 0
    @AppStorage("finpet.ref.reviews") private var reviews = 0
    @AppStorage("finpet.ref.checkins") private var checkins = ""
    @AppStorage("finpet.ref.friends") private var extraFriends = ""
    @AppStorage("finpet.ref.auto") private var autoSave = false
    @State private var page: Page = .home
    @State private var sheet: Sheet?
    @State private var invite = false
    @State private var friendName = ""
    @State private var confidence = false
    @AppStorage("finpet.ref.confidence") private var lastConfidence = ""
    private let goal = 4050.0
    private var petName: String { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Loonie" : name }
    private var progress: Double { savings / goal }
    private var finishedLesson: Bool { tasks & 2 != 0 }

    var body: some View {
        ScrollView {
            Group {
                switch page {
                case .home: home
                case .learn: learn
                case .money: money
                case .friends: friends
                }
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 22)
        }
        .defaultScrollAnchor(.top)
        .id(page)
        .foregroundStyle(ink)
        .background(cream.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { tabs }
        .fullScreenCover(item: $sheet) { item in
            switch item {
            case .setup: setup
            case .lesson:
                Quiz(pet: pet(), completed: {
                    tasks |= 2
                    sheet = nil
                }, close: { sheet = nil })
            case .purchases: purchases
            }
        }
        .alert("Start a shared streak", isPresented: $invite) {
            TextField("Friend’s name", text: $friendName)
            Button("Add demo friend") {
                let value = friendName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty && !value.contains("|") && !allFriends.contains(where: { $0.name == value }) {
                    extraFriends += extraFriends.isEmpty ? value : "|" + value
                }
                friendName = ""
            }
            Button("Cancel", role: .cancel) { friendName = "" }
        } message: {
            Text("This adds a friend to the local demo.")
        }
        .confirmationDialog("How does money feel today?", isPresented: $confidence, titleVisibility: .visible) {
            ForEach(["Good", "Okay", "Worried"], id: \.self) { answer in
                Button(answer) { lastConfidence = answer; tasks |= 1 }
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Page.allCases, id: \.self) { item in
                Button {
                    page = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon).font(.system(size: 18, weight: .semibold))
                            .frame(width: 54, height: 31)
                            .background(page == item ? mint : .clear, in: Capsule())
                        Text(item.rawValue).font(.caption.weight(page == item ? .bold : .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(page == item ? ink : muted)
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .background(.white)
        .overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
    }

    private func heading(_ title: String, streak: Bool = false) -> some View {
        HStack {
            Text(title).font(.system(size: 34, weight: .heavy))
            Spacer()
            if streak {
                Label("12", systemImage: "flame.fill").font(.headline.weight(.heavy))
                    .padding(.horizontal, 12).padding(.vertical, 6).background(honey, in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func pet(shield: Bool = false) -> Pet {
        Pet(color: color, accessory: accessory, photo: photo.isEmpty ? nil : photo, shield: shield)
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 15) {
            heading(petName, streak: true)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("$58").font(.system(size: 45, weight: .heavy))
                    Text("left this week").font(.headline)
                    Text("of $196 · 2 days to go").font(.subheadline).foregroundStyle(muted)
                    Meter(progress: 58 / 196).padding(.top, 7)
                    Button("Customize \(petName)") { sheet = .setup }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(forest).padding(.top, 12)
                }
                pet().frame(maxWidth: 120)
            }
            .padding(19).background(mint, in: RoundedRectangle(cornerRadius: 25))
            if reviews < 2 {
                ActionButton(title: "Review \(2 - reviews) \(reviews == 1 ? "purchase" : "purchases")") { sheet = .purchases }
            }
            Button { page = .money } label: {
                HStack(spacing: 13) {
                    Image(systemName: "checkmark.shield.fill").font(.system(size: 27)).foregroundStyle(forest)
                    VStack(spacing: 8) {
                        HStack {
                            Text("Emergency fund").fontWeight(.semibold)
                            Spacer()
                            Text("\(cash(savings)) of \(cash(goal))").foregroundStyle(muted)
                        }.font(.subheadline)
                        Meter(progress: progress, background: mint)
                    }
                }.petCard()
            }.buttonStyle(.plain)
            HStack {
                Text("Today").font(.title2.bold())
                Spacer()
                Text("\(tasks.nonzeroBitCount) of 3 done").foregroundStyle(muted).font(.subheadline)
            }
            VStack(spacing: 0) {
                task("Money check-in", detail: lastConfidence.isEmpty ? "One tap: how does money feel?" : lastConfidence, flag: 1) { confidence = true }
                Divider()
                task("Today’s lesson", detail: "TFSA basics · 3 questions", flag: 2) { sheet = .lesson }
                Divider()
                task("Move $5 to emergency fund", detail: "Optional today", flag: 4) {
                    if tasks & 4 == 0 { savings += 5; tasks |= 4 }
                }
            }.petCard()
        }
    }

    private func task(_ title: String, detail: String, flag: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tasks & flag == 0 ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(tasks & flag == 0 ? muted : forest).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.footnote).foregroundStyle(muted)
                }
                Spacer()
                if flag == 2 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(muted) }
            }.padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var learn: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Learn", streak: true)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Unit 2").foregroundStyle(muted)
                    Spacer()
                    Text(finishedLesson ? "2 of 5 done" : "1 of 5 done").foregroundStyle(forest)
                }.font(.subheadline.weight(.semibold))
                Text("Canadian accounts").font(.title2.weight(.heavy))
                Meter(progress: finishedLesson ? 0.4 : 0.2).padding(.top, 5)
            }.padding(17).background(mint, in: RoundedRectangle(cornerRadius: 24))
            VStack(alignment: .leading, spacing: 13) {
                pathRow("Emergency funds", detail: "Done · 3 of 3 right", icon: "checkmark", active: true)
                HStack(spacing: 13) {
                    Image(systemName: "book.closed").font(.title2.bold()).foregroundStyle(.white)
                        .frame(width: 74, height: 74).background(forest, in: Circle())
                        .padding(5).overlay { Circle().strokeBorder(PetColor.sunny.fill, lineWidth: 3) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(finishedLesson ? "Practise again" : "Up next").font(.footnote.bold()).foregroundStyle(forest)
                        Text("TFSA basics").font(.title3.weight(.heavy))
                        Text("3 questions · 2 min").font(.footnote).foregroundStyle(muted)
                        ActionButton(title: "Start lesson") { sheet = .lesson }.padding(.top, 7)
                    }.petCard()
                }
                pathRow("FHSA for a first home", detail: "First home savings account", icon: "lock")
                pathRow("Reward", detail: "A new accessory for \(petName)", icon: "gift", reward: true)
                pathRow("RRSP and your first home", detail: "Locked · 4 questions", icon: "lock")
                pathRow("Unit review", detail: "Which account first?", icon: "trophy")
            }.background(alignment: .leading) {
                Rectangle().fill(mint).frame(width: 4).padding(.vertical, 24).padding(.leading, 40)
            }
        }
    }

    private func pathRow(_ title: String, detail: String, icon: String, active: Bool = false, reward: Bool = false) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.headline).foregroundStyle(active ? forest : muted)
                .frame(width: 52, height: 52)
                .background(reward ? honey : (active ? mint : cream), in: Circle())
                .overlay { Circle().strokeBorder(active ? ink : muted.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: active ? [] : [4, 2])) }
                .frame(width: 84)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.footnote).foregroundStyle(active ? forest : muted)
            }
        }
    }

    private var money: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                heading("Money")
                Text("This week").foregroundStyle(muted).font(.subheadline)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Emergency fund").font(.subheadline.bold()).foregroundStyle(muted)
                        Text(cash(savings)).font(.system(size: 42, weight: .heavy))
                        Text("of \(cash(goal)) · \(progress.formatted(.percent.precision(.fractionLength(0)))) there")
                            .font(.subheadline).foregroundStyle(muted)
                    }
                    Spacer()
                    pet(shield: true).frame(width: 105)
                }
                Meter(progress: progress)
            }.padding(17).background(mint, in: RoundedRectangle(cornerRadius: 23))
            HStack {
                ActionButton(title: "Add $20") { savings += 20 }
                ActionButton(title: autoSave ? "Auto-save on" : "Auto-save", secondary: true) { autoSave.toggle() }
            }
            if autoSave {
                Text("Auto-save is on for this demo.").font(.footnote).foregroundStyle(muted)
            }
            Text("Goals").font(.title2.bold())
            VStack(spacing: 9) {
                goalRow("Reading week trip", "tent", 180, 400)
                Divider()
                goalRow("New laptop", "laptopcomputer", 420, 1200)
                Divider()
                goalRow("Winter coat", "tshirt", 150, 150)
            }.petCard()
            Text("Recent").font(.title2.bold())
            VStack(spacing: 8) {
                ForEach(Array(demoPurchases.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Divider() }
                    transaction(item)
                }
            }.petCard()
        }
    }

    private func goalRow(_ title: String, _ icon: String, _ saved: Double, _ target: Double) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 31, height: 31).background(mint, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).fontWeight(.semibold)
                    Spacer()
                    Text("\(cash(saved)) / \(cash(target))").foregroundStyle(muted)
                }.font(.subheadline)
                if saved == target {
                    Label("Goal reached", systemImage: "checkmark").font(.caption.bold()).foregroundStyle(forest)
                } else {
                    Meter(progress: saved / target, background: mint)
                }
            }
        }
    }

    private var demoPurchases: [(title: String, detail: String, amount: Double)] {
        [("Noodle bar", "Want · Yesterday", 24.50), ("Campus bookstore", "Need · Yesterday", 31.20),
         ("Grocery store", "Need · Sunday", 31.84)]
    }

    private func transaction(_ item: (title: String, detail: String, amount: Double)) -> some View {
        HStack {
            Text(String(item.title.prefix(1))).font(.footnote.bold()).frame(width: 29, height: 29)
                .background(mint, in: Circle()).overlay { Circle().strokeBorder(ink, lineWidth: 1.5) }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.medium))
                Text(item.detail).font(.caption).foregroundStyle(muted)
            }
            Spacer()
            Text("−\(cash(item.amount))").font(.subheadline.bold())
        }
    }

    private var allFriends: [(name: String, days: Int, ready: Bool, color: PetColor)] {
        [("Priya", 21, true, .berry), ("Sam", 9, true, .sunny), ("Jordan", 5, false, .sky)] +
        extraFriends.split(separator: "|").map { (String($0), 0, false, .leaf) }
    }

    private var friends: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                heading("Friends")
                Button("Invite") { invite = true }
                    .font(.headline).foregroundStyle(forest).petCard(radius: 14)
            }
            Label {
                Text("Friends see streaks and check-ins only, never your balances or purchases.")
                    .font(.subheadline)
            } icon: { Image(systemName: "lock").font(.footnote) }
            .foregroundStyle(muted)
            Text("Shared streaks").font(.title2.weight(.heavy))
            ForEach(allFriends, id: \.name) { friend in
                let checked = checkins.split(separator: "|").contains(Substring(friend.name))
                VStack(spacing: 11) {
                    HStack(spacing: 8) {
                        HStack(spacing: -9) {
                            pet().frame(width: 46)
                            Pet(color: friend.color, accessory: "None").frame(width: 46)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("You + \(friend.name)").font(.headline)
                            Text(checked ? "You checked in" : (friend.ready ? "\(friend.name) is in. Your turn" : "Neither of you yet today"))
                                .font(.caption).foregroundStyle(muted)
                        }
                        Spacer()
                        Label("\(friend.days + (checked && friend.ready ? 1 : 0))", systemImage: "flame.fill")
                            .font(.title3.weight(.heavy))
                    }
                    Divider()
                    HStack(spacing: 10) {
                        Label("You", systemImage: checked ? "checkmark.circle.fill" : "circle")
                        Label(friend.name, systemImage: friend.ready ? "checkmark.circle.fill" : "circle")
                        Spacer(minLength: 0)
                        Button(checked ? "Checked in" : "Check in") {
                            checkins += checkins.isEmpty ? friend.name : "|" + friend.name
                            tasks |= 1
                        }
                        .font(.footnote.bold()).padding(.horizontal, 10).padding(.vertical, 10)
                        .foregroundStyle(checked ? forest : .white)
                        .background(checked ? mint : forest, in: RoundedRectangle(cornerRadius: 12))
                        .disabled(checked)
                    }.font(.caption.weight(.medium))
                }.petCard()
            }
            ActionButton(title: "＋  Start a shared streak", secondary: true) { invite = true }
        }
    }

    private var setup: some View {
        MascotEditor(name: $name, color: $color, accessory: $accessory, personality: $personality,
                     photo: $photo, close: { sheet = nil })
    }

    private var purchases: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if reviews < 2 {
                    Text("Confirm the category for this purchase.").foregroundStyle(muted)
                    transaction(demoPurchases[reviews]).petCard()
                    ActionButton(title: "Confirm purchase") { reviews += 1 }
                } else {
                    Text("You’re all caught up.").font(.title2.bold())
                    ActionButton(title: "Back to Home") { sheet = nil }
                }
                Spacer()
            }.padding().background(cream).foregroundStyle(ink)
                .navigationTitle("Review purchases")
                .toolbar { Button("Done") { sheet = nil }.foregroundStyle(forest) }
        }
    }
}
