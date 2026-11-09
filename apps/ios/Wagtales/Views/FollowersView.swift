import SwiftUI
import Supabase

struct FollowersView: View {
    @State private var followers: [Follower] = []
    @State private var isLoading = true
    
    // DTO for decoding
    struct Follower: Identifiable, Decodable {
        let id: UUID
        let username: String?
        let full_name: String?
    }
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading followers...")
            } else if followers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("No followers yet.")
                        .foregroundColor(.secondary)
                }
            } else {
                List(followers) { follower in
                    NavigationLink(destination: PublicProfileView(targetUsername: follower.username ?? "")) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title)
                                .foregroundColor(.gray)
                            
                            VStack(alignment: .leading) {
                                Text(follower.full_name ?? "No Name").fontWeight(.medium)
                                Text("@\(follower.username ?? "user")").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Followers")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchFollowers()
        }
    }
    
    private func fetchFollowers() async {
        isLoading = true
        do {
            let userId = try await supabase.auth.session.user.id
            
            // Look for rows where we are the 'following_id', and fetch the 'follower_id' profile
            struct FollowerResponse: Decodable { let profiles: Follower? }
            let data: [FollowerResponse] = try await supabase
                .from("user_follows")
                .select("profiles!follower_id(id, username, full_name)")
                .eq("following_id", value: userId)
                .execute()
                .value
            
            await MainActor.run {
                self.followers = data.compactMap { $0.profiles }
                self.isLoading = false
            }
        } catch {
            print("Error fetching followers: \(error)")
            await MainActor.run { isLoading = false }
        }
    }
}
