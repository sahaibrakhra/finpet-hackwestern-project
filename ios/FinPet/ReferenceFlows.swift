import SwiftUI
import PhotosUI

struct MascotEditor: View {
    @Environment(\.mascotPalette) private var palette
    @Binding var name: String
    @Binding var color: PetColor
    @Binding var matchAvatarPalette: Bool
    @Binding var personality: String
    @Binding var photo: Data
    let close: () -> Void
    @State private var selection: PhotosPickerItem?
    @State private var photoError = false
    @FocusState private var editingName: Bool
    @State private var originalPhoto = Data()
    @State private var generating = false
    @State private var aiError: String?
    @State private var previewMood: PetMood = .idle
    @State private var confirmRedo = false
    private var library: AvatarLibrary { AvatarLibrary.shared }

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
                VStack(spacing: 5) {
                    Pet(color: color, photo: photo.isEmpty ? nil : photo, mood: previewMood)
                        .frame(width: photo.isEmpty ? 140 : 190)
                        .opacity(generating ? 0.35 : 1)
                        .overlay { if generating { ProgressView() } }
                    Text(petName).font(.title2.weight(.heavy))
                    Text("“\(sample)”").font(.subheadline).foregroundStyle(muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(16)
                .background(palette.stage, in: RoundedRectangle(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                controls
            }.padding(20)
        }
        .foregroundStyle(ink).background(palette.paper.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Customize mascot").font(.headline)
                Spacer()
                Button("Close") {
                    editingName = false
                    name = petName
                    close()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, 20)
            .background(palette.paper)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
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
            if !Task.isCancelled {
                let entry = library.create(avatarPNG: avatar.png, background: avatar.background)
                photo = avatar.png
                previewMood = .idle
                library.generateMissingAnimations(for: entry.id)
            }
        } catch {
            if !Task.isCancelled { aiError = error.localizedDescription }
        }
    }

    private var controls: some View {
        Group {
            fieldLabel("Name")
            TextField("Mascot name", text: $name)
                .focused($editingName)
                .submitLabel(.done)
                .onSubmit { editingName = false }
                .padding(11).background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(line).allowsHitTesting(false) }
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
                Button("Use illustrated mascot") { photo = Data(); originalPhoto = Data(); selection = nil; aiError = nil; library.setActive(nil) }
                    .font(.footnote).foregroundStyle(forest)
            }
            if let id = library.activeID { animationsCard(id) }
            if !library.entries.isEmpty { avatarPicker }
            fieldLabel(photo.isEmpty ? "Mascot colour" : "Backdrop colour")
            if !photo.isEmpty {
                Button {
                    matchAvatarPalette = true
                } label: {
                    Label("Match mascot", systemImage: matchAvatarPalette ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(palette.accent)
                }
            }
            HStack {
                ForEach(PetColor.allCases, id: \.self) { item in
                    Button {
                        color = item
                        if !photo.isEmpty { matchAvatarPalette = false }
                    } label: {
                        let selected = color == item && (photo.isEmpty || !matchAvatarPalette)
                        VStack(spacing: 5) {
                            Circle().fill(item.fill).frame(width: 31, height: 31).padding(3)
                                .overlay { Circle().strokeBorder(selected ? ink : line, lineWidth: 2) }
                            Text(item.rawValue).font(.caption.weight(selected ? .bold : .regular))
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }
            }
            fieldLabel("Personality")
            options(profiles, selected: $personality)
        }
    }

    /// Per-animation status for the active avatar, with a preview chip once each clip is saved.
    private func animationsCard(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Animations").font(.subheadline.bold())
            HStack(spacing: 8) {
                ForEach(PetMood.allCases, id: \.self) { mood in
                    let state = library.state(id, mood)
                    Button {
                        if library.hasAnimation(id, mood) { previewMood = mood }
                    } label: {
                        VStack(spacing: 4) {
                            Group {
                                switch state {
                                case .done: Image(systemName: previewMood == mood ? "play.circle.fill" : "play.circle")
                                case .running: ProgressView()
                                case .failed: Image(systemName: "exclamationmark.triangle")
                                case nil: Image(systemName: "circle.dashed")
                                }
                            }.frame(height: 22)
                            Text(mood.title).font(.caption.weight(previewMood == mood ? .bold : .regular))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(previewMood == mood && library.hasAnimation(id, mood) ? mint : .white, in: RoundedRectangle(cornerRadius: 11))
                        .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(line) }
                    }.buttonStyle(.plain).disabled(!library.hasAnimation(id, mood))
                }
            }
            if let failure = PetMood.allCases.compactMap({ mood -> String? in
                if case .failed(let message)? = library.state(id, mood) { return message }
                return nil
            }).first {
                Text(failure).font(.footnote).foregroundStyle(.red)
            }
            if !library.missingAnimations(id).isEmpty && !PetMood.allCases.contains(where: { library.state(id, $0) == .running }) {
                Button { library.generateMissingAnimations(for: id) } label: {
                    Label("Create missing animations", systemImage: "arrow.clockwise")
                }.font(.subheadline.bold()).foregroundStyle(forest)
            }
            if library.hasAnimation(id, .wave) && library.hasAnimation(id, .dance) && !library.isGenerating(id) {
                Button { confirmRedo = true } label: {
                    Label("Redo wave & dance (wider frame)", systemImage: "arrow.triangle.2.circlepath")
                }
                .font(.subheadline.bold()).foregroundStyle(forest)
                .confirmationDialog("Re-create the wave and dance animations?", isPresented: $confirmRedo, titleVisibility: .visible) {
                    Button("Redo both (2 paid video calls, about $0.14)") {
                        library.regenerateAnimations([.wave, .dance], for: id)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your current clips keep playing until the new ones are ready. The avatar itself is not re-created.")
                }
            }
            Text("Saved on this phone, so switching avatars never re-creates them.")
                .font(.caption2).foregroundStyle(muted)
        }.petCard()
    }

    /// Previously created avatars. Switching only loads what is already saved on the phone.
    private var avatarPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("My avatars")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(library.entries) { entry in
                        Button {
                            if let data = library.avatarData(entry.id) {
                                library.setActive(entry.id)
                                photo = data
                                previewMood = .idle
                            }
                        } label: {
                            Group {
                                if let data = library.avatarData(entry.id), let image = UIImage(data: data) {
                                    Image(uiImage: image).resizable().scaledToFit()
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: 54, height: 78).padding(6)
                            .background(Color(hex: entry.background) ?? mint, in: RoundedRectangle(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(library.activeID == entry.id ? forest : line,
                                                  lineWidth: library.activeID == entry.id ? 3 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete avatar", role: .destructive) {
                                let wasActive = library.activeID == entry.id
                                library.delete(entry.id)
                                if wasActive { photo = Data() }
                            }
                        }
                    }
                }
            }
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
