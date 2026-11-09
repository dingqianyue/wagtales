import SwiftUI
import Supabase

struct PetProfileView: View {
    @State var pet: Pet
    var onDelete: () -> Void
    var onUpdate: (Pet) -> Void
    
    @Environment(\.dismiss) var dismiss
    
    // MARK: - State
    @State private var fetchedOwners: [String] = []
    @State private var isLoadingOwners = true
    @State private var showingAddOwner = false
    @State private var showingEditPet = false
    
    // MARK: - Follow & Ownership State
    @State private var currentUserId: UUID?
    @State private var isOwner = false
    @State private var isFollowing = false
    @State private var isFollowProcessing = false
    @State private var followersCount = 0
    
    // Action sheet & confirmation state
    @State private var showingOptions = false
    @State private var showingConfirmationAlert = false
    @State private var pendingDeleteAction: DeleteAction? = nil
    @State private var isProcessing = false
    
    // Error handling state
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    
    enum DeleteAction {
        case leave
        case deleteEntirely
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // Pet header image
                ZStack(alignment: .topTrailing) {
                    if let photoUrlString = pet.photoUrl, let url = URL(string: photoUrlString) {
                        // Downloads and caches the image from Supabase
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView() // Shows a spinner while downloading
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                    } else if let localData = pet.photoData, let uiImage = UIImage(data: localData) {
                        // Fallback for instant UI updates before refresh
                        Image(uiImage: uiImage).resizable().scaledToFill().frame(width: 120, height: 120).clipShape(Circle())
                    } else {
                        // Fallback icon
                        Image(systemName: pet.systemIcon)
                            .font(.system(size: 100))
                            .foregroundColor(pet.isMemorial ? .gray : .regalBlue)
                            .opacity(pet.isMemorial ? 0.6 : 1.0)
                    }
                    
                    if pet.isMemorial {
                        Image(systemName: "sparkles").font(.title).foregroundColor(.moonGold).background(Circle().fill(Color.white)).offset(x: 10, y: -10)
                    }
                }
                .padding(.top, 20)
                
                // Name, breed, age, gender
                VStack(spacing: 8) {
                    HStack {
                        Text(pet.name).font(.largeTitle).bold()
                        
                        // Birthday cake
                        if pet.isBirthdayToday {
                            Text("🎂").font(.title)
                        }
                        
                        if let gender = pet.gender?.lowercased() {
                            if gender.starts(with: "m") {
                                Text("♂").foregroundColor(.regalBlue).font(.title2)
                            }
                            else if gender.starts(with: "f") {
                                Text("♀").foregroundColor(.pink).font(.title2)
                            }
                        }
                    }
                    
                    if pet.isMemorial {
                        Text("Forever in our hearts").font(.subheadline).foregroundColor(.secondary).italic()
                    } else {
                        if let breed = pet.breed, !breed.isEmpty {
                            Text("\(breed) • \(pet.ageString)").font(.subheadline).foregroundColor(.secondary)
                        } else {
                            Text("\(pet.species) • \(pet.ageString)").font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                    
                    if let personality = pet.personality, !personality.isEmpty {
                        Text("Personality: \(personality)").font(.subheadline).padding(.top, 4)
                    }
                }
                
                // Follow button (only visible if the current user is not an owner)
                if !isOwner && !isLoadingOwners {
                    followButtonRow
                }
                
                // Co-owners section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Managed by").font(.caption).foregroundColor(.secondary).padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            if isLoadingOwners {
                                ProgressView().padding(.horizontal)
                            } else {
                                ForEach(fetchedOwners, id: \.self) { ownerHandle in
                                    let cleanUsername = ownerHandle.replacingOccurrences(of: "@", with: "")
                                    
                                    NavigationLink(destination: PublicProfileView(targetUsername: cleanUsername)) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "person.crop.circle.fill")
                                            Text(ownerHandle)
                                        }
                                        .font(.subheadline).fontWeight(.medium).padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(Color.regalBlue.opacity(0.1)).foregroundColor(.regalBlue).cornerRadius(20)
                                    }
                                }
                            }
                            
                            // Only show "add owner" if the current user is an owner
                            if isOwner {
                                Button(action: { showingAddOwner = true }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.badge.plus")
                                        Text("Add")
                                    }
                                    .font(.subheadline).fontWeight(.medium).padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Color(.systemGray6)).foregroundColor(.primary).cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 8)
                
                // Social stats
                HStack(spacing: 60) {
                    StatItem(title: "Followers", value: "\(followersCount)")
                    StatItem(title: "Posts", value: "0") // Posts remain hardcoded for now
                }
                .padding().background(Color(.systemGray6)).cornerRadius(16).padding(.horizontal)
                
                Divider().padding(.horizontal)
                
                // Photo feed
                petPostsSection
            }
        }
        .navigationTitle(pet.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchPetData()
        }
        .overlay {
            if isProcessing {
                Color.black.opacity(0.3).ignoresSafeArea()
                ProgressView().tint(.white).scaleEffect(1.5)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Only show settings gear if they are an owner
                if isOwner {
                    Button(action: { showingEditPet = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditPet) {
            EditPetView(
                pet: pet,
                onSave: { updatedPet in
                    self.pet = updatedPet
                    onUpdate(updatedPet)
                },
                onDelete: {
                    dismiss()
                    onDelete()
                    self.dismiss()
                }
            )
            .presentationDetents([.large])
        }
    }
    
    // MARK: - Follow UI
    private var followButtonRow: some View {
        Button(action: {
            Task { await toggleFollow() }
        }) {
            Text(isFollowing ? "Following" : "Follow")
                .font(.subheadline)
                .bold()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isFollowing ? Color(.systemGray5) : Color.regalBlue)
                .foregroundColor(isFollowing ? .primary : .white)
                .cornerRadius(8)
        }
        .disabled(isFollowProcessing)
        .padding(.horizontal)
    }
    
    // MARK: - Database Operations
    private func fetchPetData() async {
        isLoadingOwners = true
        do {
            let myId = try await supabase.auth.session.user.id
            self.currentUserId = myId
            
            // Fetch owners (request user_id to check ownership)
            struct PetOwnerData: Decodable {
                let user_id: UUID
                struct Profile: Decodable { let username: String? }
                let profiles: Profile?
            }
            
            let response: [PetOwnerData] = try await supabase
                .from("pet_owners")
                .select("user_id, profiles(username)")
                .eq("pet_id", value: pet.id)
                .execute()
                .value
            
            // Map the handles for UI
            fetchedOwners = response
                .compactMap { $0.profiles?.username }
                .filter { !$0.isEmpty }
                .map { "@\($0)" }
            
            // Check if we are in the owner list
            isOwner = response.contains(where: { $0.user_id == myId })
            
            // Fetch followers count
            let followersResponse = try await supabase.from("pet_followers")
                .select("*", head: true, count: .exact)
                .eq("pet_id", value: pet.id)
                .execute()
            followersCount = followersResponse.count ?? 0
            
            // Check if we are currently following (only bother checking if we aren't an owner)
            if !isOwner {
                let followCheck = try await supabase.from("pet_followers")
                    .select("*", head: true, count: .exact)
                    .eq("user_id", value: myId)
                    .eq("pet_id", value: pet.id)
                    .execute()
                
                isFollowing = (followCheck.count ?? 0) > 0
            }
            
        } catch {
            print("Error fetching pet data: \(error)")
        }
        isLoadingOwners = false
    }
    
    private func toggleFollow() async {
        guard let myId = currentUserId, !isFollowProcessing else { return }
        isFollowProcessing = true
        
        do {
            if isFollowing {
                // Unfollow
                try await supabase.from("pet_followers")
                    .delete()
                    .eq("user_id", value: myId)
                    .eq("pet_id", value: pet.id)
                    .execute()
                
                isFollowing = false
                followersCount -= 1
            } else {
                // Follow
                struct PetFollowPayload: Encodable {
                    let user_id: UUID
                    let pet_id: UUID
                }
                
                let payload = PetFollowPayload(user_id: myId, pet_id: pet.id)
                
                try await supabase.from("pet_followers")
                    .insert(payload)
                    .execute()
                
                isFollowing = true
                followersCount += 1
            }
        } catch {
            print("Follow pet error: \(error)")
        }
        
        isFollowProcessing = false
    }
    
    private func leavePet() async {
        isProcessing = true
        do {
            let userId = try await supabase.auth.session.user.id
            try await supabase
                .from("pet_owners")
                .delete()
                .eq("pet_id", value: pet.id)
                .eq("user_id", value: userId)
                .execute()
            
            await MainActor.run {
                onDelete()
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to leave pet: \(error.localizedDescription)"
                showingErrorAlert = true
            }
        }
        isProcessing = false
    }
    
    private func deletePetEntirely() async {
        isProcessing = true
        do {
            try await supabase
                .from("pets")
                .delete()
                .eq("id", value: pet.id)
                .execute()
            
            await MainActor.run {
                onDelete()
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to delete pet: \(error.localizedDescription)"
                showingErrorAlert = true
            }
        }
        isProcessing = false
    }
    
    // MARK: - Posts Section
    private var petPostsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Posts")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 16)
            ProfilePostGridView(petId: pet.id)
        }
    }
}
