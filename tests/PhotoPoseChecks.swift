import Foundation

@main
struct PhotoPoseChecks {
    static func main() {
        let start = Date(timeIntervalSince1970: 1000)
        var pose = PhotoPose()
        precondition(!pose.isActive(at: start))
        pose.request(at: start)
        precondition(pose.isActive(at: start))
        precondition(pose.isActive(at: start.addingTimeInterval(4.999)))
        precondition(!pose.isActive(at: start.addingTimeInterval(5)))
        precondition(!pose.isActive(at: start.addingTimeInterval(30)))
        // Новая съёмка получает собственные пять секунд.
        let nextShot = start.addingTimeInterval(40)
        pose.request(at: nextShot)
        precondition(pose.startedAt == nextShot)
        precondition(pose.isActive(at: nextShot.addingTimeInterval(4)))
        precondition(!pose.isActive(at: nextShot.addingTimeInterval(5)))
        // Ручная подготовка остаётся на 30 секунд; начало съёмки меняет срок на пять.
        pose.request(at: start, duration: 30)
        precondition(pose.isActive(at: start.addingTimeInterval(29)))
        precondition(!pose.isActive(at: start.addingTimeInterval(30)))
        pose.request(at: start.addingTimeInterval(10))
        precondition(pose.isActive(at: start.addingTimeInterval(14.999)))
        precondition(!pose.isActive(at: start.addingTimeInterval(15)))
        print("PASS: exact five-second boundary, repeated shots, manual preparation, capture overriding preparation.")
    }
}
