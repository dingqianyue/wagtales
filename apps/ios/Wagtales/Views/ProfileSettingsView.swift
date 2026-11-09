import SwiftUI
import Supabase
import PhotosUI

// This struct packages up the data to send to Supabase
// Keys need to match database table columns exactly
struct ProfileUpdate: Codable {
    let full_name: String
    let username: String
    let bio: String
    let education: String
    let workplace: String
    let avatar_url: String?
}

struct ProfileSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("isAuthenticated") var isAuthenticated: Bool = false
    
    var onSave: (String, String, String, String, String, String?) -> Void
    
    @State var name: String
    @State var username: String
    @State var bio: String
    @State var education: String
    @State var workplace: String
    @State var avatarUrl: String?
    
    // Photo picker state variables
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarData: Data?
    
    @State private var isSaving = false
    
    // Preferences and security logic
    @State private var pushNotifications = true
    @State private var defaultPrivacy = "Ghost Mode"
    let privacyOptions = ["Ghost Mode", "Mutuals (Fuzzy)", "Mutuals (Exact)"]
    
    @State private var errorMessage: String?

    // Username change limit (also enforced by the database)
    @State private var originalUsername: String?
    @State private var lastUsernameChangeDate: Date?
    @State private var isLoadingUsernameLock = true
    let daysUntilUnlock = 30

    var usernameUnlockDate: Date? {
        guard let lastChange = lastUsernameChangeDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: daysUntilUnlock, to: lastChange)
    }

    var canChangeUsername: Bool {
        guard let unlockDate = usernameUnlockDate else { return true }
        return Date() >= unlockDate
    }

    var daysRemaining: Int {
        guard let unlockDate = usernameUnlockDate else { return 0 }
        let seconds = unlockDate.timeIntervalSinceNow
        return max(0, Int((seconds / 86_400).rounded(.up)))
    }

    var usernameChanged: Bool {
        username != (originalUsername ?? username)
    }

    // Same rules as sign-up: starts with a lowercase letter, then lowercase letters, numbers, or underscores
    var isUsernameValid: Bool {
        guard let firstChar = username.first else { return false }
        let startingCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        if String(firstChar).rangeOfCharacter(from: startingCharacters.inverted) != nil {
            return false
        }
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        return username.rangeOfCharacter(from: allowedCharacters.inverted) == nil
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Photo section
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            VStack(spacing: 8) {
                                if let avatarData, let uiImage = UIImage(data: avatarData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                } else if let photoUrlString = avatarUrl, let url = URL(string: photoUrlString) {
                                    AsyncImage(url: url) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        ProgressView()
                                    }
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 80))
                                        .foregroundColor(.regalBlue)
                                }
                                
                                Text("Edit profile photo")
                                    .font(.caption)
                                    .foregroundColor(.regalBlue)
                            }
                        }
                        .buttonStyle(.borderless)
                        .onChange(of: avatarItem) { oldValue, newValue in
                            Task {
                                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                    avatarData = data
                                }
                            }
                        }
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
                
                Section(header: Text("Personal Info")) {
                    TextField("Full Name", text: $name)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("@").foregroundColor(.secondary)
                            TextField("Username", text: $username)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .disabled(isLoadingUsernameLock || !canChangeUsername)
                                .onChange(of: username) { _, newValue in
                                    username = newValue.lowercased().replacingOccurrences(of: " ", with: "_")
                                }
                        }
                        if !canChangeUsername {
                            Text("You changed your username recently. You can change it again in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s").").font(.caption).foregroundColor(.red)
                        } else if usernameChanged && !isUsernameValid {
                            Text("Usernames must start with a letter and can only contain lowercase letters, numbers, and underscores.").font(.caption).foregroundColor(.red)
                        } else {
                            Text("Usernames must be unique and can only be changed once every 30 days.").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.caption).foregroundColor(.red)
                    }
                }

                Section(header: Text("Public Profile (Optional)"), footer: Text("This information appears on your public dashboard.")) {
                    TextField("Bio", text: $bio, axis: .vertical).lineLimit(1...3)
                    HStack { Image(systemName: "graduationcap.fill").foregroundColor(.secondary).frame(width: 20); TextField("Education", text: $education) }
                    HStack { Image(systemName: "building.2.fill").foregroundColor(.secondary).frame(width: 20); TextField("Workplace", text: $workplace) }
                }
                
                Section(header: Text("Preferences")) {
                    Toggle("Push Notifications", isOn: $pushNotifications).tint(.regalBlue)
                    Picker("Default Map Privacy", selection: $defaultPrivacy) { ForEach(privacyOptions, id: \.self) { option in Text(option).tag(option) } }
                }
                
                // Danger zone (log out logic)
                Section {
                    Button(action: {
                        Task {
                            do {
                                // Destroy the session in Supabase
                                try await supabase.auth.signOut()
                                // Kick the user back to the login screen
                                await MainActor.run {
                                    isAuthenticated = false
                                    dismiss()
                                }
                            } catch {
                                print("Error logging out: \(error.localizedDescription)")
                            }
                        }
                    }) {
                        Text("Log Out")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    
                    Button(action: { print("Delete account tapped") }) {
                        Text("Delete Account")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.primary)
                }
                // Save button (database logic)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task { await saveProfileToDatabase() }
                    }) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save").bold().foregroundColor(.regalBlue)
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || username.trimmingCharacters(in: .whitespaces).isEmpty || (usernameChanged && !isUsernameValid) || isSaving)
                }
            }
            .task { await loadUsernameChangeDate() }
        }
    }

    // MARK: - Database Logic
    private func loadUsernameChangeDate() async {
        if originalUsername == nil { originalUsername = username }

        struct UsernameChange: Decodable { let username_changed_at: Date? }
        do {
            let userId = try await supabase.auth.session.user.id
            let row: UsernameChange = try await supabase
                .from("profiles")
                .select("username_changed_at")
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            lastUsernameChangeDate = row.username_changed_at
        } catch {
            print("Failed to load username change date: \(error.localizedDescription)")
        }
        isLoadingUsernameLock = false
    }

    private func saveProfileToDatabase() async {
        isSaving = true
        errorMessage = nil

        do {
            // Get the current securely logged-in user ID
            let user = try await supabase.auth.session.user
            var finalAvatarUrl = avatarUrl
            
            // Check if a new image was picked and compress it
            if let rawData = avatarData, let compressedData = ImageCompressor.compress(data: rawData, maxDimension: 500, compressionQuality: 0.6) {
                
                // Delete old avatar from storage if it exists to save space
                if let oldPhotoUrlString = avatarUrl, let oldUrl = URL(string: oldPhotoUrlString) {
                    // Extract the "userId/filename.jpg" portion from the full URL to pass to the remove function
                    let oldPath = "\(user.id)/\(oldUrl.lastPathComponent)"
                    try? await supabase.storage.from("avatars").remove(paths: [oldPath])
                }
                
                // Upload the new, compressed image
                let fileName = "\(user.id)/\(UUID().uuidString).jpg"
                try await supabase.storage
                    .from("avatars")
                    .upload(
                        path: fileName,
                        file: compressedData,
                        options: FileOptions(contentType: "image/jpeg")
                    )
                
                finalAvatarUrl = try await supabase.storage.from("avatars").getPublicURL(path: fileName).absoluteString
            }
            
            // Package up the text fields AND the final avatar URL
            let updateData = ProfileUpdate(
                full_name: name,
                username: username,
                bio: bio,
                education: education,
                workplace: workplace,
                avatar_url: finalAvatarUrl
            )
            
            // Update Postgres
            try await supabase
                .from("profiles")
                .update(updateData)
                .eq("id", value: user.id)
                .execute()
            
            // Update the local UI and dismiss
            await MainActor.run {
                onSave(name, username, bio, education, workplace, finalAvatarUrl)
                isSaving = false
                dismiss()
            }
            
        } catch {
            print("Failed to save profile: \(error.localizedDescription)")
            await MainActor.run {
                if let dbError = error as? PostgrestError {
                    // 23505 = unique violation on profiles.username
                    errorMessage = dbError.code == "23505"
                        ? "That username is already taken. Please choose another."
                        : dbError.message
                } else {
                    errorMessage = "Couldn't save your profile. Please try again."
                }
                isSaving = false
            }
        }
    }
}
