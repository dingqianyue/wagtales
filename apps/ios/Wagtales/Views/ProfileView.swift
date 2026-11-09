import SwiftUI
import Supabase

struct ProfileView: View {
    @State private var showingAddPet = false
    @State private var showingSettings = false
    
    // MARK: - State Variables
    @State private var myName = ""
    @State private var myUsername = ""
    @State private var myBio = ""
    @State private var myEducation = ""
    @State private var myWorkplace = ""
    @State private var myAvatarUrl: String? = nil
    @State private var currentUserId: UUID? = nil
    @State private var myPets: [Pet] = []
    
    // Social stats state
    @State private var followersCount = 0
    @State private var followingCount = 0
    
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if isLoading {
                        ProgressView("Loading Dashboard...")
                            .padding(.top, 50)
                    } else {
                        compactHeader
                        
                        // Social stats directly under the header
                        socialStatsRow
                        
                        myPetsSection
                        
//                        rewardsCard
//                        activityStatsRow
                        
                        myPostsSection
                    }
                }
                .padding(.vertical)
                .sheet(isPresented: $showingAddPet) {
                    AddPetView(onSave: { newPet in
                        myPets.append(newPet)
                    })
                }
            }
            .navigationTitle("My Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape").foregroundColor(.primary)
                    }
                }
            }
            .refreshable {
                // Allows pull-to-refresh
                await fetchUserData()
            }
            .task {
                await fetchUserData()
            }
        }
    }
    
    // MARK: - Data Fetching
    private func fetchUserData() async {
        isLoading = true
        do {
            let user = try await supabase.auth.session.user
            currentUserId = user.id
            
            // Fetch profile data
            struct ProfileData: Decodable {
                let full_name: String?
                let username: String?
                let bio: String?
                let education: String?
                let workplace: String?
                let avatar_url: String?
            }
            
            let profile: ProfileData = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: user.id)
                .single()
                .execute()
                .value
            
            myName = profile.full_name ?? ""
            myUsername = profile.username ?? ""
            myBio = profile.bio ?? ""
            myEducation = profile.education ?? ""
            myWorkplace = profile.workplace ?? ""
            myAvatarUrl = profile.avatar_url
            
            // Fetch pets via many-to-many junction
            let fetchedPets: [Pet] = try await supabase
                .from("pets")
                .select("id, name, species, gender, breed, birthday, personality, is_birthday_estimated, is_memorial, system_icon, photo_url, pet_owners!inner(user_id)")
                .eq("pet_owners.user_id", value: user.id)
                .execute()
                .value
            
            myPets = fetchedPets
            
            // Fetch user's followers count
            let followersResponse = try await supabase.from("user_follows")
                .select("*", head: true, count: .exact)
                .eq("following_id", value: user.id)
                .execute()
            followersCount = followersResponse.count ?? 0
            
            // Fetch following count for humans
            let followingHumansResponse = try await supabase.from("user_follows")
                .select("*", head: true, count: .exact)
                .eq("follower_id", value: user.id)
                .execute()
            let humanCount = followingHumansResponse.count ?? 0

            // Fetch following count for pets
            let followingPetsResponse = try await supabase.from("pet_followers")
                .select("*", head: true, count: .exact)
                .eq("user_id", value: user.id)
                .execute()
            let petCount = followingPetsResponse.count ?? 0

            // Add them together
            followingCount = humanCount + petCount
            
        } catch {
            print("Error fetching profile data: \(error)")
        }
        isLoading = false
    }
    
    // MARK: - Subviews
    private var compactHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            
            // Display user avatar instead of just the system image
            if let urlString = myAvatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.regalBlue)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(myName.isEmpty ? "No Name" : myName).font(.title3).bold()
                    Text("@\(myUsername.isEmpty ? "username" : myUsername)").font(.caption).foregroundColor(.secondary)
                }
                if !myBio.isEmpty {
                    Text(myBio).font(.footnote)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if !myEducation.isEmpty {
                        HStack { Image(systemName: "graduationcap.fill"); Text(myEducation) }
                    }
                    if !myWorkplace.isEmpty {
                        HStack { Image(systemName: "building.2.fill"); Text(myWorkplace) }
                    }
                }
                .font(.caption2).foregroundColor(.secondary).padding(.top, 2)
            }
            Spacer()
        }
        .padding(.horizontal)
        .sheet(isPresented: $showingSettings) {
            ProfileSettingsView(
                onSave: { newName, newUsername, newBio, newEdu, newWork, newAvatarUrl in
                    myName = newName
                    myUsername = newUsername
                    myBio = newBio
                    myEducation = newEdu
                    myWorkplace = newWork
                    myAvatarUrl = newAvatarUrl // Save the new photo locally so the UI updates instantly
                },
                name: myName,
                username: myUsername,
                bio: myBio,
                education: myEducation,
                workplace: myWorkplace,
                avatarUrl: myAvatarUrl // Send the current photo into the settings view
            )
        }
    }
    
    private var socialStatsRow: some View {
        HStack(spacing: 0) {
            // Links to FollowersView
            NavigationLink(destination: FollowersView()) {
                StatItem(title: "Followers", value: "\(followersCount)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain) // Prevents the text from turning blue
            
            Divider().frame(height: 30)
            
            // Links to FollowingView
            NavigationLink(destination: FollowingView()) {
                StatItem(title: "Following", value: "\(followingCount)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain) // Prevents the text from turning blue
        }
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var myPetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Pets").font(.headline).padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(myPets) { pet in
                        // Route to PetProfileView
                        NavigationLink(destination: PetProfileView(
                            pet: pet,
                            onDelete: {
                                withAnimation { myPets.removeAll { $0.id == pet.id } }
                            },
                            onUpdate: { updatedPet in
                                // Find the pet in the array and replace it with the new data
                                if let index = myPets.firstIndex(where: { $0.id == updatedPet.id }) {
                                    myPets[index] = updatedPet
                                }
                            }
                        )) {
                            VStack(spacing: 8) {
                                // Avatar circle
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
                                
                                // Name & icons row
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
                                .fixedSize(horizontal: true, vertical: false) // Prevents icons from being squished away
                            }
                        }
                    }
                    
                    // Add pet button
                    Button(action: { showingAddPet = true }) {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.dashed")
                                .font(.system(size: 30))
                                .frame(width: 60, height: 60)
                                .background(Color(.systemGray6))
                                .foregroundColor(.gray)
                                .clipShape(Circle())
                            Text("Add Pet").font(.caption).foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // Mock data
    private var rewardsCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "gift.fill").font(.title).foregroundColor(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Next: $5 Local Shelter Donation").font(.subheadline).bold()
                ProgressView(value: 0.8).tint(.red)
            }
            Text("2 mi").font(.caption).bold().foregroundColor(.secondary)
        }
        .padding().background(Color(.systemGray6)).cornerRadius(16).padding(.horizontal)
    }
    
    // Mock data
    private var activityStatsRow: some View {
        HStack(spacing: 0) {
            StatItem(title: "Miles", value: "124.5").frame(maxWidth: .infinity)
            Divider().frame(height: 30)
            StatItem(title: "Days", value: "60").frame(maxWidth: .infinity)
            Divider().frame(height: 30)
            StatItem(title: "Donated", value: "$15").frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12).background(Color(.systemGray6)).cornerRadius(12).padding(.horizontal)
    }
    
    // MARK: - Posts Section
    private var myPostsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Posts")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 16)
            
            if let userId = currentUserId {
                ProfilePostGridView(userId: userId)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct StatItem: View {
    var title: String
    var value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).bold()
            Text(title).font(.caption).foregroundColor(.secondary)
        }
    }
}
