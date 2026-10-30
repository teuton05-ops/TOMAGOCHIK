import Foundation

/// Отдельное время позирования: обычные действия и поглаживание его не перебивают.
struct PhotoPose {
    private(set) var startedAt = Date.distantPast
    private(set) var until = Date.distantPast

    func isActive(at now: Date) -> Bool { now < until }

    mutating func request(at now: Date, duration: TimeInterval = 5) {
        startedAt = now
        until = now.addingTimeInterval(duration)
    }
}
