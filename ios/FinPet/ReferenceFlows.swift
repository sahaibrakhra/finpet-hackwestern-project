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
        case "Hype bestie": "We’ve got this. One tiny learning win today?"
        case "Vigilante": "Mission update. Let’s investigate compound growth."
        case "Evil": "My brilliant plan? Mastering compound interest."
        case "Quiet coach": "Let’s unpack one new idea."
        default: "I’m pondering what we’ll learn today."
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
