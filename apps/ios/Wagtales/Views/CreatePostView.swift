import SwiftUI
import Supabase
import PhotosUI

struct CreatePostView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var postTitle = ""
    @State private var postContent = ""
    
    // MARK: - Image Picker State
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    
    // MARK: - Dynamic Author Selection
    struct AuthorOption: Hashable {
        let petId: UUID?
        let name: String
        let icon: String
    }
    
    @State private var authorOptions: [AuthorOption] = []
    @State private var selectedAuthor: AuthorOption?
    
    @State private var isLoadingAuthors = true
    @State private var isPosting = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    
                    // MARK: - Real Photo Selector
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        ZStack {
                            Rectangle()
                                .fill(selectedImageData == nil ? Color(.systemGray6) : Color.clear)
                                .aspectRatio(1, contentMode: .fit)
                            
                            if let data = selectedImageData, let uiImage = UIImage(data: data) {
                                // Show the picked image
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipped()
                            } else {
                                // Placeholder
                                VStack(spacing: 12) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 50))
                                        .foregroundColor(.gray)
                                    Text("Tap to add a square photo")
                                        .font(.headline)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                    .onChange(of: selectedItem) { _, newItem in
                        Task {
                            // Extract raw data when user picks a photo
                            if let rawData = try? await newItem?.loadTransferable(type: Data.self) {
                                
                                // Instantly crop and compress it for the UI preview
                                if let squareData = ImageCompressor.compressAndCropToSquare(data: rawData, maxDimension: 1080, compressionQuality: 0.8) {
                                    // Now the preview shows the perfect square
                                    selectedImageData = squareData
                                }
                            }
                        }
                    }
                    
                    VStack(spacing: 16) {
                        // Error message display
                        if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.top, 8)
                        }
                        
                        HStack {
                            Text("Post As:").font(.subheadline).bold()
                            Spacer()
                            
                            if isLoadingAuthors {
                                ProgressView()
                            } else {
                                Picker("Post As", selection: $selectedAuthor) {
                                    ForEach(authorOptions, id: \.self) { option in
                                        Text(option.name).tag(option as AuthorOption?)
                                    }
                                }
                                .tint(.regalBlue)
                            }
                        }
                        .padding(.top, 16)
                        
                        Divider()
                        
                        TextField("Catchy Title (Max 2 lines)", text: $postTitle, axis: .vertical)
                            .font(.headline)
                            .lineLimit(1...2)
                        
                        Divider()
                        
                        TextField("Write your tips, review, or story here...", text: $postContent, axis: .vertical)
                            .font(.body)
                            .lineLimit(4...10)
                            .frame(minHeight: 100, alignment: .top)
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await fetchAuthors()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.primary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Share") {
                        Task { await submitPost() }
                    }
                    .bold()
                    .foregroundColor(.regalBlue)
                    .disabled(selectedImageData == nil || postTitle.trimmingCharacters(in: .whitespaces).isEmpty || selectedAuthor == nil || isPosting)
                }
            }
            .overlay {
                if isPosting {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("Uploading...").tint(.white).foregroundColor(.white).scaleEffect(1.2)
                }
            }
        }
    }
    
    // MARK: - Database Logic
    private func fetchAuthors() async {
        do {
            let myId = try await supabase.auth.session.user.id
            
            struct ProfileResp: Decodable { let full_name: String? }
            let profile: ProfileResp = try await supabase.from("profiles")
                .select("full_name").eq("id", value: myId).single().execute().value
            
            var options: [AuthorOption] = [
                AuthorOption(petId: nil, name: profile.full_name ?? "Me", icon: "person.crop.circle.fill")
            ]
            
            struct PetResp: Decodable { let id: UUID; let name: String; let system_icon: String }
            struct PetOwnerResp: Decodable { let pets: PetResp? }
            
            let petOwners: [PetOwnerResp] = try await supabase.from("pet_owners")
                .select("pets(id, name, system_icon)")
                .eq("user_id", value: myId)
                .execute()
                .value
            
            for po in petOwners {
                if let pet = po.pets {
                    options.append(AuthorOption(petId: pet.id, name: pet.name, icon: pet.system_icon))
                }
            }
            
            authorOptions = options
            selectedAuthor = options.first
            
        } catch {
            print("Error fetching authors: \(error)")
        }
        isLoadingAuthors = false
    }
    
    private func submitPost() async {
        guard let author = selectedAuthor, let finalImageData = selectedImageData else { return }
        isPosting = true
        errorMessage = nil
        
        do {
            let myId = try await supabase.auth.session.user.id
            let fileName = "\(UUID().uuidString).jpg"
            
            // Upload to Supabase
            try await supabase.storage
                .from("posts")
                .upload(
                    fileName,
                    data: finalImageData,
                    options: FileOptions(contentType: "image/jpeg")
                )
            
            // Get the public URL
            let imageUrl = try supabase.storage
                .from("posts")
                .getPublicURL(path: fileName)
                .absoluteString
            
            // Insert into the database
            struct PostInsert: Encodable {
                let user_id: UUID
                let pet_id: UUID?
                let title: String
                let content: String
                let image_url: String
            }
            
            let newPost = PostInsert(
                user_id: myId,
                pet_id: author.petId,
                title: postTitle,
                content: postContent,
                image_url: imageUrl
            )
            
            try await supabase.from("posts").insert(newPost).execute()
            
            dismiss()
            
        } catch {
            print("Error submitting post: \(error)")
            errorMessage = "Failed to post. Please try again."
        }
        
        isPosting = false
    }
}
