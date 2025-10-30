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
@_extern(wasm, module: "env", name: "simulo_set_rendered_object_transform")
@_extern(c)
func simulo_set_rendered_object_transform(id: UInt32, matrix: UnsafePointer<Float>)
@_extern(wasm, module: "env", name: "simulo_drop_rendered_object")
@_extern(c)
func simulo_drop_rendered_object(id: UInt32)

@_extern(wasm, module: "env", name: "simulo_create_material")
@_extern(c)
func simulo_create_material(
    namePtr: UInt32, nameLen: UInt32, tintR: Float32, tintG: Float32, tintB: Float32
) -> UInt32
@_extern(wasm, module: "env", name: "simulo_drop_material")
@_extern(c)
func simulo_drop_material(id: UInt32)

@MainActor
open class Game {
    var objects: [Object] = []

    public init() {}

    public func addObject(_ object: Object) {
        objects.append(object)
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

                default:
                    fatalError("Unknown event type: \(eventType)")
                }
            }
        }

        for object in game.objects {
            object.fireEvent(UpdateEvent(object: object, delta: Float(delta) / 1000))
        }
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

public typealias HandlerMap = [ObjectIdentifier: Any]

private func makeHandlerTuple<T, E>(
    _ handler: @escaping (T) -> (E) -> Void,
    this: T,
    eventHandlers: inout HandlerMap
) {
    let id = ObjectIdentifier(E.self)
    if let existingHandlers = eventHandlers[id] {
        var handlerList = existingHandlers as! [(E) -> Void]
        handlerList.append(handler(this))
    } else {
        eventHandlers[id] = [handler(this)]
    }
}

public func handlers<T, each E>(
    _ handlers: repeat @escaping (T) -> (each E) -> Void
) -> (T, inout HandlerMap) -> Void {
    return { this, eventHandlers in
        repeat makeHandlerTuple(each handlers, this: this, eventHandlers: &eventHandlers)
    }
}

@MainActor
public protocol Trait {
    static var events: (Self, inout HandlerMap) -> Void
    { get }
}

public struct UpdateEvent {
    public let object: Object
    public let delta: Float
}

public struct GlobalTransformEvent {
    public let matrix: Mat4
}

@MainActor
public class Rendered: Trait {
    private let id: UInt32

    public init(material: Material, renderOrder: UInt32 = 0) {
        id = simulo_create_rendered_object2(material: material.id, renderOrder: renderOrder)
    }

    deinit {
        simulo_drop_rendered_object(id: id)
    }

    func onGlobalTransform(event: GlobalTransformEvent) {
        withUnsafePointer(to: event.matrix.m) { matrixPtr in
            matrixPtr.withMemoryRebound(to: Float.self, capacity: 16) { matrix in
                simulo_set_rendered_object_transform(id: id, matrix: matrix)
            }
        }
    }

    public static let events = handlers(onGlobalTransform)
}

@MainActor
public class Object {
    private var eventHandlers: HandlerMap = [:]

    public var pos = Vec3(0, 0, 0)
    public var scale = Vec3(1, 1, 1)

    public init() {}

    public func addTrait<T: Trait>(_ trait: T) {
        T.events(trait, &eventHandlers)
    }

    public func fireEvent<E>(_ event: E) {
        let id = ObjectIdentifier(E.self)
        if let handlerList = eventHandlers[id] {
            for handler in handlerList as! [(E) -> Void] {
                handler(event)
            }
        }
    }

    public func moved() {
        fireEvent(GlobalTransformEvent(matrix: Mat4.translate(pos) * Mat4.scale(scale)))
    }
}

public class Material {
    var id: UInt32 = 0xAAAA_AAAA

    public init(_ name: String?, _ tintR: Float32, _ tintG: Float32, _ tintB: Float32) {
        if let name = name {
            name.withCString { namePtr in
                self.id = simulo_create_material(
                    namePtr: UInt32(Int(bitPattern: namePtr)), nameLen: UInt32(name.count),
                    tintR: tintR,
                    tintG: tintG,
                    tintB: tintB)
            }
        } else {
            self.id = simulo_create_material(
                namePtr: 0, nameLen: 0, tintR: tintR, tintG: tintG,
                tintB: tintB)
        }
    }

    deinit {
        simulo_drop_material(id: id)
    }
}

public typealias Vec3 = SIMD3<Float>
public struct Mat4 {
    public var m: SIMD16<Float>

    public init(_ m: SIMD16<Float>) {
        self.m = m
    }

    public static var identity: Mat4 {
        // Column-major 4x4 identity matrix
        return Mat4(
            SIMD16<Float>(
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1
            ))
    }

    public static func translate(_ v: Vec3) -> Mat4 {
        // Column-major translation matrix
        return Mat4(
            SIMD16<Float>(
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                v.x, v.y, v.z, 1
            ))
    }

    public static func scale(_ v: Vec3) -> Mat4 {
        // Column-major scale matrix
        return Mat4(
            SIMD16<Float>(
                v.x, 0, 0, 0,
                0, v.y, 0, 0,
                0, 0, v.z, 0,
                0, 0, 0, 1
            ))
    }

    public static func * (lhs: Mat4, rhs: Mat4) -> Mat4 {
        // 4x4 matrix multiplication (column-major)
        var result = SIMD16<Float>(repeating: 0)
        for col in 0..<4 {
            for row in 0..<4 {
                var sum: Float = 0
                for i in 0..<4 {
                    sum += lhs.m[i * 4 + row] * rhs.m[col * 4 + i]
                }
                result[col * 4 + row] = sum
            }
        }
        return Mat4(result)
    }
}
