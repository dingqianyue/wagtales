import SwiftUI
import Supabase

// MARK: - Full Post View
struct FullPostView: View {
    @Binding var post: Post
    @Environment(\.dismiss) var dismiss
    
    @State private var currentUserId: UUID?
    @State private var isDeleting = false
    @State private var showingComments = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Author header
                HStack {
                    if post.authorIcon.hasPrefix("http"), let iconUrl = URL(string: post.authorIcon) {
                        AsyncImage(url: iconUrl) { img in img.resizable().scaledToFill() } placeholder: { Circle().fill(Color.gray) }
                        .frame(width: 32, height: 32).clipShape(Circle())
                    } else {
                        Image(systemName: post.authorIcon).font(.title).foregroundColor(.regalBlue)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.authorName).font(.headline)
                        Text(post.timeAgo).font(.caption).foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    if currentUserId == post.authorId {
                        Button(action: { Task { await deletePost() } }) {
                            if isDeleting { ProgressView() } else { Image(systemName: "trash").foregroundColor(.red) }
                        }.padding(.horizontal)
                    } else {
                        Button("Follow") {}
                            .font(.subheadline).bold().foregroundColor(.regalBlue)
                            .padding(.horizontal, 16).padding(.vertical, 6)
                            .background(Color.regalBlue.opacity(0.1)).cornerRadius(20)
                    }
                }
                .padding(.horizontal)
                
                // Image
                if post.image.hasPrefix("http"), let url = URL(string: post.image) {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color(.systemGray5).overlay(ProgressView()) }
                    .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit).clipped()
                } else {
                    Rectangle().fill(Color(.systemGray6)).aspectRatio(1, contentMode: .fit).overlay(Image(systemName: post.image).font(.system(size: 100)).foregroundColor(.gray))
                }
                
                // Title & content
                VStack(alignment: .leading, spacing: 12) {
                    Text(post.title).font(.title2).bold()
                    Text(post.content).font(.body).lineSpacing(4)
                }
                .padding(.horizontal)
                
                // 4-button action bar
                HStack(spacing: 24) {
                    Button(action: { Task { await toggleLike() } }) {
                        HStack(spacing: 6) {
                            Image(systemName: post.isLiked ? "heart.fill" : "heart").foregroundColor(post.isLiked ? .red : .primary)
                            Text("\(post.likes)").foregroundColor(post.isLiked ? .red : .primary)
                        }
                    }
                    
                    // Comment
                    Button(action: { showingComments = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.right").foregroundColor(.primary)
                            Text("\(post.comments)").foregroundColor(.primary)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { Task { await toggleSave() } }) {
                        HStack(spacing: 6) {
                            Image(systemName: post.isSaved ? "star.fill" : "star").foregroundColor(post.isSaved ? .moonGold : .primary)
                            Text("\(post.saves)").foregroundColor(post.isSaved ? .moonGold : .primary)
                        }
                    }
                    
                    Button(action: { /* Future Share */ }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrowshape.turn.up.right").foregroundColor(.primary)
                            Text("\(post.shares)").foregroundColor(.primary)
                        }
                    }
                }
                .font(.title3)
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .padding(.bottom, 40)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { currentUserId = try? await supabase.auth.session.user.id }
        .sheet(isPresented: $showingComments) {
            CommentsView(
                postId: post.id,
                postOwnerId: post.authorId, // Pass the owner
                onCommentAdded: {
                    post.comments += 1
                },
                onCommentDeleted: {         // Subtract when deleted
                    post.comments = max(0, post.comments - 1)
                }
            )
            .presentationDetents([.medium, .large])
        }
    }
    
    private func toggleLike() async {
        post.isLiked.toggle()
        post.likes += post.isLiked ? 1 : -1
        do {
            let myId = try await supabase.auth.session.user.id
            if post.isLiked {
                struct InsertData: Encodable { let post_id: UUID; let user_id: UUID }
                try await supabase.from("post_likes").insert(InsertData(post_id: post.id, user_id: myId)).execute()
            } else {
                try await supabase.from("post_likes").delete().eq("post_id", value: post.id).eq("user_id", value: myId).execute()
            }
        } catch {
            post.isLiked.toggle()
            post.likes += post.isLiked ? 1 : -1
        }
    }
    
    private func toggleSave() async {
        post.isSaved.toggle()
        post.saves += post.isSaved ? 1 : -1
        do {
            let myId = try await supabase.auth.session.user.id
            if post.isSaved {
                struct InsertData: Encodable { let post_id: UUID; let user_id: UUID }
                try await supabase.from("post_saves").insert(InsertData(post_id: post.id, user_id: myId)).execute()
            } else {
                try await supabase.from("post_saves").delete().eq("post_id", value: post.id).eq("user_id", value: myId).execute()
            }
        } catch {
            post.isSaved.toggle()
            post.saves += post.isSaved ? 1 : -1
        }
    }
    
    private func deletePost() async {
        isDeleting = true
        do {
            if post.image.hasPrefix("http"), let url = URL(string: post.image) {
                let fileName = url.lastPathComponent
                try? await supabase.storage.from("posts").remove(paths: [fileName])
            }
            try await supabase.from("posts").delete().eq("id", value: post.id).execute()
            dismiss()
        } catch { print("Failed to delete post: \(error)") }
        isDeleting = false
    }
}
