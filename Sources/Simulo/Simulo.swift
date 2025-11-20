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
@_extern(wasm, module: "env", name: "simulo_set_rendered_object_colors")
@_extern(c)
func simulo_set_rendered_object_colors(
    count: UInt32, ids: UnsafePointer<UInt32>, colors: UnsafePointer<Float>)
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
@_extern(wasm, module: "env", name: "simulo_update_material")
@_extern(c)
func simulo_update_material(
    id: UInt32, tintR: Float32, tintG: Float32, tintB: Float32, tintA: Float32)
@_extern(wasm, module: "env", name: "simulo_drop_material")
@_extern(c)
func simulo_drop_material(id: UInt32)

@MainActor
var transformedObjects = [ObjectIdentifier: Object]()

@MainActor
open class Game {
    static var eventBuf = [UInt8](repeating: 0, count: 1024 * 32)
    static var poses: [UInt32: HasPose] = [:]
    public internal(set) static var windowSize = Vec2i(0, 0)
    public internal(set) static var rootObject = Object()
    public static var playerMaker: (Pose) -> HasPose = { pose in BasicPlayer.init(pose: pose) }

    public static func setup() {
        _ = handleEvents()
    }

    static func handleEvents() -> Bool {
        let len = simulo_poll(buf: &eventBuf, len: UInt32(eventBuf.count))
        if len < 0 { return false }
        if len > 0 {
            var offset = 0
            let limit = Int(len)

            while offset < limit {
                let eventType = eventBuf[offset]
                offset += 1

                switch eventType {
                case 0:  // upsert/move with pose
                    guard offset + 4 <= limit else { return false }
                    let id = readUInt32BE(from: &eventBuf, offset: &offset, limit: limit)

                    // Read 17 pairs of i16 (big-endian) -> 34 floats
                    var pose: [Float] = Array(repeating: 0, count: 17 * 2)
                    for i in 0..<17 {
                        guard offset + 4 <= limit else { return false }
                        let x = Float(
                            readInt16BE(from: &eventBuf, offset: &offset, limit: limit))
                        let y = Float(
                            readInt16BE(from: &eventBuf, offset: &offset, limit: limit))
                        pose[i * 2] = x
                        pose[i * 2 + 1] = y
                    }

                    if let poseObj = poses[id] {
                        poseObj.pose = Pose(data: pose)
                    } else {
                        poses[id] = Game.playerMaker(Pose(data: pose))
                    }

                case 1:  // delete by id
                    guard offset + 4 <= limit else { return false }
                    let id = readUInt32BE(from: &eventBuf, offset: &offset, limit: limit)
                    poses.removeValue(forKey: id)

                case 2:  // window resize
                    guard offset + 4 <= limit else { return false }
                    let width = readUInt16BE(from: &eventBuf, offset: &offset, limit: limit)
                    let height = readUInt16BE(from: &eventBuf, offset: &offset, limit: limit)
                    Game.windowSize = Vec2i(Int32(width), Int32(height))

                default:
                    fatalError("Unknown event type: \(eventType)")
                }
            }
        }

        return true
    }

    public static func run(root: Object) {
        rootObject = root
        var time = Int64(Date().timeIntervalSince1970 * 1000)

        while true {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let delta = now - time
            time = now

            if !Game.handleEvents() {
                break
            }

            let deltaf = Float(delta) / 1000
            var updateStack: [Object] = [Game.rootObject]
            while let obj = updateStack.popLast() {
                obj.update(delta: deltaf)
                for child in obj.children {
                    updateStack.append(child)
                }
            }

            var transformedIds = [UInt32]()
            transformedIds.reserveCapacity(transformedObjects.count)
            var transformedMatrices: [Float] = []
            transformedMatrices.reserveCapacity(transformedObjects.count * 16)

            var stack: [Object] = []

            for root in transformedObjects.values {
                stack.append(root)
                while let obj = stack.popLast() {
                    let global = obj.globalTransform

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
                        stack.append(child)
                    }
                }
            }

            simulo_set_rendered_object_transforms(
                count: UInt32(transformedIds.count), ids: transformedIds,
                matrices: transformedMatrices)

            transformedObjects.removeAll()
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

public struct Pose {
    var data: [Float]

    public static let NOSE: Int = 0
    public static let LEFT_EYE: Int = 1
    public static let RIGHT_EYE: Int = 2
    public static let LEFT_EAR: Int = 3
    public static let RIGHT_EAR: Int = 4
    public static let LEFT_SHOULDER: Int = 5
    public static let RIGHT_SHOULDER: Int = 6
    public static let LEFT_ELBOW: Int = 7
    public static let RIGHT_ELBOW: Int = 8
    public static let LEFT_WRIST: Int = 9
    public static let RIGHT_WRIST: Int = 10
    public static let LEFT_HIP: Int = 11
    public static let RIGHT_HIP: Int = 12
    public static let LEFT_KNEE: Int = 13
    public static let RIGHT_KNEE: Int = 14
    public static let LEFT_ANKLE: Int = 15
    public static let RIGHT_ANKLE: Int = 16

    public var nose: Vec2 { keypoint(Self.NOSE) }
    public var leftEye: Vec2 { keypoint(Self.LEFT_EYE) }
    public var rightEye: Vec2 { keypoint(Self.RIGHT_EYE) }
    public var leftEar: Vec2 { keypoint(Self.LEFT_EAR) }
    public var rightEar: Vec2 { keypoint(Self.RIGHT_EAR) }
    public var leftShoulder: Vec2 { keypoint(Self.LEFT_SHOULDER) }
    public var rightShoulder: Vec2 { keypoint(Self.RIGHT_SHOULDER) }
    public var leftElbow: Vec2 { keypoint(Self.LEFT_ELBOW) }
    public var rightElbow: Vec2 { keypoint(Self.RIGHT_ELBOW) }
    public var leftWrist: Vec2 { keypoint(Self.LEFT_WRIST) }
    public var rightWrist: Vec2 { keypoint(Self.RIGHT_WRIST) }
    public var leftHip: Vec2 { keypoint(Self.LEFT_HIP) }
    public var rightHip: Vec2 { keypoint(Self.RIGHT_HIP) }
    public var leftKnee: Vec2 { keypoint(Self.LEFT_KNEE) }
    public var rightKnee: Vec2 { keypoint(Self.RIGHT_KNEE) }
    public var leftAnkle: Vec2 { keypoint(Self.LEFT_ANKLE) }
    public var rightAnkle: Vec2 { keypoint(Self.RIGHT_ANKLE) }

    public func keypoint(_ index: Int) -> Vec2 {
        Vec2(data[index * 2], data[index * 2 + 1])
    }
}

@MainActor
public protocol HasPose: Object {
    var pose: Pose { get set }
}

class BasicPlayer: Object, HasPose {
    var pose: Pose

    init(pose: Pose) {
        self.pose = pose
        super.init()
    }
}

public typealias Children = () -> [Object]

@MainActor
open class Object {
    public var pos = Vec3(0, 0, 0) {
        didSet { moved() }
    }
    public var rotation = Vec3(0, 0, 0) {
        didSet { moved() }
    }
    public var scale = Vec3(1, 1, 1) {
        didSet { moved() }
    }
    public internal(set) weak var parent: Object? = nil
    public var transform: Mat4 {
        Mat4.translate(pos) * Mat4.rotate(rotation) * Mat4.scale(scale)
    }
    public var globalTransform: Mat4 {
        (parent?.globalTransform ?? Mat4.identity) * transform
    }
    var index = -1

    var children: [Object]

    public init(pos: Vec3 = Vec3(0, 0, 0), scale: Vec3 = Vec3(1, 1, 1)) {
        self.pos = pos
        self.scale = scale
        self.children = []
        moved()
    }

    public init(
        pos: Vec3 = Vec3(0, 0, 0), scale: Vec3 = Vec3(1, 1, 1),
        @ObjectChildrenBuilder children: Children
    ) {
        self.pos = pos
        self.scale = scale
        self.children = children()
        for (i, child) in self.children.enumerated() {
            child.parent = self
            child.index = i
        }
        moved()
    }

    open func update(delta: Float) {}

    func moved() {
        transformedObjects[ObjectIdentifier(self)] = self
    }

    public func addChild(_ child: Object) {
        if child.index != -1 {
            fatalError("tried to add child that was already added")
        }

        children.append(child)
        child.parent = self
        child.index = children.count - 1
    }

    public func deleteChild(_ toDelete: Object) {
        assert(toDelete.index != -1, "tried to delete an object that isn't a child of an object")

        let isLast = toDelete.index == children.count - 1
        children.swapAt(toDelete.index, children.count - 1)
        children.removeLast()
        if !isLast {
            children[toDelete.index].index = toDelete.index
        }
        toDelete.index = -1
        toDelete.parent = nil
    }

    public func deleteFromParent() {
        parent!.deleteChild(self)
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
        scale: Vec3 = Vec3(1, 1, 1), @ObjectChildrenBuilder children: Children
    ) {
        id = simulo_create_rendered_object2(material: material.id, renderOrder: renderOrder)
        super.init(pos: pos, scale: scale, children: children)
    }

    deinit {
        simulo_drop_rendered_object(id: id)
    }

    public func setMaterial(_ material: Material) {
        simulo_set_rendered_object_material(id: self.id, material: material.id)
    }

    public func setColor(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1.0) {
        let id = [self.id]
        let colors = [r, g, b, a]
        simulo_set_rendered_object_colors(count: 1, ids: id, colors: colors)
    }
}

public class Material {
    var id: UInt32 = 0xAAAA_AAAA
    public var color: Vec4 {
        didSet {
            simulo_update_material(
                id: id, tintR: color.x, tintG: color.y, tintB: color.z, tintA: color.w)
        }
    }

    public init(
        _ name: String?, _ tintR: Float32, _ tintG: Float32, _ tintB: Float32, _ tintA: Float32
    ) {
        self.color = Vec4(tintR, tintG, tintB, tintA)

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

class Particle: RenderedObject {
    let angle: Float
    let speed: Float
    let scaleDecay: Float

    public init(material: Material, angle: Float, speed: Float, scale: Float, scaleDecay: Float) {
        self.angle = angle
        self.speed = speed
        self.scaleDecay = scaleDecay
        super.init(material: material, pos: Vec3(0, 0, 0), scale: Vec3(scale, scale, 1))
    }

    public override func update(delta: Float) {
        pos += Vec2.fromAngle(angle).extend(0) * speed * delta
        scale -= Vec3(scaleDecay, scaleDecay, 0) * delta

        if scale.x <= 0 {
            deleteFromParent()
        }
    }
}

public class ParticleEmitter: Object {
    let angles: Range<Float>
    let speed: Range<Float>
    let startingScale: Float
    let scaleDecay: Float
    let materials: [Material]

    let spawnInterval: Float
    var elapsed: Float = 0

    public init(
        pos: Vec3 = Vec3(0, 0, 0),
        angles: Range<Float> = 0..<(2 * Float.pi),
        speed: Range<Float> = 100..<150,
        startingScale: Float = 4,
        scaleDecay: Float = 2,
        materials: [Material],
        spawnInterval: Float = 0.1
    ) {
        self.angles = angles
        self.speed = speed
        self.startingScale = startingScale
        self.scaleDecay = scaleDecay
        self.materials = materials

        self.spawnInterval = spawnInterval

        super.init(pos: pos)
    }

    public override func update(delta: Float) {
        elapsed += delta
        if elapsed < spawnInterval {
            return
        }

        elapsed -= spawnInterval
        let angle = Float.random(in: angles)
        let speed = Float.random(in: speed)
        addChild(
            Particle(
                material: materials.randomElement()!, angle: angle, speed: speed,
                scale: startingScale, scaleDecay: scaleDecay
            )
        )
    }
}

public class Interval {
    let period: Float
    var elapsed: Float = 0

    public init(period: Float) {
        self.period = period
    }

    public func update(_ delta: Float) -> Bool {
        elapsed += delta
        if elapsed >= period {
            elapsed -= period
            return true
        }
        return false
    }
}

extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
