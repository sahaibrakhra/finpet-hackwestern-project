import SwiftUI

private enum Page: String, CaseIterable {
    case home = "Home", learn = "Learn", friends = "Friends"

    var icon: String {
        switch self {
        case .home: "house"
        case .learn: "leaf"
        case .friends: "person.2"
        }
    }
}

private enum Sheet: Identifiable {
    case setup
    case lesson(Lesson, completionKey: String)

    var id: String {
        switch self {
        case .setup: "setup"
        case .lesson(_, let key): key
        }
    }
}

struct FinPetRoot: View {
    @AppStorage("finpet.ref.name") private var name = "Loonie"
    @AppStorage("finpet.ref.color") private var color: PetColor = .leaf
    @AppStorage("finpet.ref.accessory") private var accessory = "Scarf"
    @AppStorage("finpet.ref.personality") private var personality = "Just tryna be normal"
    @AppStorage("finpet.ref.photo") private var photo = Data()
    @AppStorage("finpet.education.history") private var history = Data()
    @AppStorage("finpet.education.attempts") private var attemptData = Data()
    @AppStorage("finpet.ref.checkins") private var checkins = ""
    @AppStorage("finpet.ref.friends") private var extraFriends = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var day = Date()
    @State private var page: Page = .home
    @State private var sheet: Sheet?
    @State private var invite = false
    @State private var friendName = ""

    private var petName: String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Loonie" : value
    }
    private var completed: [String: Date] {
        (try? JSONDecoder().decode([String: Date].self, from: history)) ?? [:]
    }
    private var calendar: Calendar { .current }
    private var attempts: [String: Attempt] {
        (try? JSONDecoder().decode([String: Attempt].self, from: attemptData)) ?? [:]
    }

    private struct Attempt: Codable {
        let date: Date
        let lessonID: String
        let score: Int
        let questions: Int
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                Group {
                    switch page {
                    case .home: home(mascotHeight: viewport.size.height * 0.49)
                    case .learn: learn
                    case .friends: friends
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 22)
            }
            .defaultScrollAnchor(.top)
            .id(page)
        }
        .foregroundStyle(ink)
        .background(cream.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { tabs }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { day = .now }
        }
        .task {
            while !Task.isCancelled {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))
                guard let tomorrow else { return }
                do {
                    try await Task.sleep(for: .seconds(max(1, tomorrow.timeIntervalSinceNow)))
                    day = .now
                } catch { return }
            }
        }
        .fullScreenCover(item: $sheet) { item in
            switch item {
            case .setup:
                MascotEditor(name: $name, color: $color, accessory: $accessory, personality: $personality,
                             photo: $photo, close: { sheet = nil })
            case .lesson(let lesson, let key):
                Quiz(pet: pet(), lesson: lesson, completed: { score in
                    var updated = completed
                    updated[key] = .now
                    updated["library-" + lesson.id] = .now
                    var recorded = attempts
                    let attemptKey = dateKey(.now) + "-" + lesson.id
                    if recorded[attemptKey] == nil || score > (recorded[attemptKey]?.score ?? 0) {
                        recorded[attemptKey] = Attempt(date: .now, lessonID: lesson.id, score: score,
                                                       questions: lesson.questions.count)
                        if let data = try? JSONEncoder().encode(recorded) { attemptData = data }
                    }
                    updated["practice-" + dateKey(.now)] = .now
                    if let data = try? JSONEncoder().encode(updated) { history = data }
                    day = .now
                }, close: { sheet = nil })
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

    private func heading(_ title: String) -> some View {
        HStack {
            Text(title).font(.system(size: 34, weight: .heavy))
            Spacer()
        }
    }

    private func pet() -> Pet {
        Pet(color: color, accessory: accessory, photo: photo.isEmpty ? nil : photo)
    }

    private func dateKey(_ date: Date, monthly: Bool = false) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let month = "\(parts.year ?? 0)-\(parts.month ?? 0)"
        return monthly ? month : month + "-\(parts.day ?? 0)"
    }

    private var dailyLessons: [Lesson] {
        let ordinal = calendar.ordinality(of: .day, in: .era, for: day) ?? 0
        let start = (ordinal * 2) % LessonLibrary.daily.count
        return [LessonLibrary.daily[start], LessonLibrary.daily[(start + 1) % LessonLibrary.daily.count]]
    }

    private var practiceDays: Set<Date> {
        Set(completed.filter { $0.key.hasPrefix("practice-") }.values.map { calendar.startOfDay(for: $0) })
    }

    private func offset(_ days: Int, from date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    private var streak: Int {
        let days = practiceDays
        let today = calendar.startOfDay(for: day)
        var date = days.contains(today) ? today : offset(-1, from: today)
        var count = 0
        while days.contains(date) {
            count += 1
            date = offset(-1, from: date)
        }
        return count
    }

    private var mood: String {
        if practiceDays.contains(calendar.startOfDay(for: day)) { return "\(petName) is in a good mood." }
        let hour = calendar.component(.hour, from: .now)
        return hour >= 19 ? "\(petName) is winding down." : "\(petName) ponders…"
    }

    private func home(mascotHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            heading(petName)
            MascotStage(mascot: pet())
                .frame(height: mascotHeight)
                .overlay(alignment: .topLeading) {
                    Text(mood).font(.footnote.weight(.semibold)).foregroundStyle(forest)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white.opacity(0.9), in: Capsule())
                        .padding(12).padding(.trailing, 50)
                }
                .overlay(alignment: .topTrailing) {
                    Button { sheet = .setup } label: {
                        Image(systemName: "camera").font(.headline).frame(width: 44, height: 44)
                            .foregroundStyle(forest).background(.white.opacity(0.85), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photo.isEmpty ? "Upload mascot photo" : "Change mascot photo")
                    .padding(12)
                }
            streakBoard
            Text("Daily challenges").font(.title2.bold())
            ForEach(dailyLessons) { lesson in
                challenge(lesson, key: "daily-\(dateKey(day))-\(lesson.id)", icon: "sun.max")
            }
            Text("Monthly challenge").font(.title2.bold())
            monthlyQuest
        }
    }

    private var streakBoard: some View {
        let today = calendar.startOfDay(for: day)
        let days = practiceDays
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Learning streak", systemImage: "flame.fill").foregroundStyle(forest)
                Spacer()
                Text("\(streak) \(streak == 1 ? "day" : "days")").foregroundStyle(muted)
            }.font(.subheadline.bold())
            HStack {
                ForEach((-6)...0, id: \.self) { distance in
                    let date = offset(distance, from: today)
                    let done = days.contains(date)
                    VStack(spacing: 4) {
                        Text(date.formatted(.dateTime.weekday(.narrow))).font(.caption2.bold())
                        Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.headline)
                    }
                    .foregroundStyle(done ? forest : muted)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(date.formatted(.dateTime.weekday(.wide)) + (done ? ", practised" : ", no practice"))
                }
            }
        }.petCard()
    }

    private func challenge(_ lesson: Lesson, key: String, icon: String) -> some View {
        let done = completed[key] != nil
        return Button { sheet = .lesson(lesson, completionKey: key) } label: {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark" : icon).font(.headline).foregroundStyle(forest)
                    .frame(width: 40, height: 40).background(mint, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.title).font(.headline)
                    Text(done ? "Completed · tap to review" : "Quick briefing · \(lesson.questions.count) questions")
                        .font(.footnote).foregroundStyle(muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(muted)
            }.petCard()
        }.buttonStyle(.plain)
    }

    private var monthlyQuest: some View {
        let month = attempts.values.filter { calendar.isDate($0.date, equalTo: day, toGranularity: .month) }
        let byDay = Dictionary(grouping: month, by: { calendar.startOfDay(for: $0.date) })
        let mostInOneDay = byDay.values.map(\.count).max() ?? 0
        let perfectLessons = Set(month.filter { $0.score == $0.questions }.map(\.lessonID)).count
        let exercises = month.reduce(0) { $0 + $1.questions }
        return VStack(alignment: .leading, spacing: 12) {
            Text(day.formatted(.dateTime.month(.wide)) + " learning quest").font(.headline)
            questRow("Finish 3 different lessons in one day", mostInOneDay, 3)
            questRow("Get a perfect score on 2 lessons", perfectLessons, 2)
            questRow("Complete 25 questions", exercises, 25)
            ActionButton(title: "Go to lessons", secondary: true) { page = .learn }
        }.petCard()
    }

    private func questRow(_ title: String, _ value: Int, _ target: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text("\(min(value, target))/\(target)").bold()
            }.font(.footnote)
            Meter(progress: Double(value) / Double(target), background: mint)
        }
    }

    private var learn: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            HStack {
                heading("Learn")
                Label("\(streak)", systemImage: "flame.fill")
                    .font(.subheadline.bold()).padding(8).background(honey, in: Capsule())
                pet().frame(width: 55)
            }
            ForEach(Array(LessonLibrary.units.enumerated()), id: \.offset) { index, unit in
                unitPath(unit, number: index + 1)
            }
        }
    }

    private func unitPath(_ unit: LearningUnit, number: Int) -> some View {
        let count = unit.lessons.filter { completed["library-" + $0.id] != nil }.count
        let next = unit.lessons.first { completed["library-" + $0.id] == nil }?.id
        return VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Unit \(number)").foregroundStyle(muted)
                    Spacer()
                    Text("\(count) of \(unit.lessons.count) done").foregroundStyle(forest)
                }.font(.subheadline.bold())
                Text(unit.title).font(.title2.weight(.heavy))
                Meter(progress: Double(count) / Double(unit.lessons.count))
            }.padding(17).background(mint, in: RoundedRectangle(cornerRadius: 24))
            VStack(alignment: .leading, spacing: 13) {
                ForEach(unit.lessons) { lesson in
                    let key = "library-" + lesson.id
                    let done = completed[key] != nil
                    let current = lesson.id == next
                    HStack(spacing: 12) {
                        pathNode(done: done, current: current)
                        if current {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Up next").font(.footnote.bold()).foregroundStyle(forest)
                                Text(lesson.title).font(.title3.weight(.heavy))
                                Text("Quick briefing · \(lesson.questions.count) questions").font(.footnote).foregroundStyle(muted)
                                ActionButton(title: "Start lesson") { sheet = .lesson(lesson, completionKey: key) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .petCard()
                            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(forest) }
                        } else if done {
                            Button { sheet = .lesson(lesson, completionKey: key) } label: {
                                pathLabel(lesson.title, detail: "Done · tap to review")
                            }.buttonStyle(.plain)
                        } else {
                            pathLabel(lesson.title, detail: "Locked · finish the earlier lesson")
                                .foregroundStyle(muted)
                        }
                    }
                }
            }.background(alignment: .leading) {
                Rectangle().fill(mint).frame(width: 4).padding(.leading, 34).padding(.vertical, 28)
            }
        }
    }

    private func pathLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            Text(detail).font(.footnote).foregroundStyle(muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pathNode(done: Bool, current: Bool) -> some View {
        Image(systemName: done ? "checkmark" : (current ? "book.closed" : "lock"))
            .font(current ? .title2.bold() : .headline)
            .foregroundStyle(current ? .white : (done ? forest : muted))
            .frame(width: current ? 59 : 49, height: current ? 59 : 49)
            .background(current ? forest : (done ? mint : cream), in: Circle())
            .overlay { Circle().strokeBorder(done || current ? ink : muted.opacity(0.5),
                                             style: StrokeStyle(lineWidth: 2, dash: done || current ? [] : [4, 2])) }
            .padding(current ? 4 : 0)
            .overlay { if current { Circle().strokeBorder(PetColor.sunny.fill, lineWidth: 3) } }
            .frame(width: 72)
            .accessibilityHidden(true)
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
                Text("Share your practice streak and check-ins with friends.")
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

}
