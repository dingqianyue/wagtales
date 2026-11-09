import SwiftUI
import Supabase

// MARK: - Data Models
struct ChatMessage: Identifiable {
    let id: UUID
    let text: String
    let isCurrentUser: Bool
    let createdAt: Date
}

enum RelationshipStatus {
    case loading
    case mutual
    case strangerCanMessage
    case strangerRequestPending
}

// MARK: - Chat View
struct ChatDetailView: View {
    let receiverId: UUID // We need to know who we are texting
    let ownerHandle: String
    let petName: String
    
    // UI state
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var status: RelationshipStatus = .loading
    @State private var currentUserId: UUID?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if status == .loading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else {
                    // Chat history
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 12) {
                                // Trust/Safety banner
                                if status != .mutual {
                                    Text("For community safety, you can only send one message until they reply.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding()
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                        .padding(.horizontal)
                                        .padding(.top, 8)
                                }
                                
                                // Message bubbles
                                ForEach(messages) { message in
                                    HStack {
                                        if message.isCurrentUser { Spacer() }
                                        
                                        Text(message.text)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(message.isCurrentUser ? Color.regalBlue : Color(.systemGray5))
                                            .foregroundColor(message.isCurrentUser ? .white : .primary)
                                            .cornerRadius(20)
                                        
                                        if !message.isCurrentUser { Spacer() }
                                    }
                                    .padding(.horizontal)
                                    .id(message.id) // Used for auto-scrolling
                                }
                            }
                            .padding(.top)
                        }
                        .onChange(of: messages.count) {
                            // Auto-scroll to the bottom when a new message appears
                            if let last = messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Smart input area
                    inputArea
                }
            }
            .navigationTitle("\(ownerHandle) (\(petName)'s Owner)")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                currentUserId = try? await supabase.auth.session.user.id
                await loadChatAndStatus()
            }
        }
    }
    
    // MARK: - Subviews
    @ViewBuilder
    private var inputArea: some View {
        switch status {
        case .mutual, .strangerCanMessage:
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                
                Button(action: { Task { await sendMessage() } }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .regalBlue)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            
        case .strangerRequestPending:
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").foregroundColor(.secondary)
                Text("Message sent. Waiting for them to reply...")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity).padding().background(Color(.systemGray6))
            
        case .loading:
            EmptyView()
        }
    }
    
    // MARK: - Database Logic
    private func loadChatAndStatus() async {
        guard let myId = currentUserId else { return }
        
        do {
            // Mark all messages sent TO me from THEM as read
            struct UpdateRead: Encodable { let is_read: Bool }
            try? await supabase.from("chat_messages")
                .update(UpdateRead(is_read: true))
                .eq("sender_id", value: receiverId) // Sent BY them
                .eq("receiver_id", value: myId)     // Sent TO me
                .execute()
            
            // Fetch chat history between these two users
            struct MsgResp: Decodable {
                let id: UUID
                let sender_id: UUID
                let text: String
                let created_at: String
            }
            
            // Get messages where (sender=me AND receiver=them) OR (sender=them AND receiver=me)
            let filter = "and(sender_id.eq.\(myId),receiver_id.eq.\(receiverId)),and(sender_id.eq.\(receiverId),receiver_id.eq.\(myId))"
            
            let fetchedMsgs: [MsgResp] = try await supabase.from("chat_messages")
                .select()
                .or(filter)
                .order("created_at", ascending: true)
                .execute().value
            
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            self.messages = fetchedMsgs.map { m in
                ChatMessage(
                    id: m.id,
                    text: m.text,
                    isCurrentUser: m.sender_id == myId,
                    createdAt: formatter.date(from: m.created_at) ?? Date()
                )
            }
            
            // Figure out the relationship status
            // Does the receiver follow me?
            let followCount = try await supabase.from("user_follows")
                .select("*", head: true, count: .exact)
                .eq("follower_id", value: receiverId) // The other person
                .eq("following_id", value: myId)      // is following me
                .execute().count ?? 0
            
            if followCount > 0 {
                // They follow you. Free chat!
                self.status = .mutual
            } else {
                // They DO NOT follow you. Check message history for the lock.
                let myMessages = self.messages.filter { $0.isCurrentUser }
                let theirMessages = self.messages.filter { !$0.isCurrentUser }
                
                if theirMessages.count > 0 {
                    // They have replied at least once! Chat is unlocked forever.
                    self.status = .mutual
                } else if myMessages.count > 0 {
                    // I sent a message, but they haven't replied. Lock it!
                    self.status = .strangerRequestPending
                } else {
                    // Total blank slate. I can send 1 message.
                    self.status = .strangerCanMessage
                }
            }
            
        } catch { print("Chat error: \(error)") }
    }
    
    private func sendMessage() async {
        guard let myId = currentUserId else { return }
        let textToSend = inputText.trimmingCharacters(in: .whitespaces)
        guard !textToSend.isEmpty else { return }
        
        // Optimistic UI update
        let tempId = UUID()
        let newMsg = ChatMessage(id: tempId, text: textToSend, isCurrentUser: true, createdAt: Date())
        messages.append(newMsg)
        inputText = ""
        
        if status == .strangerCanMessage {
            status = .strangerRequestPending // Lock it immediately
        }
        
        // Save to database
        do {
            struct InsertMsg: Encodable { let sender_id: UUID; let receiver_id: UUID; let text: String }
            try await supabase.from("chat_messages").insert(InsertMsg(sender_id: myId, receiver_id: receiverId, text: textToSend)).execute()
        } catch {
            print("Failed to send message: \(error)")
        }
    }
}
