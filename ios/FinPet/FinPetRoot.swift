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
    case review(Lesson, ReviewSchedule)

    var id: String {
        switch self {
        case .setup: "setup"
        case .lesson(_, let key): key
        case .review(let lesson, _): "review-" + lesson.id
        }
    }
}

struct FinPetRoot: View {
    @AppStorage("finpet.ref.name") private var name = "Loonie"
    @AppStorage("finpet.ref.color") private var color: PetColor = .leaf
    @AppStorage("finpet.ref.personality") private var personality = "Just tryna be normal"
    @AppStorage("finpet.ref.photo") private var photo = Data()
    @AppStorage("finpet.education.history") private var history = Data()
    @AppStorage("finpet.education.attempts") private var attemptData = Data()
    @AppStorage("finpet.education.reviews") private var reviewData = Data()
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

    private var reviews: [String: ReviewSchedule] {
        var records = (try? JSONDecoder().decode([String: ReviewSchedule].self, from: reviewData)) ?? [:]
        let history = completed
        for lesson in LessonLibrary.daily where records[lesson.id] == nil {
            if let date = history["library-" + lesson.id] {
                records[lesson.id] = .first(after: date, missed: [], calendar: calendar)
            }
        }
        return records
    }

    private var reviewQueue: [(lesson: Lesson, schedule: ReviewSchedule)] {
        let records = reviews
        return LessonLibrary.daily.compactMap { lesson in
            records[lesson.id].map { (lesson, $0) }
        }.sorted {
            if $0.schedule.due == $1.schedule.due { return $0.lesson.title < $1.lesson.title }
            return $0.schedule.due < $1.schedule.due
        }
    }

    private func saveReview(_ id: String, schedule: ReviewSchedule) {
        var records = reviews
        records[id] = schedule
        if let data = try? JSONEncoder().encode(records) { reviewData = data }
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
                MascotEditor(name: $name, color: $color, personality: $personality,
                             photo: $photo, close: { sheet = nil })
            case .lesson(let lesson, let key):
                Quiz(pet: pet(), lesson: lesson, completed: { score, missed in
                    if var schedule = reviews[lesson.id] {
                        if !missed.isEmpty {
                            schedule.missed = missed
                            schedule.due = min(schedule.due, ReviewSchedule.first(after: .now, missed: missed, calendar: calendar).due)
                            saveReview(lesson.id, schedule: schedule)
                        }
                    } else {
                        saveReview(lesson.id, schedule: .first(after: .now, missed: missed, calendar: calendar))
                    }
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
            case .review(let lesson, let schedule):
                let order = schedule.questions(total: lesson.questions.count)
                Quiz(pet: pet(), lesson: lesson, completed: { _, missed in
                    let pending = schedule.missed.filter { !order.contains($0) } + missed
                    saveReview(lesson.id, schedule: schedule.next(after: .now, missed: pending, calendar: calendar))
                    var updated = completed
                    updated["practice-" + dateKey(.now)] = .now
                    if let data = try? JSONEncoder().encode(updated) { history = data }
                    day = .now
                }, reviewQuestions: order, close: { sheet = nil })
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
                            .overlay(alignment: .bottom) {
                                Capsule().fill(page == item ? forest : .clear).frame(width: 13, height: 2)
                            }
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
            Text(title).font(.system(.largeTitle, design: .serif, weight: .semibold))
            Spacer()
        }
    }

    private func pet() -> Pet {
        Pet(color: color, photo: photo.isEmpty ? nil : photo)
    }

    private func dateKey(_ date: Date, monthly: Bool = false) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let month = "\(parts.year ?? 0)-\(parts.month ?? 0)"
        return monthly ? month : month + "-\(parts.day ?? 0)"
    }

    private var dailyLessons: [Lesson] {
        let ordinal = calendar.ordinality(of: .day, in: .era, for: day) ?? 0
        let start = ordinal % LessonLibrary.daily.count
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
        VStack(alignment: .leading, spacing: 21) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    heading(petName)
                    Text(mood).font(.subheadline).foregroundStyle(muted)
                }
                Button { sheet = .setup } label: {
                    Image(systemName: "slider.horizontal.3").font(.headline)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(forest)
                        .overlay { Circle().strokeBorder(line) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Customize mascot")
            }
            MascotStage(mascot: pet())
                .frame(height: mascotHeight)
            VStack(alignment: .leading, spacing: 0) {
                Text("Challenge of the day").font(.title2.weight(.semibold)).padding(.bottom, 7)
                ForEach(Array(dailyLessons.enumerated()), id: \.element.id) { index, lesson in
                    if index > 0 { Divider() }
                    challenge(lesson, key: "daily-\(dateKey(day))-\(lesson.id)", primary: index == 0)
                }
            }
            Divider()
            reviewSection
            Divider()
            streakBoard
            Divider()
            VStack(alignment: .leading, spacing: 11) {
                Text("Challenge of the month").font(.title2.weight(.semibold))
                monthlyQuest
            }
        }
    }

    private var reviewSection: some View {
        let queue = reviewQueue
        let due = queue.filter { $0.schedule.due <= day }
        return VStack(alignment: .leading, spacing: 7) {
            Text("Quick review").font(.title3.weight(.semibold))
            if let next = due.first {
                Button { sheet = .review(next.lesson, next.schedule) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(next.lesson.title).font(.headline)
                            Text("\(due.count) due · 3 questions per review").font(.subheadline).foregroundStyle(muted)
                        }
                        Spacer()
                        Image(systemName: "arrow.clockwise").foregroundStyle(forest)
                    }.padding(.vertical, 7).contentShape(Rectangle())
                }.buttonStyle(.plain)
            } else if let next = queue.first {
                Text("Next review \(next.schedule.due.formatted(.dateTime.month(.abbreviated).day())).")
                    .font(.subheadline).foregroundStyle(muted)
            } else {
                Text("Finish a lesson to get your first review tomorrow.").font(.subheadline).foregroundStyle(muted)
            }
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
        }
    }

    private func challenge(_ lesson: Lesson, key: String, primary: Bool) -> some View {
        let done = completed[key] != nil
        return Button { sheet = .lesson(lesson, completionKey: key) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.title).font(primary ? .title3.weight(.semibold) : .headline)
                    Text(done ? "Completed · Review" : (primary ? "\(lesson.questions.count) questions" : "Bonus practice"))
                        .font(.subheadline).foregroundStyle(muted)
                }
                Spacer()
                Image(systemName: done ? "checkmark.circle.fill" : "chevron.right")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(forest)
            }
            .padding(.vertical, 13).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var monthlyQuest: some View {
        let month = attempts.values.filter { calendar.isDate($0.date, equalTo: day, toGranularity: .month) }
        let byDay = Dictionary(grouping: month, by: { calendar.startOfDay(for: $0.date) })
        let mostInOneDay = byDay.values.map(\.count).max() ?? 0
        let perfectLessons = Set(month.filter { $0.score == $0.questions }.map(\.lessonID)).count
        let exercises = month.reduce(0) { $0 + $1.questions }
        return VStack(alignment: .leading, spacing: 12) {
            Text(day.formatted(.dateTime.month(.wide))).font(.subheadline).foregroundStyle(muted)
            questRow("Finish 3 different lessons in one day", mostInOneDay, 3)
            questRow("Get a perfect score on 2 lessons", perfectLessons, 2)
            questRow("Complete 25 questions", exercises, 25)
            Button("Browse lessons") { page = .learn }
                .font(.subheadline.weight(.semibold)).foregroundStyle(forest)
                .padding(.vertical, 6)
        }
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
                    .font(.subheadline.weight(.medium)).foregroundStyle(muted)
                pet().frame(width: 55).clipped()
            }
            reviewSection
            Divider()
            ForEach(LessonLibrary.units, id: \.title) { unit in
                unitPath(unit)
            }
        }
    }

    private func unitPath(_ unit: LearningUnit) -> some View {
        let count = unit.lessons.filter { completed["library-" + $0.id] != nil }.count
        let next = unit.lessons.first { completed["library-" + $0.id] == nil }?.id
        return VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(unit.title).font(.system(.title2, design: .serif, weight: .semibold))
                    Spacer(minLength: 12)
                    Text("\(count)/\(unit.lessons.count)")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(muted)
                        .accessibilityLabel("\(count) of \(unit.lessons.count) lessons completed")
                }
                Meter(progress: Double(count) / Double(unit.lessons.count), background: mint)
            }
            .padding(.top, 12)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(unit.lessons) { lesson in
                    let key = "library-" + lesson.id
                    let done = completed[key] != nil
                    let current = lesson.id == next
                    Button { sheet = .lesson(lesson, completionKey: key) } label: {
                        HStack(spacing: 12) {
                            pathNode(done: done, current: current)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lesson.title).font(.subheadline.weight(current ? .semibold : .medium))
                                if current {
                                    Text("Up next · \(lesson.questions.count) questions")
                                        .font(.caption).foregroundStyle(muted)
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(muted)
                        }
                        .frame(minHeight: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(done ? "Review completed lesson" : "Open lesson")
                }
            }.background(alignment: .leading) {
                Rectangle().fill(line).frame(width: 1).padding(.leading, 13).padding(.vertical, 24)
            }
            Divider()
        }
    }

    private func pathNode(done: Bool, current: Bool) -> some View {
        Image(systemName: done ? "checkmark" : (current ? "book.closed" : "circle.fill"))
            .font(.system(size: done || current ? 11 : 4, weight: .semibold))
            .foregroundStyle(current ? .white : forest)
            .frame(width: 27, height: 27)
            .background(current ? forest : (done ? mint : cream), in: Circle())
            .overlay { Circle().strokeBorder(current ? .clear : line) }
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
                            Pet(color: friend.color).frame(width: 46)
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
