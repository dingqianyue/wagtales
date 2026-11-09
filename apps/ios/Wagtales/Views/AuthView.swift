import SwiftUI
import Supabase

struct ProfileToInsert: Codable {
    let id: UUID
    let username: String
    let full_name: String
}

struct AuthView: View {
    @AppStorage("isAuthenticated") var isAuthenticated: Bool = false
    
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var fullName = ""
    
    @State private var isSignUp = false
    @State private var isLoading = false
    
    // Alert state variables
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    // MARK: - Password Validation
    var isPasswordValid: Bool {
        let hasUpper = password.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLower = password.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasNumber = password.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSymbol = password.rangeOfCharacter(from: CharacterSet.punctuationCharacters.union(.symbols)) != nil
        
        return password.count >= 8 && hasUpper && hasLower && hasNumber && hasSymbol
    }
    
    // MARK: - Username Validation
    var isUsernameValid: Bool {
        guard let firstChar = username.first else { return false }
        
        // Must start with a lowercase letter (a-z)
        let startingCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        if String(firstChar).rangeOfCharacter(from: startingCharacters.inverted) != nil {
            return false
        }
        
        // The rest can be lowercase letters, numbers, or underscores
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        return username.rangeOfCharacter(from: allowedCharacters.inverted) == nil
    }
    
    // MARK: - Form Validation
    var isFormValid: Bool {
        if isSignUp {
            return !email.isEmpty && isPasswordValid && isUsernameValid && !fullName.isEmpty
        } else {
            return !email.isEmpty && !password.isEmpty
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "pawprint.fill")
                .font(.system(size: 80))
                .foregroundColor(.regalBlue)
                .padding(.bottom, 20)
            
            Text(isSignUp ? "Create Account" : "Welcome Back")
                .font(.largeTitle)
                .bold()
            
            VStack(spacing: 16) {
                if isSignUp {
                    // Username field
                    HStack {
                        Text("@").foregroundColor(.secondary)
                        TextField("Username", text: $username)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: username) { newValue in
                                // Automatically lowercase and replace spaces with underscores
                                username = newValue.lowercased().replacingOccurrences(of: " ", with: "_")
                            }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Username hint (only shows if they type something wrong)
                    if isSignUp && !username.isEmpty && !isUsernameValid {
                        Text("Usernames must start with a letter and can only contain lowercase letters, numbers, and underscores.")
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 4)
                            .padding(.top, -8)
                    }
                    
                    // Full name field (displayed as Nickname)
                    TextField("Nickname", text: $fullName)
                        .textContentType(.nickname)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
                
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                
                SecureField("Password", text: $password)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                
                // Forgot Password button (only on log in)
                if !isSignUp {
                    Button(action: {
                        Task { await resetPassword() }
                    }) {
                        Text("Forgot Password?")
                            .font(.caption)
                            .bold()
                            .foregroundColor(.regalBlue)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, -8)
                }
                
                // Password hint
                if isSignUp {
                    Text("Password must be at least 8 characters, with an uppercase letter, lowercase letter, a number, and a special character.")
                        .font(.caption)
                        .foregroundColor(isPasswordValid ? .green : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 24)
            
            Button(action: {
                Task { await authenticate() }
            }) {
                HStack {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(isSignUp ? "Sign Up" : "Log In")
                            .bold()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.regalBlue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .disabled(!isFormValid || isLoading)
            
            // Toggle button with partial underlining
            Button(action: {
                withAnimation { isSignUp.toggle() }
            }) {
                if isSignUp {
                    (Text("Already have an account? ") + Text("Log In").underline())
                        .foregroundColor(.regalBlue)
                        .font(.subheadline)
                        .bold()
                } else {
                    (Text("Don't have an account? ") + Text("Sign Up").underline())
                        .foregroundColor(.regalBlue)
                        .font(.subheadline)
                        .bold()
                }
            }
            .padding(.top, 10)
            
            Spacer()
        }
        // The iOS pop-up alert
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK")) {
                    if alertTitle == "Success!" {
                        if isSignUp {
                            // If they just signed up, slide over to the log in screen
                            withAnimation {
                                isSignUp = false
                                password = "" // Clear the password so they have to type it
                            }
                        } else {
                            // If they just logged in, let them into the dashboard
                            withAnimation { isAuthenticated = true }
                        }
                    }
                }
            )
        }
    }
    
    // MARK: - Supabase Authentication Logic
    private func authenticate() async {
        isLoading = true
        
        do {
            if isSignUp {
                // Check if the username is already taken
                let existingProfiles: [ProfileToInsert] = try await supabase
                    .from("profiles")
                    .select("id, username, full_name")
                    .eq("username", value: username)
                    .execute()
                    .value
                
                if !existingProfiles.isEmpty {
                    throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "That username is already taken! Please choose another."])
                }
                
                // If it's free, create the secure login account
                let response = try await supabase.auth.signUp(email: email, password: password)
                
                // Take their new secure ID, and create their public profile row
                let userId = response.user.id
                let newProfile = ProfileToInsert(id: userId, username: username, full_name: fullName)
                try await supabase.from("profiles").insert(newProfile).execute()
                
                alertTitle = "Success!"
                alertMessage = "Your account has been created. Please log in."
                
            } else {
                // Log in logic
                let _ = try await supabase.auth.signIn(email: email, password: password)
                alertTitle = "Success!"
                alertMessage = "Welcome back!"
            }
            
            showAlert = true
            isLoading = false
            
        } catch {
            alertTitle = "Oops!"
            alertMessage = error.localizedDescription
            showAlert = true
            isLoading = false
        }
    }
    
    // MARK: - Password Reset Logic
    private func resetPassword() async {
        // Make sure they actually typed an email first
        guard !email.isEmpty else {
            alertTitle = "Email Required"
            alertMessage = "Please enter your email address above so we know where to send the reset link."
            showAlert = true
            return
        }
        
        isLoading = true
        
        // Tell Supabase to send the email
        do {
            try await supabase.auth.resetPasswordForEmail(email)
            
            alertTitle = "Check your inbox!"
            alertMessage = "If an account exists for that email, we've sent a password reset link."
            showAlert = true
            isLoading = false
            
        } catch {
            alertTitle = "Oops!"
            alertMessage = error.localizedDescription
            showAlert = true
            isLoading = false
        }
    }
}
