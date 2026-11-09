import Foundation

struct Pet: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String // Required
    var species: String // Required
    
    // Optional fields
    var gender: String?
    var breed: String?
    var birthday: String? // String to catch Postgres "YYYY-MM-DD"
    var personality: String?
    var photoUrl: String?
    
    var isBirthdayEstimated: Bool
    var isMemorial: Bool = false
    var systemIcon: String
    
    // These aren't columns in the `pets` table directly
    var photoData: Data? = nil
    var owners: [String]? = ["@dingqianyue"]
    
    // Tell Swift how to map Postgres snake_case to Swift camelCase
    enum CodingKeys: String, CodingKey {
        case id, name, species, gender, breed, birthday, personality
        case isBirthdayEstimated = "is_birthday_estimated"
        case isMemorial = "is_memorial"
        case systemIcon = "system_icon"
        case photoUrl = "photo_url"
    }
    
    // Helper to convert Postgres string to Swift Date
    private var parsedBirthday: Date? {
        guard let bdayString = birthday else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: bdayString)
    }
    
    var ageString: String {
        if isMemorial { return "Forever in our hearts" }
        
        guard let bday = parsedBirthday else { return "Age Unknown" }
        
        let components = Calendar.current.dateComponents([.year, .month], from: bday, to: Date())
        let years = components.year ?? 0
        let months = components.month ?? 0
        
        if years > 0 && months > 0 {
            return "\(years)y \(months)m"
        } else if years > 0 {
            return "\(years) year\(years == 1 ? "" : "s")"
        } else if months > 0 {
            return "\(months) month\(months == 1 ? "" : "s")"
        } else {
            return "Just born!"
        }
    }
    
    // Checks if today is the pet's birthday
    var isBirthdayToday: Bool {
        guard let bdayString = birthday else { return false }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let bdayDate = formatter.date(from: bdayString) else { return false }
        
        let calendar = Calendar.current
        let bdayComponents = calendar.dateComponents([.month, .day], from: bdayDate)
        let todayComponents = calendar.dateComponents([.month, .day], from: Date())
        
        return bdayComponents.month == todayComponents.month && bdayComponents.day == todayComponents.day
    }
}
