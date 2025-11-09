import Foundation

public typealias Vec2 = SIMD2<Float>
public typealias Vec2i = SIMD2<Int32>
public typealias Vec3 = SIMD3<Float>
public typealias Vec4 = SIMD4<Float>

extension Vec2i {
    public func asVec2() -> Vec2 {
        Vec2(Float(x), Float(y))
    }
}

extension Vec2 {
    public func extend(_ z: Float) -> Vec3 {
        Vec3(x, y, z)
    }

    public static func fromAngle(_ angle: Float) -> Vec2 {
        Vec2(cos(angle), sin(angle))
    }
}

public struct Mat4 {
    public var m: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)

    public init(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ c: SIMD4<Float>, _ d: SIMD4<Float>) {
        self.m = (a, b, c, d)
    }

    public static var identity: Mat4 {
        // Column-major 4x4 identity matrix
        return Mat4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    public static func translate(_ v: Vec3) -> Mat4 {
        // Column-major translation matrix
        return Mat4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(v.x, v.y, v.z, 1)
        )
    }

    public static func rotate(_ v: Vec3) -> Mat4 {
        let rotX = Mat4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, cos(v.x), -sin(v.x), 0),
            SIMD4<Float>(0, sin(v.x), cos(v.x), 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        let rotY = Mat4(
            SIMD4<Float>(cos(v.y), 0, sin(v.y), 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(-sin(v.y), 0, cos(v.y), 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        let rotZ = Mat4(
            SIMD4<Float>(cos(v.z), -sin(v.z), 0, 0),
            SIMD4<Float>(sin(v.z), cos(v.z), 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        return rotX * rotY * rotZ
    }

    public static func scale(_ v: Vec3) -> Mat4 {
        // Column-major scale matrix
        return Mat4(
            SIMD4<Float>(v.x, 0, 0, 0),
            SIMD4<Float>(0, v.y, 0, 0),
            SIMD4<Float>(0, 0, v.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    // Matrix multiplication is slow when targeting WASM. Implemented manually for performance.
    public static func * (lhs: Mat4, rhs: Mat4) -> Mat4 {
        let a = lhs.m
        let b = rhs.m

        let col0 = SIMD4<Float>(
            a.0.x * b.0.x + a.1.x * b.0.y + a.2.x * b.0.z + a.3.x * b.0.w,
            a.0.y * b.0.x + a.1.y * b.0.y + a.2.y * b.0.z + a.3.y * b.0.w,
            a.0.z * b.0.x + a.1.z * b.0.y + a.2.z * b.0.z + a.3.z * b.0.w,
            a.0.w * b.0.x + a.1.w * b.0.y + a.2.w * b.0.z + a.3.w * b.0.w
        )
        let col1 = SIMD4<Float>(
            a.0.x * b.1.x + a.1.x * b.1.y + a.2.x * b.1.z + a.3.x * b.1.w,
            a.0.y * b.1.x + a.1.y * b.1.y + a.2.y * b.1.z + a.3.y * b.1.w,
            a.0.z * b.1.x + a.1.z * b.1.y + a.2.z * b.1.z + a.3.z * b.1.w,
            a.0.w * b.1.x + a.1.w * b.1.y + a.2.w * b.1.z + a.3.w * b.1.w
        )
        let col2 = SIMD4<Float>(
            a.0.x * b.2.x + a.1.x * b.2.y + a.2.x * b.2.z + a.3.x * b.2.w,
            a.0.y * b.2.x + a.1.y * b.2.y + a.2.y * b.2.z + a.3.y * b.2.w,
            a.0.z * b.2.x + a.1.z * b.2.y + a.2.z * b.2.z + a.3.z * b.2.w,
            a.0.w * b.2.x + a.1.w * b.2.y + a.2.w * b.2.z + a.3.w * b.2.w
        )
        let col3 = SIMD4<Float>(
            a.0.x * b.3.x + a.1.x * b.3.y + a.2.x * b.3.z + a.3.x * b.3.w,
            a.0.y * b.3.x + a.1.y * b.3.y + a.2.y * b.3.z + a.3.y * b.3.w,
            a.0.z * b.3.x + a.1.z * b.3.y + a.2.z * b.3.z + a.3.z * b.3.w,
            a.0.w * b.3.x + a.1.w * b.3.y + a.2.w * b.3.z + a.3.w * b.3.w
        )
        return Mat4(col0, col1, col2, col3)
    }
}
