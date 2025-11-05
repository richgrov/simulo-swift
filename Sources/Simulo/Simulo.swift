import Foundation

@_extern(wasm, module: "env", name: "simulo_poll")
@_extern(c)
func simulo_poll(buf: UnsafeMutablePointer<UInt8>, len: UInt32) -> Int32

@_extern(wasm, module: "env", name: "simulo_create_rendered_object2")
@_extern(c)
func simulo_create_rendered_object2(material: UInt32, renderOrder: UInt32) -> UInt32
@_extern(wasm, module: "env", name: "simulo_set_rendered_object_material")
@_extern(c)
func simulo_set_rendered_object_material(id: UInt32, material: UInt32)
@_extern(wasm, module: "env", name: "simulo_set_rendered_object_transforms")
@_extern(c)
func simulo_set_rendered_object_transforms(
    count: UInt32, ids: UnsafePointer<UInt32>, matrices: UnsafePointer<Float>)
@_extern(wasm, module: "env", name: "simulo_drop_rendered_object")
@_extern(c)
func simulo_drop_rendered_object(id: UInt32)

@_extern(wasm, module: "env", name: "simulo_create_material")
@_extern(c)
func simulo_create_material(
    namePtr: UInt32, nameLen: UInt32, tintR: Float32, tintG: Float32, tintB: Float32, tintA: Float32
) -> UInt32
@_extern(wasm, module: "env", name: "simulo_drop_material")
@_extern(c)
func simulo_drop_material(id: UInt32)

@MainActor
var transformedObjects = [ObjectIdentifier: Object]()

@MainActor
open class Game {
    var objects: [Object] = []
    var windowSize = Vec2i(0, 0)

    public init() {}

    public func addObject(_ object: Object) {
        objects.append(object)
    }

    public func deleteObject(_ object: Object) {
        objects.removeAll { $0 === object }
    }
}

@MainActor
public func run(_ game: Game) {
    let capacity = 1024 * 32
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    defer { buf.deallocate() }

    var poses: [UInt32: [Float]] = [:]

    var time = Int64(Date().timeIntervalSince1970 * 1000)

    while true {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let delta = now - time
        time = now

        let len = simulo_poll(buf: buf, len: UInt32(capacity))
        if len < 0 { break }
        if len > 0 {
            var offset = 0
            let limit = Int(len)

            while offset < limit {
                let eventType = buf[offset]
                offset += 1

                switch eventType {
                case 0:  // upsert/move with pose
                    guard offset + 4 <= limit else { return }
                    let id = readUInt32BE(from: buf, offset: &offset, limit: limit)

                    // Read 17 pairs of i16 (big-endian) -> 34 floats
                    var pose: [Float] = Array(repeating: 0, count: 17 * 2)
                    for i in 0..<17 {
                        guard offset + 4 <= limit else { return }
                        let x = Float(readInt16BE(from: buf, offset: &offset, limit: limit))
                        let y = Float(readInt16BE(from: buf, offset: &offset, limit: limit))
                        pose[i * 2] = x
                        pose[i * 2 + 1] = y
                    }

                    if poses[id] != nil {
                        poses[id] = pose
                    } else {
                        poses[id] = pose
                    }

                case 1:  // delete by id
                    guard offset + 4 <= limit else { return }
                    let id = readUInt32BE(from: buf, offset: &offset, limit: limit)
                    poses.removeValue(forKey: id)

                case 2:  // window resize
                    guard offset + 4 <= limit else { return }
                    let width = readUInt16BE(from: buf, offset: &offset, limit: limit)
                    let height = readUInt16BE(from: buf, offset: &offset, limit: limit)
                    game.windowSize = Vec2i(Int32(width), Int32(height))

                default:
                    fatalError("Unknown event type: \(eventType)")
                }
            }
        }

        let deltaf = Float(delta) / 1000
        for object in game.objects {
            object.update(delta: deltaf)
        }

        var transformedIds = [UInt32]()
        transformedIds.reserveCapacity(transformedObjects.count)
        var transformedMatrices: [Float] = []
        transformedMatrices.reserveCapacity(transformedObjects.count * 16)

        var stack: [(Object, Mat4)] = []

        for root in transformedObjects.values {
            stack.append((root, Mat4.identity))
            while let (obj, parentTransform) = stack.popLast() {
                let global = parentTransform * obj.transform

                if let rendered = obj as? RenderedObject {
                    transformedIds.append(rendered.id)
                    let m = global.m
                    transformedMatrices.append(contentsOf: [
                        m.0.x, m.0.y, m.0.z, m.0.w,
                        m.1.x, m.1.y, m.1.z, m.1.w,
                        m.2.x, m.2.y, m.2.z, m.2.w,
                        m.3.x, m.3.y, m.3.z, m.3.w,
                    ])
                }

                for child in obj.children {
                    stack.append((child, global))
                }
            }
        }

        simulo_set_rendered_object_transforms(
            count: UInt32(transformedIds.count), ids: transformedIds, matrices: transformedMatrices)

        transformedObjects.removeAll()
    }
}

@inline(__always)
private func readUInt32BE(from buf: UnsafeMutablePointer<UInt8>, offset: inout Int, limit: Int)
    -> UInt32
{
    precondition(offset + 4 <= limit)
    let b0 = UInt32(buf[offset])
    let b1 = UInt32(buf[offset + 1])
    let b2 = UInt32(buf[offset + 2])
    let b3 = UInt32(buf[offset + 3])
    offset += 4
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
}

@inline(__always)
private func readInt16BE(from buf: UnsafeMutablePointer<UInt8>, offset: inout Int, limit: Int)
    -> Int16
{
    precondition(offset + 2 <= limit)
    let b0 = UInt16(buf[offset])
    let b1 = UInt16(buf[offset + 1])
    offset += 2
    let u = (b0 << 8) | b1
    return Int16(bitPattern: u)
}

@inline(__always)
private func readUInt16BE(from buf: UnsafeMutablePointer<UInt8>, offset: inout Int, limit: Int)
    -> UInt16
{
    precondition(offset + 2 <= limit)
    let b0 = UInt16(buf[offset])
    let b1 = UInt16(buf[offset + 1])
    offset += 2
    return (b0 << 8) | b1
}

@resultBuilder
public struct ObjectChildrenBuilder {
    public static func buildBlock(_ children: Object...) -> [Object] {
        children
    }
}

@MainActor
open class Object {
    public var pos = Vec3(0, 0, 0) {
        didSet { moved() }
    }
    public var scale = Vec3(1, 1, 1) {
        didSet { moved() }
    }
    public var transform: Mat4 {
        Mat4.translate(pos) * Mat4.scale(scale)
    }

    var children: [Object]

    public init(pos: Vec3 = Vec3(0, 0, 0), scale: Vec3 = Vec3(1, 1, 1)) {
        self.pos = pos
        self.scale = scale
        self.children = []
    }

    public init(
        pos: Vec3 = Vec3(0, 0, 0), scale: Vec3 = Vec3(1, 1, 1),
        @ObjectChildrenBuilder children: () -> [Object]
    ) {
        self.pos = pos
        self.scale = scale
        self.children = children()
    }

    open func update(delta: Float) {}

    func moved() {
        transformedObjects[ObjectIdentifier(self)] = self
    }
}

@MainActor
open class RenderedObject: Object {
    let id: UInt32

    public init(
        material: Material, renderOrder: UInt32 = 0, pos: Vec3 = Vec3(0, 0, 0),
        scale: Vec3 = Vec3(1, 1, 1)
    ) {
        id = simulo_create_rendered_object2(material: material.id, renderOrder: renderOrder)
        super.init(pos: pos, scale: scale)
    }

    public init(
        material: Material, renderOrder: UInt32 = 0, pos: Vec3 = Vec3(0, 0, 0),
        scale: Vec3 = Vec3(1, 1, 1), @ObjectChildrenBuilder children: () -> [Object]
    ) {
        id = simulo_create_rendered_object2(material: material.id, renderOrder: renderOrder)
        super.init(pos: pos, scale: scale, children: children)
    }

    deinit {
        simulo_drop_rendered_object(id: id)
    }

}

public class Material {
    var id: UInt32 = 0xAAAA_AAAA

    public init(
        _ name: String?, _ tintR: Float32, _ tintG: Float32, _ tintB: Float32, _ tintA: Float32
    ) {
        if let name = name {
            name.withCString { namePtr in
                self.id = simulo_create_material(
                    namePtr: UInt32(Int(bitPattern: namePtr)), nameLen: UInt32(name.count),
                    tintR: tintR,
                    tintG: tintG,
                    tintB: tintB,
                    tintA: tintA)
            }
        } else {
            self.id = simulo_create_material(
                namePtr: 0, nameLen: 0, tintR: tintR, tintG: tintG,
                tintB: tintB, tintA: tintA)
        }
    }

    deinit {
        simulo_drop_material(id: id)
    }
}

public typealias Vec2 = SIMD2<Float>
public typealias Vec2i = SIMD2<Int32>
public typealias Vec3 = SIMD3<Float>

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
