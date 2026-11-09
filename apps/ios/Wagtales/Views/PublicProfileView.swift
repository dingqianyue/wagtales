import SwiftUI
import Supabase

struct PublicProfileView: View {
    let targetUsername: String // Passed in without the "@"
    
    // MARK: - Profile State
    @State private var fullName = ""
    @State private var bio = ""
    @State private var education = ""
    @State private var workplace = ""
    @State private var userPets: [Pet] = []
    
    // MARK: - Social Stats State
    @State private var followersCount = 0
    @State private var followingCount = 0
    
    // MARK: - Follow Action State
    @State private var targetUserId: UUID?
    @State private var isFollowing = false
    @State private var isFollowProcessing = false
    @State private var isCurrentUser = false // Prevent following self
    
    // MARK: - View State
    @State private var isLoading = true
    @State private var errorMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    ProgressView("Loading Profile...")
                        .padding(.top, 50)
                } else if !errorMessage.isEmpty {
                    Text(errorMessage).foregroundColor(.red).padding(.top, 50)
                } else {
                    compactHeader
                    
                    // Only show the follow button if this is not your own profile
                    if !isCurrentUser {
                        actionButtonsRow
                    }
                    
                    socialStatsRow
                    petsSection
                    
                    userPostsSection
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("@\(targetUsername)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchPublicProfile()
        }
    }
    
    // MARK: - Database Logic
    private func fetchPublicProfile() async {
        isLoading = true
        do {
            // Fetch profile data
            struct PublicProfileData: Decodable {
                let id: UUID
                let full_name: String?
                let bio: String?
                let education: String?
                let workplace: String?
            }
            
            let profile: PublicProfileData = try await supabase
                .from("profiles")
                .select("id, full_name, bio, education, workplace")
                .eq("username", value: targetUsername)
                .single()
                .execute()
                .value
            
            fullName = profile.full_name ?? ""
            bio = profile.bio ?? ""
            education = profile.education ?? ""
            workplace = profile.workplace ?? ""
            targetUserId = profile.id // Save for the follow button
            
            // Fetch followers count
            let followersResponse = try await supabase.from("user_follows")
                .select("*", head: true, count: .exact)
                .eq("following_id", value: profile.id)
                .execute()
            followersCount = followersResponse.count ?? 0
            
            // Fetch following count for humans
            let followingHumansResponse = try await supabase.from("user_follows")
                .select("*", head: true, count: .exact)
                .eq("follower_id", value: profile.id)
                .execute()
            let humanCount = followingHumansResponse.count ?? 0

            // Fetch following count for pets
            let followingPetsResponse = try await supabase.from("pet_followers")
                .select("*", head: true, count: .exact)
                .eq("user_id", value: profile.id)
                .execute()
            let petCount = followingPetsResponse.count ?? 0

            // Add them together
            followingCount = humanCount + petCount
            
            // Fetch pets
            let fetchedPets: [Pet] = try await supabase
                .from("pets")
                .select("id, name, species, gender, breed, birthday, personality, is_birthday_estimated, is_memorial, system_icon, photo_url, pet_owners!inner(user_id)")
                .eq("pet_owners.user_id", value: profile.id)
                .execute()
                .value
            
            userPets = fetchedPets
            
            // Check if you are already following them and check if it's your own profile
            if let myUser = try? await supabase.auth.session.user {
                // Flag if this profile belongs to the logged-in user
                isCurrentUser = (myUser.id == profile.id)
                
                // Only check follow status if it's not you
                if !isCurrentUser {
                    let followCheck = try await supabase.from("user_follows")
                        .select("*", head: true, count: .exact)
                        .eq("follower_id", value: myUser.id)
                        .eq("following_id", value: profile.id)
                        .execute()
                    
                    isFollowing = (followCheck.count ?? 0) > 0
                }
            }
            
        } catch {
            errorMessage = "User not found or error loading data."
            print("Profile fetch error: \(error)")
        }
        isLoading = false
    }
    
    private func toggleFollow() async {
        guard let targetId = targetUserId, !isFollowProcessing else { return }
        isFollowProcessing = true
        
        do {
            let myId = try await supabase.auth.session.user.id
            
            if isFollowing {
                // Unfollow: Delete from database
                try await supabase.from("user_follows")
                    .delete()
                    .eq("follower_id", value: myId)
                    .eq("following_id", value: targetId)
                    .execute()
                
                // Update UI instantly
                isFollowing = false
                followersCount -= 1
            } else {
                // Follow: Insert into database using a safe Struct
                struct FollowPayload: Encodable {
                    let follower_id: UUID
                    let following_id: UUID
                }
                
                let payload = FollowPayload(follower_id: myId, following_id: targetId)
                
                try await supabase.from("user_follows")
                    .insert(payload)
                    .execute()
                
                // Update UI instantly
                isFollowing = true
                followersCount += 1
            }
        } catch {
            print("Follow action error: \(error)")
            errorMessage = "Could not follow: \(error.localizedDescription)"
        }
        
        isFollowProcessing = false
    }
    
    // MARK: - Subviews
    private var compactHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.regalBlue)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(fullName.isEmpty ? "No Name" : fullName).font(.title3).bold()
                    Text("@\(targetUsername)").font(.caption).foregroundColor(.secondary)
                }
                
                if !bio.isEmpty {
                    Text(bio).font(.footnote)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if !education.isEmpty {
                        HStack { Image(systemName: "graduationcap.fill"); Text(education) }
                    }
                    if !workplace.isEmpty {
                        HStack { Image(systemName: "building.2.fill"); Text(workplace) }
                    }
                }
                .font(.caption2).foregroundColor(.secondary).padding(.top, 2)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
    
    // Follow and message buttons
    private var actionButtonsRow: some View {
        HStack(spacing: 12) {
            
            // Follow button
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
            
            // Message button
            if let targetId = targetUserId {
                NavigationLink(destination: ChatDetailView(
                    receiverId: targetId,
                    ownerHandle: "@\(targetUsername)",
                    petName: "Direct"
                )) {
                    Text("Message")
                        .font(.subheadline)
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var socialStatsRow: some View {
        HStack(spacing: 0) {
            StatItem(title: "Followers", value: "\(followersCount)")
                .frame(maxWidth: .infinity)
            
            Divider().frame(height: 30)
            
            StatItem(title: "Following", value: "\(followingCount)")
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var petsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pets").font(.headline).padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(userPets) { pet in
                        // Links to the standard PetProfileView
                        NavigationLink(destination: PetProfileView(
                            pet: pet,
                            onDelete: {
                                withAnimation { userPets.removeAll { $0.id == pet.id } }
                            },
                            onUpdate: { updatedPet in
                                // Replace the old pet data with the newly edited data
                                if let index = userPets.firstIndex(where: { $0.id == updatedPet.id }) {
                                    userPets[index] = updatedPet
                                }
                            }
                        )) {
                            VStack(spacing: 8) {
                                // Photo section (matches dashboard)
                                ZStack(alignment: .topTrailing) {
                                    if let photoUrlString = pet.photoUrl, let url = URL(string: photoUrlString) {
                                        AsyncImage(url: url) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: {
                                            ProgressView()
                                        }
                                        .frame(width: 60, height: 60)
                                        .clipShape(Circle())
                                    } else if let photoData = pet.photoData, let uiImage = UIImage(data: photoData) {
                                        Image(uiImage: uiImage).resizable().scaledToFill().frame(width: 60, height: 60).clipShape(Circle())
                                    } else {
                                        Image(systemName: pet.systemIcon).font(.system(size: 40))
                                            .frame(width: 60, height: 60)
                                            .background(Color(.systemGray5))
                                            .foregroundColor(pet.isMemorial ? .gray : .regalBlue)
                                            .clipShape(Circle())
                                    }
                                    
                                    if pet.isMemorial {
                                        Image(systemName: "sparkles").font(.caption2).foregroundColor(.moonGold).background(Circle().fill(Color.white)).offset(x: 5, y: -5)
                                    }
                                }
                                
                                // Name & status row (matches dashboard)
                                HStack(spacing: 4) {
                                    Text(pet.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    if let gender = pet.gender?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                                        if gender.starts(with: "m") {
                                            Text("♂").foregroundColor(.regalBlue).font(.caption)
                                        } else if gender.starts(with: "f") {
                                            Text("♀").foregroundColor(.pink).font(.caption)
                                        }
                                    }
                                    
                                    if pet.isBirthdayToday {
                                        Text("🎂").font(.caption2)
                                    }
                                }
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Posts Section
    private var userPostsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Posts")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 16)
            
            if let userId = targetUserId {
                ProfilePostGridView(userId: userId)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
