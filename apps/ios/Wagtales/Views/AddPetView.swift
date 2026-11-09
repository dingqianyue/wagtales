import SwiftUI
import PhotosUI
import Supabase

// MARK: - Supabase DTOs (Data Transfer Objects)
struct PetInsert: Codable {
    var name: String
    var species: String
    var gender: String?       // Will save as NULL if nil
    var breed: String?        // Will save as NULL if nil
    var birthday: String?     // "YYYY-MM-DD"
    var personality: String?  // Will save as NULL if nil
    var is_birthday_estimated: Bool
    var is_memorial: Bool
    var system_icon: String
    var photo_url: String?
}

struct InsertedPetResponse: Codable {
    var id: UUID
}

struct PetOwnerInsert: Codable {
    var pet_id: UUID
    var user_id: UUID
}

struct AddPetView: View {
    @Environment(\.dismiss) var dismiss
    var onSave: (Pet) -> Void
    
    // Photo state
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarData: Data?
    
    // Text fields state
    @State private var name = ""
    @State private var selectedSpecies = "Dog"
    @State private var customSpecies = ""
    
    // Gender state
    @State private var selectedGender = "Unknown"
    
    @State private var selectedBreed = "Mixed/Rescue"
    @State private var customBreed = ""
    
    // Default to skip for optional personality
    @State private var personality = "Skip for now"
    
    @State private var isExactBirthdayKnown = true
    @State private var exactDate = Date()
    @State private var estimatedYears = 2
    @State private var estimatedMonths = 0
    
    @State private var isMemorial = false
    
    // Supabase State
    @State private var isSaving = false
    @State private var errorMessage = ""
    
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
    
    var body: some View {
        NavigationStack {
            Form {
                // Photo section
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            if let avatarData, let uiImage = UIImage(data: avatarData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else {
                                VStack {
                                    Image(systemName: "camera.circle.fill")
                                        .font(.system(size: 80))
                                        .foregroundColor(.regalBlue)
                                    Text("Add Photo")
                                        .font(.caption)
                                        .foregroundColor(.regalBlue)
                                }
                            }
                        }
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
                
                Section(header: Text("Age & Birthday")) {
                    Toggle("I know the exact birthday", isOn: $isExactBirthdayKnown).tint(.regalBlue)
                    if isExactBirthdayKnown {
                        DatePicker("Birthday", selection: $exactDate, in: ...Date(), displayedComponents: .date)
                    } else {
                        Picker("Years old", selection: $estimatedYears) { ForEach(0..<31) { Text("\($0)").tag($0) } }
                        Picker("Months old", selection: $estimatedMonths) { ForEach(0..<12) { Text("\($0)").tag($0) } }
                    }
                    Toggle("This pet has passed away (Memorial)", isOn: $isMemorial)
                        .tint(.regalBlue)
                }
                
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Add a Pet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.primary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task { await savePetToSupabase() }
                    }) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .bold()
                                .foregroundColor(.regalBlue)
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }
    
    // MARK: - Supabase Save Logic
    private func savePetToSupabase() async {
        isSaving = true
        errorMessage = ""
        
        do {
            // Get the current user
            let userId = try await supabase.auth.session.user.id
            
            // Calculate final data
            let finalSpecies = selectedSpecies == "Other" ? (customSpecies.isEmpty ? "Unknown" : customSpecies) : selectedSpecies
            let finalBreed = selectedSpecies == "Other" ? "" : (selectedBreed == "Other" ? customBreed : selectedBreed)
            
            var icon = "pawprint.circle.fill"
            switch selectedSpecies {
            case "Dog": icon = "dog.circle.fill"
            case "Cat": icon = "cat.circle.fill"
            case "Bird": icon = "bird.circle.fill"
            case "Snake", "Reptile": icon = "lizard.circle.fill"
            case "Hamster": icon = "hare.circle.fill"
            default: icon = "pawprint.circle.fill"
            }
            
            let finalBirthday = isExactBirthdayKnown ? exactDate : (Calendar.current.date(byAdding: DateComponents(year: -estimatedYears, month: -estimatedMonths), to: Date()) ?? Date())
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dateString = formatter.string(from: finalBirthday)
            
            // Upload photo to storage bucket
            var finalPhotoUrl: String? = nil
            
            if let rawData = avatarData,
               let compressedData = ImageCompressor.compress(data: rawData, maxDimension: 500, compressionQuality: 0.6) {
                
                let fileName = "\(UUID().uuidString).jpg"
                
                try await supabase.storage
                    .from("pet_avatars")
                    .upload(
                        fileName,
                        data: compressedData, // Upload compressed data
                        options: FileOptions(contentType: "image/jpeg")
                    )
                
                finalPhotoUrl = try supabase.storage
                    .from("pet_avatars")
                    .getPublicURL(path: fileName).absoluteString
            }
            
            // Package data for Postgres with nil checks
            let newPetData = PetInsert(
                name: name,
                species: finalSpecies,
                gender: selectedGender == "Unknown" ? nil : selectedGender,
                breed: finalBreed.isEmpty ? nil : finalBreed,
                birthday: dateString,
                personality: personality == "Skip for now" ? nil : personality,
                is_birthday_estimated: !isExactBirthdayKnown,
                is_memorial: isMemorial,
                system_icon: icon,
                photo_url: finalPhotoUrl // Save URL to database
            )
            
            // Insert pet and retrieve new ID
            let insertedPet: InsertedPetResponse = try await supabase
                .from("pets")
                .insert(newPetData)
                .select("id")
                .single()
                .execute()
                .value
            
            // Insert junction table row
            let bridgeRecord = PetOwnerInsert(pet_id: insertedPet.id, user_id: userId)
            try await supabase
                .from("pet_owners")
                .insert(bridgeRecord)
                .execute()
            
            // Create local model for instant UI update
            let newLocalPet = Pet(
                id: insertedPet.id,
                name: name,
                species: finalSpecies,
                gender: selectedGender == "Unknown" ? nil : selectedGender,
                breed: finalBreed.isEmpty ? nil : finalBreed,
                birthday: dateString,
                personality: personality == "Skip for now" ? nil : personality,
                photoUrl: finalPhotoUrl,
                isBirthdayEstimated: !isExactBirthdayKnown,
                isMemorial: isMemorial,
                systemIcon: icon,
                photoData: avatarData // The URL we just got from the bucket
            )
            
            await MainActor.run {
                onSave(newLocalPet)
                isSaving = false
                dismiss()
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to save pet: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}

#Preview {
    AddPetView(onSave: { _ in })
}
