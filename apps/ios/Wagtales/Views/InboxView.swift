import SwiftUI
import Supabase

struct InboxConversation: Identifiable {
    let id: UUID // The other user's ID
    let username: String
    let lastMessage: String
    let timeAgo: String
    let unread: Bool
}

struct InboxView: View {
    @State private var conversations: [InboxConversation] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if conversations.isEmpty {
                    Text("No messages yet. Go make some friends!")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(conversations) { convo in
                        NavigationLink(destination: ChatDetailView(
                            receiverId: convo.id,
                            ownerHandle: convo.username,
                            petName: "Direct"
                        )) {
                            HStack(spacing: 16) {
                                // Avatar
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                
                                // Details
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(convo.username)
                                        .font(.headline)
                                        .fontWeight(convo.unread ? .bold : .medium)
                                    
                                    Text(convo.lastMessage)
                                        .font(.subheadline)
                                        .foregroundColor(convo.unread ? .primary : .secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                // Time
                                Text(convo.timeAgo)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Inbox")
            .task {
                await fetchInbox()
            }
        }
    }
    
    private func fetchInbox() async {
        do {
            let myId = try await supabase.auth.session.user.id
            
            struct InboxResponse: Decodable {
                let other_user_id: UUID
                let other_username: String?
                let last_message: String
                let last_message_time: String
                let is_unread: Bool
            }
            
            // Call the custom RPC function
            let fetchedData: [InboxResponse] = try await supabase
                .rpc("get_user_inbox", params: ["target_user_id": myId])
                .execute()
                .value
            
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            // Convert it to our UI format
            self.conversations = fetchedData.map { item in
                let date = formatter.date(from: item.last_message_time) ?? Date()
                
                return InboxConversation(
                    id: item.other_user_id,
                    username: "@\(item.other_username ?? "Unknown")",
                    lastMessage: item.last_message,
                    timeAgo: formatTimeAgo(date),
                    unread: item.is_unread
                )
            }
        } catch {
            print("Inbox fetch error: \(error)")
        }
        isLoading = false
    }
    
    // Quick helper function for the time display
    private func formatTimeAgo(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: Date())
        if let d = components.day, d > 0 { return "\(d)d" }
        if let h = components.hour, h > 0 { return "\(h)h" }
        if let m = components.minute, m > 0 { return "\(m)m" }
        return "Now"
    }
}
