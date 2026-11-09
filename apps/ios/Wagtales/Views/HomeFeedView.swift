import SwiftUI
import Supabase

// MARK: - Main Feed View
struct HomeFeedView: View {
    @State private var showingCreatePost = false
    @State private var selectedTab = "Explore"
    @State private var searchText = ""
    @State private var posts: [Post] = []
    @State private var isLoading = true
    @State private var hasUnreadNotifications = false
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top custom tab bar
                HStack(spacing: 30) {
                    FeedTabButton(title: "Following", currentTab: $selectedTab)
                    FeedTabButton(title: "Explore", currentTab: $selectedTab)
                }
                .padding(.top, 10)
                .padding(.bottom, 8)
                
                if isLoading {
                    Spacer()
                    ProgressView("Loading Feed...")
                    Spacer()
                } else if posts.isEmpty {
                    Spacer()
                    Text("No posts yet. Be the first!")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    // The grid
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach($posts) { $post in
                                NavigationLink(destination: FullPostView(post: $post)) {
                                    GridPostCard(post: $post)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                        .padding(.top, 10)
                    }
                    // Pull to refresh
                    .refreshable {
                        await fetchPosts()
                    }
                } // End of else block
            }
            .onChange(of: selectedTab) {
                Task {
                    posts = [] // Clears the screen instantly so it feels responsive
                    await fetchPosts()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Inbox/notification button on the left
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: InboxView()) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                                .font(.body)
                                .bold()
                                .foregroundColor(.primary)
                            
                            // The unread red dot
                            if hasUnreadNotifications {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                    .offset(x: 2, y: -2) // Pushes it perfectly to the top-right edge
                            }
                        }
                    }
                }
                
                // Search and create buttons on the right
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        NavigationLink(destination: SearchView()) {
                            Image(systemName: "magnifyingglass").font(.body).bold().foregroundColor(.primary)
                        }
                        
                        Button(action: { showingCreatePost = true }) {
                            Image(systemName: "plus.app").font(.body).bold().foregroundColor(.primary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCreatePost) {
                CreatePostView()
                    // When the sheet is dismissed, refresh the feed to show the new post
                    .onDisappear {
                        Task { await fetchPosts() }
                    }
            }
            .onAppear {
                // Force a silent database check every time this page becomes visible
                Task {
                    await fetchPosts()
                }
            }
        }
    }
    
    // MARK: - Database Logic
    private func fetchPosts() async {
        
        // Only show the spinner if we have absolutely no posts yet
        if posts.isEmpty { isLoading = true }
        
        do {
            let myId = try await supabase.auth.session.user.id
            
            // Check for unread messages
            let unreadCount = try? await supabase.from("chat_messages")
                .select("id", head: true, count: .exact)
                .eq("receiver_id", value: myId) // Messages sent to me
                .eq("is_read", value: false)    // That are not read yet
                .execute().count
            
            self.hasUnreadNotifications = (unreadCount ?? 0) > 0
            
            // Everything that could possibly be empty is optional (?)
            struct PostResponse: Decodable {
                let id: UUID
                let user_id: UUID
                let pet_id: UUID? // We need this to check pet follows
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
            
            // Base query
            let baseQuery = supabase
                .from("posts")
                .select("id, user_id, pet_id, title, content, image_url, likes_count, saves_count, comments_count, shares_count, created_at, profiles(full_name, username), pets(name, system_icon)")
            
            // Declare the array here so both paths can fill it
            let fetchedData: [PostResponse]
            
            // Apply the feed filters
            if selectedTab == "Following" {
                
                // Fetch human follows
                struct FollowedHuman: Decodable { let following_id: UUID }
                let humanResp: [FollowedHuman] = (try? await supabase.from("user_follows").select("following_id").eq("follower_id", value: myId).execute().value) ?? []
                let followedHumanIds = humanResp.map { $0.following_id }
                
                // Fetch pet follows
                struct FollowedPet: Decodable { let pet_id: UUID }
                let petResp: [FollowedPet] = (try? await supabase.from("pet_followers").select("pet_id").eq("user_id", value: myId).execute().value) ?? []
                let followedPetIds = petResp.map { $0.pet_id }
                
                // Safety check: Are they following anyone at all?
                if followedHumanIds.isEmpty && followedPetIds.isEmpty {
                    // Fast exit: They don't follow anyone yet, so the feed is instantly empty
                    fetchedData = []
                } else {
                    // Build the Supabase "OR" filter cleanly
                    var filterParts: [String] = []
                    
                    if !followedHumanIds.isEmpty {
                        let humanIdsString = followedHumanIds.map { "\($0)" }.joined(separator: ",")
                        filterParts.append("user_id.in.(\(humanIdsString))")
                    }
                    
                    if !followedPetIds.isEmpty {
                        let petIdsString = followedPetIds.map { "\($0)" }.joined(separator: ",")
                        filterParts.append("pet_id.in.(\(petIdsString))")
                    }
                    
                    let filterString = filterParts.joined(separator: ",")
                    
                    // Fetch, explicitly block their own posts, and sort by newest
                    fetchedData = try await baseQuery
                        .or(filterString)
                        .neq("user_id", value: myId) // Guarantees none of your posts appear
                        .order("created_at", ascending: false)
                        .execute()
                        .value
                }
                
            } else {
                // Explore tab
                // Sort by likes first (trending), then by newest as a tiebreaker
                fetchedData = try await baseQuery
                    .order("likes_count", ascending: false)
                    .order("created_at", ascending: false)
                    .execute()
                    .value
            }
            
            // Fetch memory (likes & saves)
            struct ItemRef: Decodable { let post_id: UUID }
            let likedResp: [ItemRef] = (try? await supabase.from("post_likes").select("post_id").eq("user_id", value: myId).execute().value) ?? []
            let myLikedIds = Set(likedResp.map { $0.post_id })
            
            let savedResp: [ItemRef] = (try? await supabase.from("post_saves").select("post_id").eq("user_id", value: myId).execute().value) ?? []
            let mySavedIds = Set(savedResp.map { $0.post_id })
            
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            // Build the UI posts
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
                    isLiked: myLikedIds.contains(item.id),
                    isSaved: mySavedIds.contains(item.id),
                    createdAt: parsedDate
                )
                loadedPosts.append(uiPost)
            }
            
            self.posts = loadedPosts
        } catch {
            print("Fetch feed error: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Top Tab Button Custom UI
struct FeedTabButton: View {
    let title: String
    @Binding var currentTab: String
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
                .fontWeight(currentTab == title ? .bold : .medium)
                .foregroundColor(currentTab == title ? .primary : .secondary)
            
            Rectangle()
                .fill(currentTab == title ? Color.regalBlue : Color.clear)
                .frame(width: 30, height: 3)
                .cornerRadius(1.5)
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentTab = title
            }
        }
    }
}
