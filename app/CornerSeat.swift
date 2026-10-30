import Foundation

/// Место в нижнем углу рабочей области, с отступом для второго питомца.
enum CornerSeat {
    static func origin(in area: CGRect, size: CGFloat, order: Int, left: Bool) -> CGPoint {
        let offset = CGFloat(max(0, order)) * size * 0.95
        let x = left ? area.minX + 8 + offset : area.maxX - size - 8 - offset
        return CGPoint(x: min(max(area.minX, x), max(area.minX, area.maxX - size)), y: area.minY)
    }
}
