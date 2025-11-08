package simugo

import (
	"bytes"
	"encoding/binary"
	"math"
	"time"
	"unsafe"
)

//go:wasmimport env simulo_poll
//go:noescape
func simuloPoll(buf unsafe.Pointer, length uint32) int32

//go:wasmimport env simulo_create_rendered_object2
//go:noescape
func simuloCreateRenderedObject2(material uint32, renderOrder uint32) uint32

//go:wasmimport env simulo_set_rendered_object_material
//go:noescape
func simuloSetRenderedObjectMaterial(id uint32, material uint32)

//go:wasmimport env simulo_set_rendered_object_transforms
//go:noescape
func simuloSetRenderedObjectTransforms(count uint32, ids unsafe.Pointer, matrices unsafe.Pointer)

//go:wasmimport env simulo_drop_rendered_object
//go:noescape
func simuloDropRenderedObject(id uint32)

//go:wasmimport env simulo_create_material
//go:noescape
func simuloCreateMaterial(namePtr uint32, nameLen uint32, tintR, tintG, tintB, tintA float32) uint32

//go:wasmimport env simulo_update_material
//go:noescape
func simuloUpdateMaterial(id uint32, tintR, tintG, tintB, tintA float32)

//go:wasmimport env simulo_drop_material
//go:noescape
func simuloDropMaterial(id uint32)

// Vectors
type Vec2 struct{ X, Y float32 }
type Vec2i struct{ X, Y int32 }
type Vec3 struct{ X, Y, Z float32 }
type Vec4 struct{ X, Y, Z, W float32 }

func (v Vec2i) AsVec2() Vec2 { return Vec2{float32(v.X), float32(v.Y)} }

type Mat4 struct {
	m [4]Vec4
}

func NewMat4(a, b, c, d Vec4) Mat4 { return Mat4{m: [4]Vec4{a, b, c, d}} }

func Mat4Identity() Mat4 {
	return NewMat4(
		Vec4{1, 0, 0, 0},
		Vec4{0, 1, 0, 0},
		Vec4{0, 0, 1, 0},
		Vec4{0, 0, 0, 1},
	)
}

func Mat4Translate(v Vec3) Mat4 {
	return NewMat4(
		Vec4{1, 0, 0, 0},
		Vec4{0, 1, 0, 0},
		Vec4{0, 0, 1, 0},
		Vec4{v.X, v.Y, v.Z, 1},
	)
}

func Mat4Rotate(v Vec3) Mat4 {
	rotX := NewMat4(
		Vec4{1, 0, 0, 0},
		Vec4{0, float32(math.Cos(float64(v.X))), -float32(math.Sin(float64(v.X))), 0},
		Vec4{0, float32(math.Sin(float64(v.X))), float32(math.Cos(float64(v.X))), 0},
		Vec4{0, 0, 0, 1},
	)
	rotY := NewMat4(
		Vec4{float32(math.Cos(float64(v.Y))), 0, float32(math.Sin(float64(v.Y))), 0},
		Vec4{0, 1, 0, 0},
		Vec4{-float32(math.Sin(float64(v.Y))), 0, float32(math.Cos(float64(v.Y))), 0},
		Vec4{0, 0, 0, 1},
	)
	rotZ := NewMat4(
		Vec4{float32(math.Cos(float64(v.Z))), -float32(math.Sin(float64(v.Z))), 0, 0},
		Vec4{float32(math.Sin(float64(v.Z))), float32(math.Cos(float64(v.Z))), 0, 0},
		Vec4{0, 0, 1, 0},
		Vec4{0, 0, 0, 1},
	)
	return rotX.Multiply(rotY).Multiply(rotZ)
}

func Mat4Scale(v Vec3) Mat4 {
	return NewMat4(
		Vec4{v.X, 0, 0, 0},
		Vec4{0, v.Y, 0, 0},
		Vec4{0, 0, v.Z, 0},
		Vec4{0, 0, 0, 1},
	)
}

func (lhs Mat4) Multiply(rhs Mat4) Mat4 {
	a := lhs.m
	b := rhs.m

	col0 := Vec4{
		a[0].X*b[0].X + a[1].X*b[0].Y + a[2].X*b[0].Z + a[3].X*b[0].W,
		a[0].Y*b[0].X + a[1].Y*b[0].Y + a[2].Y*b[0].Z + a[3].Y*b[0].W,
		a[0].Z*b[0].X + a[1].Z*b[0].Y + a[2].Z*b[0].Z + a[3].Z*b[0].W,
		a[0].W*b[0].X + a[1].W*b[0].Y + a[2].W*b[0].Z + a[3].W*b[0].W,
	}
	col1 := Vec4{
		a[0].X*b[1].X + a[1].X*b[1].Y + a[2].X*b[1].Z + a[3].X*b[1].W,
		a[0].Y*b[1].X + a[1].Y*b[1].Y + a[2].Y*b[1].Z + a[3].Y*b[1].W,
		a[0].Z*b[1].X + a[1].Z*b[1].Y + a[2].Z*b[1].Z + a[3].Z*b[1].W,
		a[0].W*b[1].X + a[1].W*b[1].Y + a[2].W*b[1].Z + a[3].W*b[1].W,
	}
	col2 := Vec4{
		a[0].X*b[2].X + a[1].X*b[2].Y + a[2].X*b[2].Z + a[3].X*b[2].W,
		a[0].Y*b[2].X + a[1].Y*b[2].Y + a[2].Y*b[2].Z + a[3].Y*b[2].W,
		a[0].Z*b[2].X + a[1].Z*b[2].Y + a[2].Z*b[2].Z + a[3].Z*b[2].W,
		a[0].W*b[2].X + a[1].W*b[2].Y + a[2].W*b[2].Z + a[3].W*b[2].W,
	}
	col3 := Vec4{
		a[0].X*b[3].X + a[1].X*b[3].Y + a[2].X*b[3].Z + a[3].X*b[3].W,
		a[0].Y*b[3].X + a[1].Y*b[3].Y + a[2].Y*b[3].Z + a[3].Y*b[3].W,
		a[0].Z*b[3].X + a[1].Z*b[3].Y + a[2].Z*b[3].Z + a[3].Z*b[3].W,
		a[0].W*b[3].X + a[1].W*b[3].Y + a[2].W*b[3].Z + a[3].W*b[3].W,
	}
	return NewMat4(col0, col1, col2, col3)
}

var transformedObjects = map[ObjectLike]ObjectLike{}

type ObjectLike interface {
	Transform() Mat4
	MarkTransformOutdated()
	SetParentTransform(parent Mat4)

	Children() []ObjectLike
}

type Object struct {
	Pos             Vec3
	Rotation        Vec3
	Scale           Vec3
	ChildObjects    []ObjectLike
	ParentTransform Mat4
}

func NewObject() *Object {
	obj := &Object{Pos: Vec3{0, 0, 0}, Scale: Vec3{1, 1, 1}}
	obj.MarkTransformOutdated()
	return obj
}

func (o *Object) Update(delta float32) {}

func (o *Object) MarkTransformOutdated() { transformedObjects[o] = o }

func (o *Object) Transform() Mat4 {
	return Mat4Translate(o.Pos).Multiply(Mat4Rotate(o.Rotation)).Multiply(Mat4Scale(o.Scale))
}

func (o *Object) SetParentTransform(parent Mat4) {
	o.ParentTransform = parent
}

func (o *Object) Children() []ObjectLike {
	return o.ChildObjects
}

// RenderedObject
type RenderedObject struct {
	Object
	id uint32
}

func NewRenderedObject(material Material, renderOrder uint32, pos Vec3, scale Vec3) *RenderedObject {
	ro := &RenderedObject{}
	ro.id = simuloCreateRenderedObject2(material.ID, renderOrder)
	ro.Object = *NewObject()
	return ro
}

func (ro *RenderedObject) Close() { // manual drop equivalent
	simuloDropRenderedObject(ro.id)
}

// Material
type Material struct {
	ID    uint32
	Color Vec4
}

func NewMaterial(name *string, tintR, tintG, tintB, tintA float32) Material {
	m := Material{Color: Vec4{tintR, tintG, tintB, tintA}}
	if name != nil {
		// Placeholder: we are not passing actual pointer/len to extern; just stub
		m.ID = simuloCreateMaterial(0, uint32(len(*name)), tintR, tintG, tintB, tintA)
	} else {
		m.ID = simuloCreateMaterial(0, 0, tintR, tintG, tintB, tintA)
	}
	return m
}

func (m *Material) SetColor(c Vec4) {
	m.Color = c
	simuloUpdateMaterial(m.ID, c.X, c.Y, c.Z, c.W)
}

func (m *Material) Close() { simuloDropMaterial(m.ID) }

// Game and run loop
type Game struct {
	objects    []*Object
	eventBuf   [1024 * 32]byte
	poses      map[uint32][]float32
	WindowSize Vec2i
}

type GameLike interface {
	HandleEvents() bool
	Update(delta float32)
	RootObjects() []ObjectLike
}

func NewGame() *Game {
	g := &Game{
		objects: []*Object{},
		poses:   map[uint32][]float32{},
	}
	// Poll once to "initialize" window size
	_ = g.HandleEvents()
	return g
}

func (g *Game) Update(delta float32) {}

func (g *Game) AddObject(o *Object) { g.objects = append(g.objects, o) }

func (g *Game) DeleteObject(target *Object) {
	filtered := g.objects[:0]
	for _, o := range g.objects {
		if o != target {
			filtered = append(filtered, o)
		}
	}
	g.objects = filtered
}

// RootObjects returns the top-level objects as ObjectLike values.
func (g *Game) RootObjects() []ObjectLike {
	objs := make([]ObjectLike, 0, len(g.objects))
	for _, o := range g.objects {
		objs = append(objs, o)
	}
	return objs
}

func (g *Game) HandleEvents() bool {
	lenN := simuloPoll(unsafe.Pointer(&g.eventBuf[0]), uint32(len(g.eventBuf)))
	if lenN < 0 {
		return false
	}
	if lenN == 0 {
		return true
	}
	r := bytes.NewReader(g.eventBuf[:lenN])
	for r.Len() > 0 {
		var eventType uint8
		if err := binary.Read(r, binary.BigEndian, &eventType); err != nil {
			return false
		}
		switch eventType {
		case 0: // upsert/move with pose
			var id uint32
			if err := binary.Read(r, binary.BigEndian, &id); err != nil {
				return false
			}
			pose := make([]float32, 17*2)
			for i := 0; i < 17; i++ {
				var sx, sy int16
				if err := binary.Read(r, binary.BigEndian, &sx); err != nil {
					return false
				}
				if err := binary.Read(r, binary.BigEndian, &sy); err != nil {
					return false
				}
				pose[i*2] = float32(sx)
				pose[i*2+1] = float32(sy)
			}
			g.poses[id] = pose
		case 1: // delete by id
			var id uint32
			if err := binary.Read(r, binary.BigEndian, &id); err != nil {
				return false
			}
			delete(g.poses, id)
		case 2: // window resize
			var w, h uint16
			if err := binary.Read(r, binary.BigEndian, &w); err != nil {
				return false
			}
			if err := binary.Read(r, binary.BigEndian, &h); err != nil {
				return false
			}
			g.WindowSize = Vec2i{int32(w), int32(h)}
		default:
			return false
		}
	}
	return true
}

func Run(game GameLike) {
	prev := time.Now()
	for {
		now := time.Now()
		deltaMs := now.Sub(prev).Milliseconds()
		prev = now
		if !game.HandleEvents() {
			break
		}
		deltaf := float32(deltaMs) / 1000.0
		game.Update(deltaf)
		for _, _ = range game.RootObjects() {
			//object.Update(deltaf)
		}

		transformedIDs := make([]uint32, 0, len(transformedObjects))
		transformedMatrices := make([]float32, 0, len(transformedObjects)*16)
		stack := make([]struct {
			obj    ObjectLike
			parent Mat4
		}, 0)

		for _, root := range transformedObjects {
			stack = append(stack, struct {
				obj    ObjectLike
				parent Mat4
			}{root, Mat4Identity()})
			for len(stack) > 0 {
				last := stack[len(stack)-1]
				stack = stack[:len(stack)-1]
				global := last.parent.Multiply(last.obj.Transform())

				if ro, ok := last.obj.(*RenderedObject); ok {
					transformedIDs = append(transformedIDs, ro.id)
					m := global.m
					transformedMatrices = append(transformedMatrices,
						m[0].X, m[0].Y, m[0].Z, m[0].W, m[1].X, m[1].Y, m[1].Z, m[1].W, m[2].X, m[2].Y, m[2].Z, m[2].W, m[3].X, m[3].Y, m[3].Z, m[3].W,
					)
				}
				for _, child := range last.obj.Children() {
					stack = append(stack, struct {
						obj    ObjectLike
						parent Mat4
					}{child, global})
				}
			}
		}

		if len(transformedIDs) > 0 {
			simuloSetRenderedObjectTransforms(uint32(len(transformedIDs)), unsafe.Pointer(&transformedIDs[0]), unsafe.Pointer(&transformedMatrices[0]))
		}
		transformedObjects = make(map[ObjectLike]ObjectLike)
	}
}
