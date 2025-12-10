import Foundation

public class Tween {
    public static func easeOutQuint(_ t: Float) -> Float {
        return 1 - pow(1 - t, 5)
    }
}
