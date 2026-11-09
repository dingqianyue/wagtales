import SwiftUI
import Supabase

struct ProfileSearchResult: Codable, Identifiable {
    let id: UUID
    let username: String?
    let full_name: String?
}

struct AddCoOwnerView: View {
    @Environment(\.dismiss) var dismiss
    let petId: UUID
    var onAdd: (String) -> Void // Passes the username back to update the UI
    
    @State private var searchText = ""
    @State private var searchResults: [ProfileSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            VStack {

                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search username...", text: $searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            Task { await searchUsers() }
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage).foregroundColor(.red).font(.caption).padding()
                }
                
                // Results list
                List(searchResults) { user in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(user.full_name ?? "Unknown").font(.headline)
                            Text("@\(user.username ?? "")").font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Add") {
                            Task { await addCoOwner(user: user) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.regalBlue)
                    }
                }
                .listStyle(.plain)
                
                Spacer()
            }
            .navigationTitle("Add Co-owner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if isSearching { ProgressView() }
            }
        }
    }
    
    private func searchUsers() async {
        guard !searchText.isEmpty else { return }
        isSearching = true
        errorMessage = ""
        
        do {
            // Using ilike for case-insensitive partial matching
            let results: [ProfileSearchResult] = try await supabase
                .from("profiles")
                .select("id, username, full_name")
                .ilike("username", pattern: "%\(searchText)%")
                .limit(20)
                .execute()
                .value
            
            searchResults = results
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
        isSearching = false
    }
    
    private func addCoOwner(user: ProfileSearchResult) async {
        guard let username = user.username else { return }
        isSearching = true
        errorMessage = ""
        
        do {
            struct PetOwnerInsert: Codable {
                let pet_id: UUID
                let user_id: UUID
            }
            
            let record = PetOwnerInsert(pet_id: petId, user_id: user.id)
            
            try await supabase
                .from("pet_owners")
                .insert(record)
                .execute()
            
            // Success
            // Update UI on the main thread and dismiss
            await MainActor.run {
                onAdd(username)
                dismiss()
            }
        } catch {
            errorMessage = "Could not add user. They might already be an owner."
        }
        isSearching = false
    }
}
