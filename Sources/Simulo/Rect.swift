public struct Rect {
    public var pos: Vec2
    public var scale: Vec2

    @MainActor
    public static let zero = Rect(pos: Vec2(0, 0), scale: Vec2(0, 0))

    public init(pos: Vec2, scale: Vec2) {
        self.pos = pos
        self.scale = scale
    }

    public static func fromCentered(pos: Vec2, scale: Vec2) -> Rect {
        Rect(pos: pos - scale / 2, scale: scale)
    }

    public func contains(_ point: Vec2) -> Bool {
        point.x >= pos.x && point.x < pos.x + scale.x && point.y >= pos.y
            && point.y < pos.y + scale.y
    }
}
