import SwiftUI
import Supabase

// MARK: - Data Model
struct Post: Identifiable {
    let id: UUID
    let authorId: UUID
    let authorName: String
    let authorIcon: String
    let image: String
    let title: String
    let content: String
    
    // Interaction counts
    var likes: Int
    var comments: Int
    var saves: Int
    var shares: Int
    
    // User status
    var isLiked: Bool = false
    var isSaved: Bool = false
    
    let createdAt: Date
        
    // Automatically calculates the "time ago" format, including years
    var timeAgo: String {
        let now = Date()
        let calendar = Calendar.current
        
        // Grab the time differences
        let components = calendar.dateComponents([.minute, .hour, .day], from: createdAt, to: now)
        
        // Grab the actual years to compare them
        let postYear = calendar.component(.year, from: createdAt)
        let currentYear = calendar.component(.year, from: now)
        
        let formatter = DateFormatter()
        
        if postYear != currentYear {
            // Different year (e.g., "Oct 14, 2025")
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: createdAt)
        } else if let days = components.day, days >= 7 {
            // Same year, but over a week old (e.g., "Feb 27")
            formatter.dateFormat = "MMM d"
            return formatter.string(from: createdAt)
        } else if let days = components.day, days > 0 {
            // Within the last week
            return "\(days)d"
        } else if let hours = components.hour, hours > 0 {
            // Within the last day
            return "\(hours)h"
        } else if let minutes = components.minute, minutes > 0 {
            // Within the last hour
            return "\(minutes)m"
        } else {
            // Just posted
            return "Now"
        }
    }
}
