import SwiftUI
import Supabase

// MARK: - Single Grid Item
struct GridPostCard: View {
    @Binding var post: Post
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if post.image.hasPrefix("http"), let url = URL(string: post.image) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color(.systemGray5).overlay(ProgressView()) }
                .frame(minWidth: 0, maxWidth: .infinity).aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Rectangle().fill(Color(.systemGray6)).aspectRatio(1, contentMode: .fit).overlay(Image(systemName: post.image).font(.system(size: 40)).foregroundColor(.gray)).cornerRadius(12)
            }
            
            Text(post.title)
                .font(.subheadline)
                .bold()
                .lineLimit(1) // One-line limit
                .truncationMode(.tail) // Add "..." at the end if the title is too long
                .multilineTextAlignment(.leading)
            
            HStack(spacing: 4) {
                if post.authorIcon.hasPrefix("http"), let iconUrl = URL(string: post.authorIcon) {
                    AsyncImage(url: iconUrl) { img in img.resizable().scaledToFill() } placeholder: { Circle().fill(Color.gray) }
                    .frame(width: 16, height: 16).clipShape(Circle())
                } else {
                    Image(systemName: post.authorIcon).font(.caption).foregroundColor(.regalBlue)
                }
                
                Text(post.authorName).font(.caption).foregroundColor(.secondary).lineLimit(1)
                Text("• \(post.timeAgo)").font(.caption).foregroundColor(.gray)
                Spacer()
                
                Button(action: { Task { await toggleLike() } }) {
                    HStack(spacing: 2) {
                        Image(systemName: post.isLiked ? "heart.fill" : "heart").foregroundColor(post.isLiked ? .red : .secondary)
                        Text("\(post.likes)")
                    }
                    .font(.caption).foregroundColor(post.isLiked ? .red : .secondary)
                }
            }
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
}
