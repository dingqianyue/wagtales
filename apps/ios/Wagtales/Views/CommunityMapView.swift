import SwiftUI
import MapKit

// MARK: - Privacy & Data Models
enum LocationPrivacy: String, CaseIterable {
    case ghost = "Ghost Mode"
    case mutualsFuzzy = "Mutuals (Fuzzy)"
    case mutualsExact = "Mutuals (Exact)"
    case everyoneFuzzy = "Everyone (Fuzzy)"
    
    var icon: String {
        switch self {
        case .ghost: return "eye.slash.fill"
        case .mutualsFuzzy, .mutualsExact: return "person.2.fill"
        case .everyoneFuzzy: return "globe.americas.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .ghost: return .gray
        case .mutualsFuzzy, .mutualsExact: return .purple
        case .everyoneFuzzy: return .regalBlue
        }
    }
}

struct Hazard: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var coordinate: CLLocationCoordinate2D
    var upvotes: Int
    var downvotes: Int
    
    static func == (lhs: Hazard, rhs: Hazard) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Main Map View
struct CommunityMapView: View {
    @StateObject private var locationManager = LocationManager()
    
    @State private var privacyState: LocationPrivacy = .ghost
    
    @State private var hazards = [
        Hazard(title: "Broken Glass", coordinate: CLLocationCoordinate2D(latitude: 39.9545, longitude: -75.1630), upvotes: 3, downvotes: 0)
    ]
    @State private var selectedHazard: Hazard?
    
    // UI filters
    @State private var showHazards = true
    @State private var showActivePets = true
    @State private var showPlaces = false
    @State private var showingReportForm = false
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                
                // The map
                Map(selection: $selectedHazard) {
                    
                    UserAnnotation()
                    
                    if showActivePets {
                        // Mock user 1: Stranger sharing Fuzzy
                        MapCircle(center: CLLocationCoordinate2D(latitude: 39.9526, longitude: -75.1652), radius: 300)
                            .foregroundStyle(Color.regalBlue.opacity(0.15))
                            .stroke(Color.regalBlue.opacity(0.5), lineWidth: 2)
                        
                        Annotation("Max's Zone", coordinate: CLLocationCoordinate2D(latitude: 39.9526, longitude: -75.1652)) {
                            Image(systemName: "dog.circle.fill").font(.title).foregroundColor(.regalBlue).background(.white).clipShape(Circle())
                        }.tag(UUID())
                        
                        // Mock user 2: Mutual sharing Exact
                        Annotation("Pushpa", coordinate: CLLocationCoordinate2D(latitude: 39.9560, longitude: -75.1610)) {
                            VStack(spacing: 0) {
                                Image(systemName: "cat.circle.fill").font(.title).foregroundColor(.brown).background(.white).clipShape(Circle())
                            }
                        }.tag(UUID())
                    }
                    
                    if showHazards {
                        ForEach(hazards) { hazard in
                            Marker(hazard.title, systemImage: "exclamationmark.triangle.fill", coordinate: hazard.coordinate)
                                .tint(.red)
                                .tag(hazard)
                        }
                    }
                    
                    if showPlaces {
                        Marker("Pet-Friendly Cafe", systemImage: "cup.and.saucer.fill", coordinate: CLLocationCoordinate2D(latitude: 39.9510, longitude: -75.1640))
                            .tint(.green)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                
                // Overlays
                VStack(spacing: 12) {
                    privacyDropdown
                    filterPills
                }
                
                // Floating report button
                VStack {
                    Spacer()
                    Button(action: { showingReportForm = true }) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Report Hazard")
                        }
                        .font(.headline)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(30)
                        .shadow(radius: 5)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Community Map")
            .navigationBarTitleDisplayMode(.inline)
            
            // Sheets
            .sheet(item: $selectedHazard) { hazard in
                HazardDetailSheet(hazard: hazard).presentationDetents([.fraction(0.3)])
            }
            .sheet(isPresented: $showingReportForm) {
                ReportHazardView { newHazard in hazards.append(newHazard) }
                    .presentationDetents([.medium, .large])
            }
        }
    }
    
    // MARK: - Subviews
    private var privacyDropdown: some View {
        HStack {
            Menu {
                ForEach(LocationPrivacy.allCases, id: \.self) { option in
                    Button(action: { withAnimation { privacyState = option } }) {
                        Label(option.rawValue, systemImage: option.icon)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: privacyState.icon)
                    Text(privacyState.rawValue).fontWeight(.semibold)
                    Image(systemName: "chevron.down").font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
                .foregroundColor(privacyState.color)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.15), radius: 5)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                FilterButton(title: "Hazards", icon: "exclamationmark.triangle.fill", isOn: $showHazards, color: .red)
                FilterButton(title: "Active Pets", icon: "pawprint.fill", isOn: $showActivePets, color: .regalBlue)
                FilterButton(title: "Places", icon: "building.2.fill", isOn: $showPlaces, color: .green)
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Helper Views
struct FilterButton: View {
    var title: String
    var icon: String
    @Binding var isOn: Bool
    var color: Color
    
    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isOn ? color : Color(.systemGray6))
            .foregroundColor(isOn ? .white : .primary)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.1), radius: 3)
        }
    }
}

struct HazardDetailSheet: View {
    var hazard: Hazard
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text(hazard.title)
                .font(.title2)
                .bold()
            
            Text("Reported recently. Is this still an issue?")
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                Button(action: {
                    print("Still there! +5 Points to user.")
                    dismiss()
                }) {
                    VStack {
                        Image(systemName: "checkmark.circle.fill").font(.title)
                        Text("Still There (\(hazard.upvotes))")
                    }
                    .foregroundColor(.amber)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                Button(action: {
                    print("Resolved! +5 Points to user.")
                    dismiss()
                }) {
                    VStack {
                        Image(systemName: "xmark.circle.fill").font(.title)
                        Text("Resolved (\(hazard.downvotes))")
                    }
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            Spacer()
        }
        .padding(.top, 24)
    }
}

struct ReportHazardView: View {
    @Environment(\.dismiss) var dismiss
    var onSave: (Hazard) -> Void
    
    @State private var selectedHazardType = "Poison Bait"
    @State private var customDescription = ""
    
    let hazardOptions = [
        "Poison Bait", "Broken Glass", "Aggressive Off-Leash Dog",
        "Foxtails / Toxic Plants", "Coyote Sighting", "Pesticide Spraying", "Other"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("What did you spot?"), footer: Text("Your report will instantly alert users walking nearby.")) {
                    Picker("Hazard Type", selection: $selectedHazardType) {
                        ForEach(hazardOptions, id: \.self) { option in Text(option).tag(option) }
                    }.pickerStyle(.navigationLink)
                    
                    if selectedHazardType == "Other" {
                        TextField("Describe the hazard...", text: $customDescription)
                    }
                }
            }
            .navigationTitle("Report Hazard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.primary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Drop Pin") { submitReport() }
                    .bold()
                    .foregroundColor(.red)
                    .disabled(selectedHazardType == "Other" && customDescription.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    private func submitReport() {
        let finalTitle = selectedHazardType == "Other" ? customDescription : selectedHazardType
        let mockCurrentLocation = CLLocationCoordinate2D(latitude: 39.9535, longitude: -75.1645)
        let newHazard = Hazard(title: finalTitle, coordinate: mockCurrentLocation, upvotes: 1, downvotes: 0)
        
        onSave(newHazard)
        dismiss()
    }
}

#Preview {
    CommunityMapView()
}
