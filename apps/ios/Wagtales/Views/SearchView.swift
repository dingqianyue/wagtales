import SwiftUI
import Supabase

struct SearchView: View {
    @State private var searchText = ""
    @State private var selectedTab: SearchTab = .accounts
    
    @State private var accountResults: [UserResult] = []
    @State private var postResults: [PostResult] = []
    @State private var petResults: [PetResult] = []
    @State private var isSearching = false
    
    enum SearchTab { case accounts, posts, pets }
    
    // MARK: - Data Models
    struct UserResult: Identifiable, Decodable {
        let id: UUID
        let username: String?
        let full_name: String?
    }
    
    struct PostResult: Identifiable, Decodable {
        let id: UUID
        let title: String
        let content: String
    }
    
    // Represents the join table data
    struct PetOwnerResult: Decodable {
        let user_id: UUID
    }
    
    struct PetResult: Identifiable, Decodable {
        let id: UUID
        let name: String
        let system_icon: String
        let photo_url: String?
        // Supabase returns join tables as an array
        let pet_owners: [PetOwnerResult]?
    }
    
    // MARK: - UI
    var body: some View {
        NavigationStack {
            VStack {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search...", text: $searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // Triggers search automatically when typing, with built-in cancellation
                .task(id: searchText) {
                    await performSearch()
                }
                
                Picker("Type", selection: $selectedTab) {
                    Text("Accounts").tag(SearchTab.accounts)
                    Text("Posts").tag(SearchTab.posts)
                    Text("Pets").tag(SearchTab.pets)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: selectedTab) { _ in
                    Task { await performSearch(skipDelay: true) }
                }
                
                List {
                    if isSearching {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if selectedTab == .accounts {
                        ForEach(accountResults) { user in
                            NavigationLink(destination: PublicProfileView(targetUsername: user.username ?? "")) {
                                VStack(alignment: .leading) {
                                    Text(user.full_name ?? "No Name")
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    Text("@\(user.username ?? "")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } else if selectedTab == .posts {
                        ForEach(postResults) { post in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(post.title).font(.headline)
                                Text(post.content).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                            }
                            .padding(.vertical, 4)
                        }
                    } else if selectedTab == .pets {
                        ForEach(petResults) { pet in
                            NavigationLink(destination: PetProfileLoaderView(petId: pet.id)) {
                                HStack(spacing: 12) {
                                    Image(systemName: pet.system_icon)
                                        .foregroundColor(.regalBlue)
                                        .font(.title3)
                                    
                                    Text(pet.name)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                
            }
            .navigationTitle("Search & Explore")
        }
    }
    
    // MARK: - Logic
    private func performSearch(skipDelay: Bool = false) async {
        guard searchText.count > 1 else {
            accountResults = []
            postResults = []
            petResults = []
            isSearching = false
            return
        }
        
        // Debounce: Wait 0.3 seconds before searching
        // If the user types another letter, SwiftUI cancels this task and starts over
        if !skipDelay {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return // Task was cancelled by the user typing again
            }
        }
        
        isSearching = true
        
        do {
            switch selectedTab {
            case .accounts:
                accountResults = try await supabase.from("profiles")
                    .select("id, username, full_name")
                    // .or searches both columns
                    .or("username.ilike.%\(searchText)%,full_name.ilike.%\(searchText)%")
                    .limit(20)
                    .execute()
                    .value
                
            case .posts:
                postResults = try await supabase.from("posts")
                    .select("id, title, content")
                    // .or searches both columns
                    .or("title.ilike.%\(searchText)%,content.ilike.%\(searchText)%")
                    .limit(20)
                    .execute()
                    .value
                
            case .pets:
                petResults = try await supabase.from("pets")
                    // Grab the pet info plus the related user_id from the join table
                    .select("id, name, system_icon, photo_url, pet_owners(user_id)")
                    .ilike("name", pattern: "%\(searchText)%")
                    .limit(20)
                    .execute()
                    .value
            }
        } catch {
            print("Search error: \(error)")
        }
        
        isSearching = false
    }
}

struct PetProfileLoaderView: View {
    let petId: UUID
    @State private var fullPet: Pet?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading Pet...")
            } else if let fullPet = fullPet {
                // Passes the downloaded pet to the actual UI
                PetProfileView(
                    pet: fullPet,
                    onDelete: { /* Handle deletion from search context if needed */ },
                    onUpdate: { _ in /* Handle update */ }
                )
            } else {
                Text("Could not load pet details.")
                    .foregroundColor(.secondary)
            }
        }
        .task {
            await fetchFullPet()
        }
    }
    
    private func fetchFullPet() async {
        do {
            // Downloads the full Pet struct matching the Codable model
            let fetchedPet: Pet = try await supabase
                .from("pets")
                .select("*")
                .eq("id", value: petId)
                .single()
                .execute()
                .value
            
            self.fullPet = fetchedPet
        } catch {
            print("Error loading full pet: \(error)")
        }
        isLoading = false
    }
}
