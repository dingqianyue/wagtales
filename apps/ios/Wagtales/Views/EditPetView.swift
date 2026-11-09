import SwiftUI
import PhotosUI
import Supabase

struct EditPetView: View {
    @Environment(\.dismiss) var dismiss
    
    let pet: Pet
    var onSave: (Pet) -> Void
    var onDelete: () -> Void
    
    // Photo state
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarData: Data?
    
    // Text fields state
    @State private var name: String
    @State private var selectedSpecies: String
    @State private var customSpecies: String = ""
    
    // Gender state
    @State private var selectedGender: String
    
    // Breed state
    @State private var selectedBreed: String
    @State private var customBreed: String = ""
    
    // Personality state
    @State private var personality: String
    
    // Age state
    @State private var isExactBirthdayKnown: Bool
    @State private var exactDate: Date
    @State private var estimatedYears: Int
    @State private var estimatedMonths: Int
    // Tracks if we need to recalculate the estimated birthday
    @State private var hasModifiedAge = false
    
    @State private var isMemorial: Bool
    
    // Processing & error state
    @State private var isProcessing = false
    @State private var errorMessage = ""
    
    // Delete confirmation state
    @State private var showingLeaveAlert = false
    @State private var showingDeleteAlert = false
    
    let speciesOptions = ["Dog", "Cat", "Bird", "Snake", "Hamster", "Other"]
    let genderOptions = ["Male", "Female", "Unknown"]
    
    let breedOptions: [String: [String]] = [
        "Dog": ["Mixed/Rescue", "Golden Retriever", "Labrador", "French Bulldog", "Poodle", "German Shepherd", "Other"],
        "Cat": ["Domestic Shorthair", "Domestic Longhair", "Siamese", "Maine Coon", "Persian", "Other"],
        "Bird": ["Parakeet", "Cockatiel", "Parrot", "Canary", "Finch", "Other"],
        "Snake": ["Ball Python", "Corn Snake", "Kingsnake", "Boa Constrictor", "Other"],
        "Hamster": ["Syrian", "Dwarf", "Roborovski", "Other"]
    ]

    let mbtiOptions = [
        "Skip for now", "INTJ (Architect)", "INTP (Logician)", "ENTJ (Commander)", "ENTP (Debater)",
        "INFJ (Advocate)", "INFP (Mediator)", "ENFJ (Protagonist)", "ENFP (Campaigner)",
        "ISTJ (Logistician)", "ISFJ (Defender)", "ESTJ (Executive)", "ESFJ (Consul)",
        "ISTP (Virtuoso)", "ISFP (Adventurer)", "ESTP (Entrepreneur)", "ESFP (Entertainer)"
    ]
    
    init(pet: Pet, onSave: @escaping (Pet) -> Void, onDelete: @escaping () -> Void) {
        self.pet = pet
        self.onSave = onSave
        self.onDelete = onDelete
        
        // Pre-fill existing data
        _name = State(initialValue: pet.name)
        
        // Handle custom species
        let isStandardSpecies = ["Dog", "Cat", "Bird", "Snake", "Hamster"].contains(pet.species)
        _selectedSpecies = State(initialValue: isStandardSpecies ? pet.species : "Other")
        _customSpecies = State(initialValue: isStandardSpecies ? "" : pet.species)
        
        _selectedGender = State(initialValue: pet.gender ?? "Unknown")
        
        // Handle custom breeds safely
        let breedVal = pet.breed ?? ""
        let isStandardBreed = (breedOptions[pet.species] ?? []).contains(breedVal)
        _selectedBreed = State(initialValue: breedVal.isEmpty ? "Mixed/Rescue" : (isStandardBreed ? breedVal : "Other"))
        _customBreed = State(initialValue: isStandardBreed ? "" : breedVal)
        
        _personality = State(initialValue: pet.personality ?? "Skip for now")
        _isMemorial = State(initialValue: pet.isMemorial)
        
        // Calculate and populate exact date vs estimated age
        _isExactBirthdayKnown = State(initialValue: !pet.isBirthdayEstimated)
        
        var parsedDate = Date()
        var initYears = 2
        var initMonths = 0
        
        if let bdayStr = pet.birthday {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: bdayStr) {
                parsedDate = date
                
                // If it was estimated, reverse-calculate the years/months from the saved date to today
                if pet.isBirthdayEstimated {
                    let components = Calendar.current.dateComponents([.year, .month], from: date, to: Date())
                    initYears = max(0, components.year ?? 0)
                    initMonths = max(0, components.month ?? 0)
                }
            }
        }
        
        _exactDate = State(initialValue: parsedDate)
        _estimatedYears = State(initialValue: initYears)
        _estimatedMonths = State(initialValue: initMonths)
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
                                    Image(uiImage: uiImage).resizable().scaledToFill().frame(width: 100, height: 100).clipShape(Circle())
                                } else if let photoUrlString = pet.photoUrl, let url = URL(string: photoUrlString) {
                                    AsyncImage(url: url) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        ProgressView()
                                    }.frame(width: 100, height: 100).clipShape(Circle())
                                } else {
                                    Image(systemName: "camera.circle.fill").font(.system(size: 80)).foregroundColor(.regalBlue)
                                }
                                
                                Text("Edit pet profile photo")
                                    .font(.caption)
                                    .foregroundColor(.regalBlue)
                            }
                        }
                        .buttonStyle(.borderless) // Limit clickable area
                        
                        // iOS 17+ syntax
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
                
                // Basic Info
                Section(header: Text("Basic Info")) {
                    TextField("Pet's Name", text: $name)
                    
                    Picker("Species", selection: $selectedSpecies) {
                        ForEach(speciesOptions, id: \.self) { species in Text(species).tag(species) }
                    }
                    .onChange(of: selectedSpecies) { oldValue, newValue in
                        if let breeds = breedOptions[newValue], let first = breeds.first {
                            selectedBreed = first
                        } else {
                            selectedBreed = ""
                        }
                    }
                    
                    if selectedSpecies == "Other" {
                        TextField("Specify Species", text: $customSpecies)
                    }
                }
                
                // Optional details
                Section(header: Text("Details (Optional)")) {
                    Picker("Gender", selection: $selectedGender) {
                        ForEach(genderOptions, id: \.self) { option in Text(option).tag(option) }
                    }
                    
                    if selectedSpecies != "Other" {
                        Picker("Breed / Type", selection: $selectedBreed) {
                            ForEach(breedOptions[selectedSpecies] ?? [], id: \.self) { Text($0) }
                        }
                        if selectedBreed == "Other" { TextField("Specify Breed", text: $customBreed) }
                    }
                    
                    Picker("MBTI Type", selection: $personality) {
                        ForEach(mbtiOptions, id: \.self) { type in Text(type).tag(type) }
                    }
                }
                
                // Age & Birthday
                Section(header: Text("Age & Birthday")) {
                    Toggle("I know the exact birthday", isOn: $isExactBirthdayKnown).tint(.regalBlue)
                    
                    if isExactBirthdayKnown {
                        DatePicker("Birthday", selection: $exactDate, in: ...Date(), displayedComponents: .date)
                    } else {
                        Picker("Years old", selection: $estimatedYears) { ForEach(0..<31) { Text("\($0)").tag($0) } }
                            .onChange(of: estimatedYears) { oldValue, newValue in hasModifiedAge = true } // <-- NEW
                            
                        Picker("Months old", selection: $estimatedMonths) { ForEach(0..<12) { Text("\($0)").tag($0) } }
                            .onChange(of: estimatedMonths) { oldValue, newValue in hasModifiedAge = true } // <-- NEW
                    }
                    Toggle("This pet has passed away (Memorial)", isOn: $isMemorial).tint(.regalBlue)
                }
                
                // Danger Zone
                Section("Danger Zone") {
                    Button("Leave Pet (Transfer Ownership)") {
                        Task { await checkBeforeLeaving() }
                    }
                    .foregroundColor(.red)
                    
                    Button("Delete Pet Entirely") {
                        showingDeleteAlert = true
                    }
                    .foregroundColor(.red)
                }
                
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Pet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.primary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await saveChanges() } }) {
                        if isProcessing { ProgressView() } else { Text("Save").bold().foregroundColor(.regalBlue) }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isProcessing)
                }
            }
            // Deletion alerts
            .alert("Leave Pet?", isPresented: $showingLeaveAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Leave", role: .destructive) { Task { await executeLeavePet() } }
            } message: { Text("You will no longer manage this pet.") }
            
            .alert("Delete Pet?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { Task { await deletePetEntirely() } }
            } message: { Text("This permanently deletes the pet and its photos for everyone.") }
        }
    }
    
    // MARK: - Save Logic
    private func saveChanges() async {
        isProcessing = true
        errorMessage = ""
        do {
            // Calculate final data
            let finalSpecies = selectedSpecies == "Other" ? (customSpecies.isEmpty ? "Unknown" : customSpecies) : selectedSpecies
            let finalGender = selectedGender == "Unknown" ? nil : selectedGender
            let finalPersonality = personality == "Skip for now" ? nil : personality
            
            var cleanBreed: String? = nil
            if selectedSpecies != "Other" {
                if selectedBreed == "Other" {
                    cleanBreed = customBreed.trimmingCharacters(in: .whitespaces).isEmpty ? nil : customBreed
                } else if selectedBreed != "Mixed/Rescue" {
                    cleanBreed = selectedBreed
                }
            }
            
            var icon = "pawprint.circle.fill"
            switch selectedSpecies {
            case "Dog": icon = "dog.circle.fill"
            case "Cat": icon = "cat.circle.fill"
            case "Bird": icon = "bird.circle.fill"
            case "Snake", "Reptile": icon = "lizard.circle.fill"
            case "Hamster": icon = "hare.circle.fill"
            default: icon = "pawprint.circle.fill"
            }
            
            // Birthday calculation logic
            let dateString: String
            
            if isExactBirthdayKnown {
                // They know the exact date, format it normally
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                dateString = formatter.string(from: exactDate)
                
            } else {
                // It is estimated. Did they leave the pickers alone?
                if pet.isBirthdayEstimated && !hasModifiedAge {
                    // Keep the original string from the database to prevent "date drift"
                    dateString = pet.birthday ?? ""
                } else {
                    // They changed the pickers, so recalculate based on today's date
                    let finalBirthday = Calendar.current.date(byAdding: DateComponents(year: -estimatedYears, month: -estimatedMonths), to: Date()) ?? Date()
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    dateString = formatter.string(from: finalBirthday)
                }
            }
            
            // Handle photo upload & replacement
            var newPhotoUrl: String? = pet.photoUrl
            
            if let rawData = avatarData, let compressedData = ImageCompressor.compress(data: rawData, maxDimension: 500, compressionQuality: 0.6) {
                // Delete old photo if it exists
                if let oldPhotoUrlString = pet.photoUrl, let oldUrl = URL(string: oldPhotoUrlString) {
                    let oldFileName = oldUrl.lastPathComponent
                    try? await supabase.storage.from("pet_avatars").remove(paths: [oldFileName])
                }
                
                // Upload new photo
                let fileName = "\(UUID().uuidString).jpg"
                try await supabase.storage.from("pet_avatars").upload(fileName, data: compressedData, options: FileOptions(contentType: "image/jpeg"))
                newPhotoUrl = try supabase.storage.from("pet_avatars").getPublicURL(path: fileName).absoluteString
            }
            
            // DTO for updating (database replaces the row data here)
            struct PetUpdate: Codable {
                var name: String
                var species: String
                var gender: String?
                var breed: String?
                var birthday: String?
                var personality: String?
                var is_birthday_estimated: Bool
                var is_memorial: Bool
                var system_icon: String
                var photo_url: String?
            }
            
            // Use AnyEncodable to allow nil values to reach Supabase as null
            let updateData: [String: AnyEncodable] = [
                "name": AnyEncodable(name),
                "species": AnyEncodable(finalSpecies),
                "gender": AnyEncodable(finalGender),
                "breed": AnyEncodable(cleanBreed),
                "birthday": AnyEncodable(dateString),
                "personality": AnyEncodable(finalPersonality),
                "is_birthday_estimated": AnyEncodable(!isExactBirthdayKnown),
                "is_memorial": AnyEncodable(isMemorial),
                "system_icon": AnyEncodable(icon),
                "photo_url": AnyEncodable(newPhotoUrl)
            ]
            
            // Push update to Postgres
            try await supabase
                .from("pets")
                .update(updateData)
                .eq("id", value: pet.id)
                .execute()
            
            // Update local model
            var updatedPet = pet
            updatedPet.name = name
            updatedPet.species = finalSpecies
            updatedPet.gender = finalGender
            updatedPet.breed = cleanBreed
            updatedPet.birthday = dateString
            updatedPet.personality = finalPersonality
            updatedPet.isBirthdayEstimated = !isExactBirthdayKnown
            updatedPet.isMemorial = isMemorial
            updatedPet.systemIcon = icon
            updatedPet.photoUrl = newPhotoUrl
            if let newPhoto = avatarData { updatedPet.photoData = newPhoto }
            
            await MainActor.run {
                onSave(updatedPet)
                dismiss()
            }
        } catch {
            await MainActor.run { errorMessage = "Failed to update: \(error.localizedDescription)" }
        }
        isProcessing = false
    }
    
    // MARK: - Deletion / Transfer Logic
    
    private func checkBeforeLeaving() async {
        isProcessing = true
        errorMessage = ""
        do {
            // Count how many users own this pet
            struct CountResponse: Decodable {
                let count: Int
            }
            let response: [CountResponse] = try await supabase
                .from("pet_owners")
                .select("count", head: false)
                .eq("pet_id", value: pet.id)
                .execute()
                .value
            
            let ownerCount = response.count
            
            await MainActor.run {
                isProcessing = false
                if ownerCount > 1 {
                    showingLeaveAlert = true
                } else {
                    errorMessage = "You are the only owner! Add a co-owner first, or choose 'Delete Pet Entirely'."
                }
            }
        } catch {
            await MainActor.run {
                isProcessing = false
                errorMessage = "Failed to check co-owners."
            }
        }
    }
    
    private func executeLeavePet() async {
        isProcessing = true
        do {
            let userId = try await supabase.auth.session.user.id
            try await supabase.from("pet_owners").delete().eq("pet_id", value: pet.id).eq("user_id", value: userId).execute()
            
            await MainActor.run { onDelete() }
        } catch {
            await MainActor.run { errorMessage = "Failed to leave: \(error.localizedDescription)" }
        }
        isProcessing = false
    }
    
    private func deletePetEntirely() async {
        isProcessing = true
        do {
            // Delete photo from storage if it exists
            if let photoUrlString = pet.photoUrl, let oldUrl = URL(string: photoUrlString) {
                let oldFileName = oldUrl.lastPathComponent
                try? await supabase.storage.from("pet_avatars").remove(paths: [oldFileName])
            }
            
            // Delete the pet from Postgres
            try await supabase.from("pets").delete().eq("id", value: pet.id).execute()
            
            await MainActor.run { onDelete() }
        } catch {
            await MainActor.run { errorMessage = "Failed to delete: \(error.localizedDescription)" }
        }
        isProcessing = false
    }
}
