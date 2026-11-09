// Reusable component for both user and pet profiles

import SwiftUI
import Supabase

struct ProfilePostGridView: View {
    // Pass ONE of these in when we use the view
    var userId: UUID? = nil
    var petId: UUID? = nil
    
    @State private var posts: [Post] = []
    @State private var isLoading = true
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        VStack(alignment: .leading) {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
            } else if posts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 50))
                        .foregroundColor(Color(.systemGray4))
                    Text("No posts yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach($posts) { $post in
                        NavigationLink(destination: FullPostView(post: $post)) {
                            GridPostCard(post: $post)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
        }
        .onAppear {
            // Force a silent database check every time this page becomes visible
            Task {
                await fetchProfilePosts()
            }
        }
    }
    
    private func fetchProfilePosts() async {
        
        // Only show the spinner if we have absolutely no posts yet
        if posts.isEmpty { isLoading = true }
        
        do {
            struct PostResponse: Decodable {
                let id: UUID
                let user_id: UUID
                let title: String
                let content: String
                let image_url: String?
                let likes_count: Int?
                let saves_count: Int?
                let comments_count: Int?
                let shares_count: Int?
                let created_at: String
                
                struct ProfileResp: Decodable { let full_name: String?; let username: String? }
                let profiles: ProfileResp?
                
                struct PetResp: Decodable { let name: String; let system_icon: String }
                let pets: PetResp?
            }
            
            // Start building the Supabase query
            var query = supabase.from("posts")
                .select("id, user_id, title, content, image_url, likes_count, saves_count, comments_count, shares_count, created_at, profiles(full_name, username), pets(name, system_icon)")
            
            // Smart filtering: Are we looking for a pet or a human?
            if let targetPetId = petId {
                // It's a pet profile! Grab only posts where pet_id matches.
                query = query.eq("pet_id", value: targetPetId)
            } else if let targetUserId = userId {
                // It's a human profile! Grab posts by this user, BUT ONLY where pet_id is null.
                // We use .filter with operator: "is" to avoid Swift's keyword confusion
                query = query
                    .eq("user_id", value: targetUserId)
                    .filter("pet_id", operator: "is", value: "null")
            }
            
            // Execute the query
            let fetchedData: [PostResponse] = try await query
                .order("created_at", ascending: false)
                .execute()
                .value
            
            // Memory fetch
            let myId = try? await supabase.auth.session.user.id
            struct ItemRef: Decodable { let post_id: UUID }
            var myLikedPostIds: Set<UUID> = []
            var mySavedPostIds: Set<UUID> = []
            
            if let userId = myId {
                if let liked: [ItemRef] = try? await supabase.from("post_likes").select("post_id").eq("user_id", value: userId).execute().value {
                    myLikedPostIds = Set(liked.map { $0.post_id })
                }
                if let saved: [ItemRef] = try? await supabase.from("post_saves").select("post_id").eq("user_id", value: userId).execute().value {
                    mySavedPostIds = Set(saved.map { $0.post_id })
                }
            }
            
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            var loadedPosts: [Post] = []
            for item in fetchedData {
                let isPetPost = (item.pets != nil)
                let authorName = isPetPost ? item.pets!.name : (item.profiles?.full_name ?? item.profiles?.username ?? "Unknown")
                let authorIcon = isPetPost ? item.pets!.system_icon : "person.crop.circle.fill"
                let parsedDate = dateFormatter.date(from: item.created_at) ?? Date()
                
                let uiPost = Post(
                    id: item.id,
                    authorId: item.user_id,
                    authorName: authorName,
                    authorIcon: authorIcon,
                    image: item.image_url ?? "photo.artframe",
                    title: item.title,
                    content: item.content,
                    likes: item.likes_count ?? 0,
                    comments: item.comments_count ?? 0,
                    saves: item.saves_count ?? 0,
                    shares: item.shares_count ?? 0,
                    isLiked: myLikedPostIds.contains(item.id),
                    isSaved: mySavedPostIds.contains(item.id),
                    createdAt: parsedDate
                )
                loadedPosts.append(uiPost)
            }
            self.posts = loadedPosts
        } catch {
            print("Error fetching profile posts: \(error)")
        }
        isLoading = false
    }
}
