import SwiftUI
import Pow

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
    @AppStorage("finpet.ref.matchAvatarPalette") private var matchAvatarPalette = true
    @AppStorage("finpet.ref.personality") private var personality = "Just tryna be normal"
    @AppStorage("finpet.ref.photo") private var photo = Data()
    @AppStorage("finpet.education.history") private var history = Data()
    @AppStorage("finpet.education.attempts") private var attemptData = Data()
    @AppStorage("finpet.education.reviews") private var reviewData = Data()
    @AppStorage("finpet.ref.checkins") private var checkins = ""
    @AppStorage("finpet.ref.friends") private var extraFriends = ""
    @EnvironmentObject private var auth: AuthSession
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var avatarBase: UIColor?
    @State private var day = Date()
    @State private var page: Page = .home
    @State private var sheet: Sheet?
    @State private var invite = false
    @State private var monthlyExpanded = false
    @State private var focusedUnit: String?
    @State private var friendName = ""

    private var palette: MascotPalette {
        MascotPalette(base: matchAvatarPalette ? (avatarBase ?? UIColor(color.fill)) : UIColor(color.fill))
    }

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
            ScrollViewReader { scroll in
                ScrollView {
                    Group {
                        switch page {
                        case .home: home(mascotHeight: viewport.size.height * 0.48)
                        case .learn: learn(scroll: scroll)
                        case .friends: friends
                        }
                    }
                    .padding(.horizontal, page == .home ? 0 : 22)
                    .padding(.top, page == .home ? 0 : 18)
                    .padding(.bottom, 28)
                }
                .defaultScrollAnchor(.top)
                .id(page)
            }
        }
        .foregroundStyle(ink)
        .background(palette.paper.ignoresSafeArea())
        .tint(palette.accent)
        .onChange(of: photo, initial: true) { _, data in
            avatarBase = MascotPalette.baseColour(photo: data)
        }
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
                MascotEditor(name: $name, color: $color, matchAvatarPalette: $matchAvatarPalette,
                             personality: $personality,
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
        .environment(\.mascotPalette, palette)
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
        HStack(spacing: 4) {
            ForEach(Page.allCases, id: \.self) { item in
                let isCurrent = page == item
                Button { page = item } label: {
                    HStack(spacing: 7) {
                        Image(systemName: item.icon).font(.system(size: 16, weight: .medium))
                        Text(item.rawValue).font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(isCurrent ? palette.accent : muted)
                    .background(isCurrent ? palette.panel : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 7)
        .background(palette.paper)
        .overlay(alignment: .top) { Rectangle().fill(palette.rule).frame(height: 1) }
        .changeEffect(.feedbackHapticSelection, value: page)
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

    /// Practised yesterday or today.
    private var usedRecently: Bool {
        let today = calendar.startOfDay(for: day)
        return practiceDays.contains(today) || practiceDays.contains(offset(-1, from: today))
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
        VStack(alignment: .leading, spacing: 0) {
            homeHeader
            MascotStage(mascot: pet(), active: usedRecently, fullBleed: true)
                .frame(height: mascotHeight)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Today").font(.system(.title, design: .serif, weight: .semibold))
                        Spacer()
                        Text(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.subheadline).foregroundStyle(muted)
                    }
                    ForEach(Array(dailyLessons.enumerated()), id: \.element.id) { index, lesson in
                        challenge(lesson, key: "daily-\(dateKey(day))-\(lesson.id)", primary: index == 0)
                    }
                }
                Divider()
                reviewSection
                Divider()
                streakBoard
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Challenge of the month").font(.system(.title2, design: .serif, weight: .semibold))
                    monthlyQuest
                }
            }
            .padding(.horizontal, 22).padding(.top, 20)
        }
    }

    private var homeHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(petName).font(.system(.largeTitle, design: .serif, weight: .semibold))
                Text(mood).font(.subheadline).foregroundStyle(muted)
            }
            Spacer(minLength: 8)
            Button { sheet = .setup } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 19, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.accent)
            .accessibilityLabel("Customize mascot")
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 9)
        .background(palette.stage)
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
                        Image(systemName: "arrow.clockwise").foregroundStyle(palette.accent)
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
                Label("Learning streak", systemImage: "flame.fill").foregroundStyle(palette.accent)
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
            HStack(alignment: .center, spacing: 15) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(primary ? "Challenge of the day" : "Bonus practice")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(primary ? .white.opacity(0.85) : muted)
                    Text(lesson.title)
                        .font(primary ? .system(.title2, design: .serif, weight: .semibold) : .headline)
                        .multilineTextAlignment(.leading)
                    if primary || done {
                        Text(done ? "Completed · Review" : "\(lesson.questions.count) questions")
                            .font(.subheadline)
                            .foregroundStyle(primary ? .white.opacity(0.85) : muted)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: done ? "checkmark.circle" : (primary ? "play.fill" : "chevron.right"))
                    .font(.system(size: primary ? 15 : 12, weight: .semibold))
                    .frame(width: primary ? 42 : 20, height: 36)
                    .background(primary ? .white.opacity(0.12) : .clear, in: Circle())
                    .accessibilityHidden(true)
            }
            .foregroundStyle(primary ? .white : ink)
            .padding(.vertical, primary ? 17 : 7)
            .padding(.horizontal, primary ? 17 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(primary ? palette.accent : .clear, in: RoundedRectangle(cornerRadius: 13))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var monthlyQuest: some View {
        let month = attempts.values.filter { calendar.isDate($0.date, equalTo: day, toGranularity: .month) }
        let byDay = Dictionary(grouping: month, by: { calendar.startOfDay(for: $0.date) })
        let mostInOneDay = byDay.values.map(\.count).max() ?? 0
        let perfectLessons = Set(month.filter { $0.score == $0.questions }.map(\.lessonID)).count
        let exercises = month.reduce(0) { $0 + $1.questions }
        let goalsMet = [mostInOneDay >= 3, perfectLessons >= 2, exercises >= 25].filter { $0 }.count
        return VStack(alignment: .leading, spacing: 0) {
            // An inline expansion keeps the monthly details paired with their summary.
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
                    monthlyExpanded.toggle()
                }
            } label: {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(day.formatted(.dateTime.month(.wide))).font(.headline)
                        Text("\(goalsMet) of 3 goals complete")
                            .font(.subheadline).foregroundStyle(muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .rotationEffect(.degrees(monthlyExpanded ? 180 : 0))
                        .foregroundStyle(palette.accent)
                }.padding(15).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(monthlyExpanded ? "Collapses monthly goals" : "Shows monthly goals")

            if monthlyExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Divider()
                    questRow("Finish 3 different lessons in one day", mostInOneDay, 3)
                    questRow("Get a perfect score on 2 lessons", perfectLessons, 2)
                    questRow("Complete 25 questions", exercises, 25)
                    Button("Browse lessons") { page = .learn }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(palette.accent)
                        .padding(.vertical, 4)
                }
                .padding(.horizontal, 15).padding(.bottom, 12)
                .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func questRow(_ title: String, _ value: Int, _ target: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text("\(min(value, target))/\(target)").bold()
            }.font(.footnote)
            Meter(progress: Double(value) / Double(target), background: palette.rule)
        }
    }

    private func learn(scroll: ScrollViewProxy) -> some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                heading("Learn")
                Label("\(streak)", systemImage: "flame.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(muted)
                pet().frame(width: 58).clipped()
            }
            topicStrip(scroll: scroll)
            reviewSection
            Divider()
            ForEach(LessonLibrary.units, id: \.title) { unit in
                unitPath(unit).id(unit.title)
            }
        }
    }

    private func topicStrip(scroll: ScrollViewProxy) -> some View {
        let topicNames = ["Investing", "TFSA", "RRSP", "First home", "Credit", "Planning"]
        return ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(Array(LessonLibrary.units.enumerated()), id: \.element.title) { index, unit in
                    let active = (focusedUnit ?? LessonLibrary.units.first?.title) == unit.title
                    Button {
                        focusedUnit = unit.title
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.27)) {
                            scroll.scrollTo(unit.title, anchor: .top)
                        }
                    } label: {
                        Text(topicNames.indices.contains(index) ? topicNames[index] : unit.title)
                            .font(.subheadline.weight(active ? .semibold : .medium))
                            .foregroundStyle(active ? .white : palette.accent)
                            .padding(.horizontal, 13).frame(minHeight: 42)
                            .background(active ? palette.accent : palette.panel, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(unit.title)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }.scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .changeEffect(.feedbackHapticSelection, value: focusedUnit)
        .accessibilityLabel("Jump to a topic")
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
                Meter(progress: Double(count) / Double(unit.lessons.count), background: palette.panel)
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
                Rectangle().fill(palette.rule).frame(width: 1).padding(.leading, 13).padding(.vertical, 24)
            }
            Divider()
        }
    }

    private func pathNode(done: Bool, current: Bool) -> some View {
        Image(systemName: done ? "checkmark" : (current ? "book.closed" : "circle.fill"))
            .font(.system(size: done || current ? 11 : 4, weight: .semibold))
            .foregroundStyle(current ? .white : palette.accent)
            .frame(width: 27, height: 27)
            .background(current ? palette.accent : (done ? palette.panel : palette.paper), in: Circle())
            .overlay { Circle().strokeBorder(current ? .clear : palette.rule) }
            .accessibilityHidden(true)
    }

    private var allFriends: [(name: String, days: Int, ready: Bool, color: PetColor)] {
        [("Priya", 21, true, .berry), ("Sam", 9, true, .sunny), ("Jordan", 5, false, .sky)] +
        extraFriends.split(separator: "|").map { (String($0), 0, false, .leaf) }
    }

    private var friends: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                heading("Friends")
                Button {
                    invite = true
                } label: {
                    Label("Invite", systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(palette.panel, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).foregroundStyle(palette.accent)
                Menu {
                    Button("Log out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { auth.logOut() }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                        .foregroundStyle(palette.accent)
                }.accessibilityLabel("Account options")
            }
            Text("Shared streaks")
                .font(.system(.title2, design: .serif, weight: .semibold))
            VStack(spacing: 0) {
                ForEach(allFriends, id: \.name) { friend in
                    friendRow(name: friend.name, days: friend.days, ready: friend.ready, color: friend.color)
                    Divider()
                }
            }
            Button {
                invite = true
            } label: {
                Label("Start a shared streak", systemImage: "plus")
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(palette.accent)
        }
    }

    private func friendRow(name: String, days: Int, ready: Bool, color: PetColor) -> some View {
        let checked = checkins.split(separator: "|").contains(Substring(name))
        return HStack(spacing: 12) {
            Pet(color: color).frame(width: 50, height: 50)
                .background(palette.panel, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                Text(checked ? "You checked in" : (ready ? "Your turn" : "Waiting for a check-in"))
                    .font(.footnote).foregroundStyle(muted)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 5) {
                Label("\(days + (checked && ready ? 1 : 0))", systemImage: "flame.fill")
                    .font(.footnote.monospacedDigit().weight(.semibold)).foregroundStyle(muted)
                Button {
                    checkins += checkins.isEmpty ? name : "|" + name
                } label: {
                    Text(checked ? "Done" : "Check in").font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).frame(minHeight: 32)
                        .background(palette.panel, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).foregroundStyle(palette.accent).disabled(checked)
                .changeEffect(.feedback(hapticNotification: .success), value: checked, isEnabled: checked)
            }
        }.padding(.vertical, 10)
    }
}
