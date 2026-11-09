import SwiftUI
import Supabase

struct FollowingView: View {
    @State private var selectedTab: Tab = .humans
    
    // State arrays to hold our fetched data
    @State private var followedHumans: [FollowedHuman] = []
    @State private var followedPets: [FollowedPet] = []
    @State private var isLoading = true
    
    enum Tab {
        case humans
        case pets
    }
    
    // DTOs for decoding the Supabase response
    struct FollowedHuman: Identifiable, Decodable {
        let id: UUID
        let username: String?
        let full_name: String?
    }
    
    struct FollowedPet: Identifiable, Decodable {
        let id: UUID
        let name: String
        let system_icon: String
        let photo_url: String?
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Native tab switcher
            Picker("Following Type", selection: $selectedTab) {
                Text("Humans").tag(Tab.humans)
                Text("Pets").tag(Tab.pets)
            }
            .pickerStyle(.segmented)
            .padding()
            
            if isLoading {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else {
                List {
                    if selectedTab == .humans {
                        humansList
                    } else {
                        petsList
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Following")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchFollowing()
        }
    }
    
    // MARK: - Subviews
    private var humansList: some View {
        ForEach(followedHumans) { human in
            NavigationLink(destination: PublicProfileView(targetUsername: human.username ?? "")) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                    
                    VStack(alignment: .leading) {
                        Text(human.full_name ?? "No Name").fontWeight(.medium)
                        Text("@\(human.username ?? "user")").font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private var petsList: some View {
        ForEach(followedPets) { pet in
            NavigationLink(destination: PetProfileLoaderView(petId: pet.id)) {
                HStack(spacing: 12) {
                    if let photoUrl = pet.photo_url, let url = URL(string: photoUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: pet.system_icon)
                            .font(.title)
                            .foregroundColor(.regalBlue)
                    }
                    
                    Text(pet.name)
                        .fontWeight(.medium)
                        .foregroundColor(.primary) // Keeps text from turning link-blue
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    // MARK: - Database Fetching
    private func fetchFollowing() async {
        isLoading = true
        do {
            let userId = try await supabase.auth.session.user.id
            
            // Fetch humans
            // We look at 'user_follows' where we are the follower, and join the 'profiles' table for the person we are following
            struct HumanResponse: Decodable { let profiles: FollowedHuman? }
            let humanData: [HumanResponse] = try await supabase
                .from("user_follows")
                .select("profiles!following_id(id, username, full_name)")
                .eq("follower_id", value: userId)
                .execute()
                .value
            
            // Fetch pets
            // We look at 'pet_followers' where we are the user, and join the 'pets' table
            struct PetResponse: Decodable { let pets: FollowedPet? }
            let petData: [PetResponse] = try await supabase
                .from("pet_followers")
                .select("pets(id, name, system_icon, photo_url)")
                .eq("user_id", value: userId)
                .execute()
                .value
            
            await MainActor.run {
                self.followedHumans = humanData.compactMap { $0.profiles }
                self.followedPets = petData.compactMap { $0.pets }
                self.isLoading = false
            }
        } catch {
            print("Error fetching following lists: \(error)")
            await MainActor.run { isLoading = false }
        }
    }
}
