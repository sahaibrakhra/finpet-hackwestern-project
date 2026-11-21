import SwiftUI
import PhotosUI

struct MascotEditor: View {
    @Binding var name: String
    @Binding var color: PetColor
    @Binding var accessory: String
    @Binding var personality: String
    @Binding var photo: Data
    let close: () -> Void
    @State private var selection: PhotosPickerItem?
    @State private var photoError = false
    @State private var step = 1
    @State private var originalPhoto = Data()
    @State private var generating = false
    @State private var aiError: String?

    private var petName: String { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Loonie" : name }
    private let profiles = ["Just tryna be normal", "Hype bestie", "Vigilante", "Evil", "Quiet coach"]
    private var sample: String {
        switch personality {
        case "Hype bestie": "We’ve got this. One tiny money win today?"
        case "Vigilante": "Mission update. Let’s investigate that spending spike."
        case "Evil": "My brilliant plan? A tiny emergency fund."
        case "Quiet coach": "Let’s take a moment and see what changed."
        default: "We went $14 over. Totally normal. Tiny plan?"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("Step \(step) of 2").font(.subheadline.bold()).foregroundStyle(muted)
                    Capsule().fill(forest).frame(height: 6)
                    Capsule().fill(step == 2 ? forest : line).frame(height: 6)
                }
                Text(step == 1 ? "Make it yours" : "Meet \(petName)").font(.system(size: 31, weight: .heavy))
                VStack(spacing: 5) {
                    Pet(color: color, accessory: accessory, photo: photo.isEmpty ? nil : photo).frame(width: 140)
                        .opacity(generating ? 0.35 : 1)
                        .overlay { if generating { ProgressView() } }
                    Text(petName).font(.title2.weight(.heavy))
                    Text("“\(sample)”").font(.subheadline).foregroundStyle(muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(16)
                .background(mint, in: RoundedRectangle(cornerRadius: 22))
                if step == 1 { controls }
            }.padding(20)
        }
        .foregroundStyle(ink).background(cream.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                ActionButton(title: step == 1 ? "Start with \(petName)" : "Go to Home") {
                    if step == 1 { step = 2 } else { close() }
                }
                if step == 2 {
                    Button("Back to customization") { step = 1 }.font(.subheadline).foregroundStyle(forest)
                }
            }.padding(.horizontal, 20).padding(.vertical, 8).background(cream)
        }
        .task(id: selection) {
            guard let selection else { return }
            do {
                guard let data = try await selection.loadTransferable(type: Data.self),
                      let image = UIImage(data: data), !Task.isCancelled else { return }
                let scale = min(1, 1024 / max(image.size.width, image.size.height))
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                originalPhoto = resized.jpegData(compressionQuality: 0.8) ?? Data()
                photoError = originalPhoto.isEmpty
                if !photoError { await generateAvatar() }
            } catch {
                if !Task.isCancelled { photoError = true }
            }
        }
    }

    /// Generates a full-body avatar from the uploaded photo. On failure the previous mascot is kept.
    private func generateAvatar() async {
        guard !originalPhoto.isEmpty else { return }
        generating = true
        aiError = nil
        defer { generating = false }
        do {
            let avatar = try await MascotService().generateAvatar(from: originalPhoto)
            if !Task.isCancelled { photo = avatar }
        } catch {
            if !Task.isCancelled { aiError = error.localizedDescription }
        }
    }

    private var controls: some View {
        Group {
            HStack(spacing: 10) {
                Image(systemName: "camera").frame(width: 37, height: 37).background(mint, in: Circle())
                VStack(alignment: .leading) {
                    Text("Use your own photo").font(.subheadline.bold())
                    Text("A pet, plushie or doodle.").font(.caption).foregroundStyle(muted)
                }
                Spacer()
                PhotosPicker("Upload", selection: $selection, matching: .images)
                    .font(.subheadline.bold()).foregroundStyle(forest)
            }.petCard()
            if photoError { Text("That photo couldn’t be opened.").font(.footnote).foregroundStyle(muted) }
            VStack(alignment: .leading, spacing: 8) {
                if generating {
                    HStack(spacing: 8) { ProgressView(); Text("Creating your full-body avatar…").font(.footnote) }
                }
                if let aiError { Text(aiError).font(.footnote).foregroundStyle(.red) }
                if !originalPhoto.isEmpty && !generating {
                    Button { Task { await generateAvatar() } } label: {
                        Label(aiError == nil && !photo.isEmpty ? "Regenerate avatar" : "Try again", systemImage: "wand.and.stars")
                    }.font(.subheadline.bold()).foregroundStyle(forest)
                }
                Text("Your photo is sent to our server and Google's Gemini to generate the avatar.")
                    .font(.caption2).foregroundStyle(muted)
            }.petCard()
            if !photo.isEmpty {
                Button("Use illustrated mascot") { photo = Data(); originalPhoto = Data(); selection = nil; aiError = nil }
                    .font(.footnote).foregroundStyle(forest)
            }
            fieldLabel("Name")
            TextField("Loonie", text: $name).padding(11).background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(line) }
            fieldLabel("Colour")
            HStack {
                ForEach(PetColor.allCases, id: \.self) { item in
                    Button {
                        color = item
                    } label: {
                        VStack(spacing: 5) {
                            Circle().fill(item.fill).frame(width: 31, height: 31).padding(3)
                                .overlay { Circle().strokeBorder(color == item ? ink : line, lineWidth: 2) }
                            Text(item.rawValue).font(.caption.weight(color == item ? .bold : .regular))
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }
            }
            fieldLabel("Accessory")
            options(["None", "Scarf", "Toque", "Grad cap"], selected: $accessory)
            fieldLabel("Personality")
            options(profiles, selected: $personality)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(muted)
    }

    private func options(_ options: [String], selected: Binding<String>) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selected.wrappedValue = option
                    } label: {
                        Text(option).font(.caption.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(selected.wrappedValue == option ? mint : .white, in: RoundedRectangle(cornerRadius: 11))
                            .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(selected.wrappedValue == option ? forest : line) }
                    }.buttonStyle(.plain)
                }
            }
        }.scrollIndicators(.hidden)
    }
}

struct Quiz: View {
    let pet: Pet
    let completed: () -> Void
    let close: () -> Void
    @State private var index = 0
    @State private var selected: Int?
    @State private var checked = false
    private struct Question {
        var prompt: String
        var choices: [String]
        var correct: Int
        var feedback: String
    }
    private let questions = [
        Question(prompt: "My $1,000 in a TFSA grew to $1,200. How much Canadian tax do I generally owe on the $200?",
                 choices: ["$0", "About $30", "Depends on my income"], correct: 0,
                 feedback: "Growth inside a TFSA is generally tax-free in Canada."),
        Question(prompt: "A friend calls a TFSA a type of stock. What is it?",
                 choices: ["A Canadian stock", "A registered account", "A loan"], correct: 1,
                 feedback: "A TFSA is a registered account that can hold eligible investments."),
        Question(prompt: "I withdrew money from my TFSA this year. When is that amount generally added back to my contribution room?",
                 choices: ["Immediately", "Never", "At the start of next year"], correct: 2,
                 feedback: "Withdrawals generally create new room the following calendar year.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Button(action: close) { Image(systemName: "xmark").font(.title3) }.accessibilityLabel("Close lesson")
                    ForEach(questions.indices, id: \.self) { step in
                        Capsule().fill(step <= index ? PetColor.leaf.fill : line).frame(height: 6)
                    }
                    Text("\(index + 1)/\(questions.count)").font(.subheadline.bold())
                }.foregroundStyle(muted)
                Text("TFSA basics · Question \(index + 1) of \(questions.count)")
                    .font(.subheadline.bold()).foregroundStyle(muted)
                HStack(alignment: .bottom, spacing: 8) {
                    pet.frame(width: 94)
                    Text(questions[index].prompt).font(.title3.weight(.heavy)).petCard()
                }
                ForEach(questions[index].choices.indices, id: \.self) { option in
                    Button {
                        selected = option
                    } label: {
                        HStack {
                            Image(systemName: selected == option ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(forest).font(.title2)
                            Text(questions[index].choices[option]).font(.headline)
                            Spacer()
                        }.petCard(selected == option ? mint : .white, radius: 16)
                    }.buttonStyle(.plain).disabled(checked)
                }
                if checked {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selected == questions[index].correct ? "You got it!" : "Here’s how it works").font(.headline)
                        Text(questions[index].feedback).font(.subheadline)
                    }.petCard(mint)
                }
            }.padding(20)
        }
        .foregroundStyle(ink).background(cream.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            ActionButton(title: checked ? (index == questions.count - 1 ? "Finish lesson" : "Continue") : "Check",
                         secondary: selected == nil) {
                guard selected != nil else { return }
                if !checked { checked = true }
                else if index == questions.count - 1 { completed() }
                else { index += 1; selected = nil; checked = false }
            }
            .disabled(selected == nil)
            .padding(.horizontal, 20).padding(.vertical, 8).background(cream)
        }
    }
}
