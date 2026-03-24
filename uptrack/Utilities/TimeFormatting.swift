import Foundation

enum TimeFormatting {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    /// Formats a duration in seconds to a human-readable string like "1h 23m", "45m", "2m"
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }

    /// Formats a time range like "2:30 PM – 3:15 PM"
    static func formatTimeRange(from start: Date, to end: Date?) -> String {
        let startStr = timeFormatter.string(from: start)
        if let end {
            let endStr = timeFormatter.string(from: end)
            return "\(startStr) – \(endStr)"
        } else {
            return "\(startStr) – now"
        }
    }

    /// Returns "Today", "Yesterday", or a formatted date like "March 5, 2026"
    static func formatRelativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return dateFormatter.string(from: date)
        }
    }

    /// Returns "listening for X minutes" style string
    static func formatListeningDuration(since start: Date) -> String {
        let seconds = Date().timeIntervalSince(start)
        let minutes = Int(seconds / 60)

        if minutes < 1 {
            return "listening for less than a minute"
        } else if minutes == 1 {
            return "listening for 1 minute"
        } else {
            return "listening for \(minutes) minutes"
        }
    }

    /// Formats a duration between two dates
    static func formatSessionDuration(from start: Date, to end: Date?) -> String {
        let seconds = (end ?? Date()).timeIntervalSince(start)
        return formatDuration(seconds)
    }
}
