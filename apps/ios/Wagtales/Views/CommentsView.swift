import SwiftUI
import Supabase

struct Comment: Identifiable {
    let id: UUID
    let userId: UUID
    let username: String
    let content: String
    var likesCount: Int
    var isLiked: Bool
    let createdAt: Date
    let parentCommentId: UUID? // For replies
    var replies: [Comment] = [] // Holds the threaded replies
    
    var timeAgo: String {
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: createdAt, to: Date())
        if let d = components.day, d > 0 { return "\(d)d" }
        if let h = components.hour, h > 0 { return "\(h)h" }
        if let m = components.minute, m > 0 { return "\(m)m" }
        return "Now"
    }
}

struct CommentsView: View {
    let postId: UUID
    let postOwnerId: UUID
    
    @State private var comments: [Comment] = []
    @State private var newCommentText = ""
    @State private var isPosting = false
    @State private var isLoading = true
    @State private var currentUserId: UUID?
    @State private var replyingToCommentId: UUID? = nil // Remembers the parent
    
    @FocusState private var isInputFocused: Bool
    
    // We pass this back so the FullPostView can instantly update its comment counter
    var onCommentAdded: () -> Void
    
    var onCommentDeleted: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Comments list
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if comments.isEmpty {
                    Spacer()
                    Text("No comments yet. Start the conversation!")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach($comments) { $comment in
                                VStack(spacing: 0) {
                                    // Parent comment
                                    CommentRow(
                                        comment: $comment,
                                        currentUserId: currentUserId,
                                        postOwnerId: postOwnerId,
                                        onReply: { replyUsername in
                                            newCommentText = "@\(replyUsername) "
                                            isInputFocused = true
                                            replyingToCommentId = comment.id // Set parent
                                        },
                                        onDelete: {
                                            Task {
                                                try? await supabase.from("comments").delete().eq("id", value: comment.id).execute()
                                                await fetchComments() // Refresh UI to show the cascade wipe
                                                onCommentDeleted()
                                            }
                                        }
                                    )
                                    
                                    // Indented replies
                                    if !comment.replies.isEmpty {
                                        ForEach($comment.replies) { $reply in
                                            CommentRow(
                                                comment: $reply,
                                                currentUserId: currentUserId,
                                                postOwnerId: postOwnerId,
                                                onReply: { replyUsername in
                                                    newCommentText = "@\(replyUsername) "
                                                    isInputFocused = true
                                                    replyingToCommentId = comment.id // Keep it flat under the parent
                                                },
                                                onDelete: {
                                                    Task {
                                                        try? await supabase.from("comments").delete().eq("id", value: reply.id).execute()
                                                        await fetchComments() // Refresh UI
                                                        onCommentDeleted()
                                                    }
                                                }
                                            )
                                            .padding(.leading, 40) // Indentation
                                            .padding(.top, 12)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
                
                Divider()
                
                // Input bar
                HStack(alignment: .bottom) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title)
                        .foregroundColor(.regalBlue)
                    
                    TextField("Add a comment...", text: $newCommentText, axis: .vertical)
                        .focused($isInputFocused) // Attach the keyboard controller here
                        .lineLimit(1...4)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)
                    
                    Button(action: { Task { await postComment() } }) {
                        if isPosting {
                            ProgressView().padding(.horizontal, 8)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.title2)
                                .foregroundColor(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .regalBlue)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 6)
                        }
                    }
                    .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty || isPosting)
                }
                .padding()
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { Task { await fetchComments() } }
        }
    }
    
    private func fetchComments() async {
        do {
            let myId = try await supabase.auth.session.user.id
            self.currentUserId = myId
            
            struct CommentResponse: Decodable {
                let id: UUID
                let user_id: UUID
                let content: String
                let likes_count: Int?
                let parent_comment_id: UUID?
                let created_at: String
                struct ProfileResp: Decodable { let username: String? }
                let profiles: ProfileResp?
            }
            
            // Fetch comments
            let fetchedData: [CommentResponse] = try await supabase
                .from("comments")
                .select("id, user_id, content, likes_count, parent_comment_id, created_at, profiles(username)")
                .eq("post_id", value: postId)
                .order("created_at", ascending: true) // Oldest first
                .execute()
                .value
            
            // Fetch memory (What did THIS user like?)
            struct ItemRef: Decodable { let comment_id: UUID }
            let likedResp: [ItemRef] = try await supabase.from("comment_likes").select("comment_id").eq("user_id", value: myId).execute().value
            let myLikedIds = Set(likedResp.map { $0.comment_id })
            
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            // Build the objects
            let rawComments = fetchedData.map { item in
                Comment(
                    id: item.id,
                    userId: item.user_id,
                    username: item.profiles?.username ?? "Unknown",
                    content: item.content,
                    likesCount: item.likes_count ?? 0,
                    isLiked: myLikedIds.contains(item.id),
                    createdAt: formatter.date(from: item.created_at) ?? Date(),
                    parentCommentId: item.parent_comment_id
                )
            }
            
            // Organize into threads (parents and replies)
            var parents: [Comment] = []
            var childrenDict: [UUID: [Comment]] = [:]
            
            for c in rawComments {
                if let parentId = c.parentCommentId {
                    childrenDict[parentId, default: []].append(c)
                } else {
                    parents.append(c)
                }
            }
            
            // Attach children to their parents
            for i in 0..<parents.count {
                if let children = childrenDict[parents[i].id] {
                    parents[i].replies = children
                }
            }
            
            self.comments = parents
            
        } catch { print("Fetch comments error: \(error)") }
        isLoading = false
    }
    
    private func postComment() async {
        let text = newCommentText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isPosting = true
        
        do {
            let myId = try await supabase.auth.session.user.id
            self.currentUserId = myId
            // Include the parent_comment_id
            struct InsertComment: Encodable { let post_id: UUID; let user_id: UUID; let content: String; let parent_comment_id: UUID? }
            
            try await supabase.from("comments")
                .insert(InsertComment(
                    post_id: postId,
                    user_id: myId,
                    content: text,
                    parent_comment_id: replyingToCommentId
                ))
                .execute()
            
            newCommentText = ""
            replyingToCommentId = nil // Reset this so the next comment is a normal one
            onCommentAdded() // Tell the post to update its comment count
            await fetchComments() // Refresh the list
        } catch { print("Post comment error: \(error)") }
        isPosting = false
    }
}

// Subview for a single comment row
struct CommentRow: View {
    @Binding var comment: Comment
    
    let currentUserId: UUID?
    let postOwnerId: UUID
    
    var onReply: (String) -> Void
    var onDelete: () -> Void
    
    // Controls the confirmation popup
    @State private var showingDeleteAlert = false
    
    var canDelete: Bool {
        currentUserId == comment.userId || currentUserId == postOwnerId
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            
            // Avatar
            NavigationLink(destination: PublicProfileView(targetUsername: comment.username)) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Username
                    NavigationLink(destination: PublicProfileView(targetUsername: comment.username)) {
                        Text("@\(comment.username)").font(.subheadline).bold().foregroundColor(.primary)
                    }
                    Text(comment.timeAgo).font(.caption).foregroundColor(.gray)
                }
                
                Text(comment.content).font(.subheadline)
                
                // Bottom row of the comment
                HStack(spacing: 16) {
                    Button(action: { onReply(comment.username) }) {
                        Text("Reply").font(.caption).bold().foregroundColor(.gray)
                    }
                }
                .padding(.top, 2)
            }
            
            Spacer()
            
            // Like button for comment
            Button(action: { Task { await toggleCommentLike() } }) {
                VStack(spacing: 4) {
                    Image(systemName: comment.isLiked ? "heart.fill" : "heart")
                        .font(.caption)
                        .foregroundColor(comment.isLiked ? .red : .gray)
                    if comment.likesCount > 0 {
                        Text("\(comment.likesCount)")
                            .font(.caption2)
                            .foregroundColor(comment.isLiked ? .red : .gray)
                    }
                }
            }
        }
        // The native iOS Press-and-Hold menu
        .contentShape(Rectangle()) // Makes the empty space pressable
        .contextMenu {
            if canDelete {
                Button(role: .destructive, action: {
                    showingDeleteAlert = true
                }) {
                    Label("Delete Comment", systemImage: "trash")
                }
            }
        }
        // The confirmation popup
        .alert("Delete Comment?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete() // This runs the database deletion code from CommentsView
            }
        } message: {
            Text("Are you sure you want to delete this comment? This action cannot be undone.")
        }
    }
    
    private func toggleCommentLike() async {
        comment.isLiked.toggle()
        comment.likesCount += comment.isLiked ? 1 : -1
        do {
            let myId = try await supabase.auth.session.user.id
            if comment.isLiked {
                struct InsertData: Encodable { let comment_id: UUID; let user_id: UUID }
                try await supabase.from("comment_likes").insert(InsertData(comment_id: comment.id, user_id: myId)).execute()
            } else {
                try await supabase.from("comment_likes").delete().eq("comment_id", value: comment.id).eq("user_id", value: myId).execute()
            }
        } catch {
            comment.isLiked.toggle()
            comment.likesCount += comment.isLiked ? 1 : -1
        }
    }
}
