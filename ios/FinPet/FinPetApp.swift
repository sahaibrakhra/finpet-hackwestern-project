import SwiftUI
import PhotosUI

struct Entry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var title: String
    var amount: Double
    var category: Category
    var region: String
}

enum Category: String, CaseIterable, Codable {
    case needs = "Needs", wants = "Wants", savings = "Savings/Investments"
}

struct ProgressRecord: Codable {
    var level: Int
    var due: Date
}

struct Profile: Codable {
    var name = ""
    var mascot = "🐱"
    var personality = "Just Tryna Be Normal"
    var portrait: Data?
    var goal = 0.0
    var income: Double?
    var fixed: Double?
    var entries: [Entry] = []
    var xp = 0
    var treats = 0
    var fedTreats = 0
    var checkIns: [Date] = []
    var lessons: [String: ProgressRecord] = [:]
    var requests: [String] = []
    var confidence: [Confidence] = []
    var rewardedWeeks: [Date] = []

    var saved: Double {
        entries.filter { $0.category == .savings }.reduce(0) { $0 + $1.amount }
    }

    var weeklyBudget: Double? {
        guard let income, let fixed else { return nil }
        return max(0, (income - fixed) * 12 / 52)
    }

    var weeklySpending: Double {
        entries.filter {
            $0.category == .wants && Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear)
        }.reduce(0) { $0 + $1.amount }
    }

    var overBudget: Bool {
        guard let weeklyBudget else { return false }
        return weeklySpending > weeklyBudget
    }

    var streak: Int {
        let calendar = Calendar.current
        let days = Set(checkIns.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: .now)
        var cursor = days.contains(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    mutating func checkIn() {
        let calendar = Calendar.current
        if let budget = weeklyBudget,
           let currentWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start,
           let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeek),
           !rewardedWeeks.contains(lastWeek) {
            let logged = entries.filter { $0.date >= lastWeek && $0.date < currentWeek }
            let wants = logged.filter { $0.category == .wants }.reduce(0) { $0 + $1.amount }
            if !logged.isEmpty && wants <= budget {
                rewardedWeeks.append(lastWeek)
                xp += 5
                treats += 1
            }
        }
        if !checkIns.contains(where: { Calendar.current.isDateInToday($0) }) {
            checkIns.append(.now)
            if streak.isMultiple(of: 3) { treats += 1 }
        }
    }

    mutating func add(_ entry: Entry) {
        let previousSaved = saved
        entries.append(entry)
        checkIn()
        if goal > 0 && previousSaved < goal && saved >= goal { xp += 25; treats += 1 }

    }
}

struct Confidence: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var rating: Int
}

func money(_ value: Double) -> String {
    value.formatted(.currency(code: "CAD"))
}

@main
struct FinPetApp: App {
    @AppStorage("finpet-profile-v1") private var stored = Data()
    @State private var profile = Profile()

    var body: some Scene {
        WindowGroup {
            TabView {
                Dashboard(profile: $profile)
                    .tabItem { Label("Home", systemImage: "house") }
                LessonsView(profile: $profile)
                    .tabItem { Label("Learn", systemImage: "book") }
                MoneyView(profile: $profile)
                    .tabItem { Label("Money", systemImage: "wallet.bifold") }
                TrendsView(profile: $profile)
                    .tabItem { Label("Trends", systemImage: "chart.bar") }
            }
            .tint(Color(red: 0.23, green: 0.39, blue: 0.27))
            .onAppear {
                if let saved = try? JSONDecoder().decode(Profile.self, from: stored) { profile = saved }
            }
            .onChange(of: encodedProfile) { _, value in
                if let value { stored = value }
            }
        }
    }

    private var encodedProfile: Data? { try? JSONEncoder().encode(profile) }
}

struct Dashboard: View {
    @Binding var profile: Profile
    @State private var editing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 12) {
                        if let data = profile.portrait, let photo = UIImage(data: data) {
                            Image(uiImage: photo).resizable().scaledToFill()
                                .frame(width: 132, height: 132).clipShape(.circle)
                        } else {
                            Text(profile.mascot).font(.system(size: 92))
                                .accessibilityLabel("Mascot")
                        }
                        Text(profile.name.isEmpty ? "Meet your FinPet" : profile.name)
                            .font(.largeTitle.bold())
                        Label(profile.overBudget ? "Taking a breather" : "Ready to go",
                              systemImage: profile.overBudget ? "heart" : "sun.max")
                            .font(.subheadline.weight(.medium))
                        Text(message).multilineTextAlignment(.center)
                        Button(profile.name.isEmpty ? "Set up mascot" : "Customize mascot") { editing = true }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background((profile.overBudget ? Color.orange : Color.green).opacity(0.12), in: RoundedRectangle(cornerRadius: 28))

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Emergency shield", systemImage: "shield.lefthalf.filled").font(.headline)
                        if profile.goal > 0 {
                            ProgressView(value: min(1, profile.saved / profile.goal))
                            Text("\(money(profile.saved)) of \(money(profile.goal))")
                        } else {
                            Text("Set a goal in Money to fill your shield.").foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Label("\(profile.xp) XP", systemImage: "sparkle")
                        Spacer()
                        Label("\(profile.streak) day streak", systemImage: "flame")
                    }
                    Button("Feed a treat (\(profile.treats) available)") {
                        profile.treats -= 1
                        profile.fedTreats += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(profile.treats == 0)
                    Button("Check in today") { profile.checkIn() }
                        .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("FinPet")
            .sheet(isPresented: $editing) { MascotSetup(profile: $profile) }
        }
    }

    private var message: String {
        if profile.name.isEmpty { return "Pick a companion for your money journey." }
        let openings = [
            "Vigilante": "Money mission update.", "Evil": "A devious little update.",
            "Just Tryna Be Normal": "Quick check-in.", "Hype Friend": "Hey, team!",
            "Quiet Coach": "A moment to check in."
        ]
        let opening = openings[profile.personality] ?? "Quick check-in."
        if let budget = profile.weeklyBudget, profile.weeklySpending > budget {
            return opening + " Wants are \(money(profile.weeklySpending - budget)) above your weekly plan. Review one recent purchase when you have a moment."
        }
        if let last = profile.entries.last {
            return opening + " You logged \(money(last.amount)) for \(last.title). " +
                (last.category == .savings ? "Your emergency savings are now \(money(profile.saved))." :
                    "This week's wants total \(money(profile.weeklySpending)).")
        }
        return opening + " One short lesson is enough to start."
    }
}

struct MascotSetup: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var profile: Profile
    @State private var selection: PhotosPickerItem?
    @State private var imageStatus = ""
    private let personalities = ["Vigilante", "Evil", "Just Tryna Be Normal", "Hype Friend", "Quiet Coach"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Mascot name", text: $profile.name)
                Picker("Mascot", selection: $profile.mascot) {
                    ForEach(["🐱", "🐸", "🦊", "🐧", "🐻"], id: \.self) { Text($0) }
                }
                Picker("Personality", selection: $profile.personality) {
                    ForEach(personalities, id: \.self) { Text($0) }
                }
                PhotosPicker("Upload your own picture", selection: $selection, matching: .images)
                if profile.portrait != nil {
                    Button("Use built-in mascot", role: .destructive) { profile.portrait = nil }
                }
                if !imageStatus.isEmpty { Text(imageStatus).foregroundStyle(.secondary) }
                Text("AI-animated video requires a generation provider. Uploaded portraits appear immediately as still images.")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Your mascot")
            .toolbar { Button("Done") { dismiss() } }
            .task(id: selection) {
                guard let selection else { return }
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self),
                          let image = UIImage(data: data), !Task.isCancelled else { return }
                    let scale = min(1, 600 / max(image.size.width, image.size.height))
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    let thumbnail = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                    profile.portrait = thumbnail.jpegData(compressionQuality: 0.8)
                    imageStatus = "Portrait ready."
                } catch {
                    if !Task.isCancelled { imageStatus = "Could not open that image. Try another." }
                }
            }
        }
    }
}
