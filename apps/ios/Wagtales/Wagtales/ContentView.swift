import SwiftUI

struct ContentView: View {
    // Checks if the user is logged in
    @AppStorage("isAuthenticated") var isAuthenticated: Bool = false
    
    // Controls the loading screen visibility
    @State private var isAppLoading: Bool = true
    
    var body: some View {
        ZStack {
            // App state router
            if isAppLoading {
                // State 1: Checking database (loading screen)
                SplashLoadingView()
            } else if isAuthenticated {
                // State 2: User is logged in
                MainTabView()
            } else {
                // State 3: User needs to log in (auth screen)
                AuthView()
            }
        }
        .onAppear {
            checkAuthStatus()
        }
    }
    
    // MARK: - Auth Check Logic
    
    private func checkAuthStatus() {
        // Ask Supabase for the active session
        // For now, we just simulate a 1.5-second loading delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.5)) {
                isAppLoading = false
            }
        }
    }
}

// MARK: - Subviews

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeFeedView()
                .tabItem {
                    Image(systemName: "pawprint.fill")
                    Text("Feed")
                }
            
            CommunityMapView()
                .tabItem {
                    Image(systemName: "map.fill")
                    Text("Map")
                }
            
            ProfileView()
                .tabItem {
                    Image(systemName: "person.crop.circle.fill")
                    Text("Profile")
                }
        }
        .tint(.regalBlue)
    }
}

// A simple loading screen
struct SplashLoadingView: View {
    var body: some View {
        ZStack {
            // Background color
            Color.regalBlue.ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                
                Text("Wagtales")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
                
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
                    .padding(.top, 10)
            }
        }
    }
}

// Preview
#Preview {
    ContentView()
}
