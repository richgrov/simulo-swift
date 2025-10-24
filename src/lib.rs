pub mod ecs;

mod pose;
mod transforms;

use std::collections::{HashMap, HashSet, VecDeque};
use std::io::{Cursor, Read};
use std::ops::{Deref, DerefMut};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Instant;

use glam::{IVec2, Mat4, Vec2, Vec3, Vec4};

pub use pose::Pose;
use shipyard::sparse_set::SparseSet;
use shipyard::{
    AllStoragesViewMut, Borrow, BorrowInfo, Component, EntitiesView, EntitiesViewMut, EntityId,
    Get, IntoIter, IntoWorkload, Unique, UniqueView, View, ViewMut, Workload, World,
};

pub use transforms::*;

static mut POSE_DATA: pose::PoseData = [0.0; 17 * 2];
static INITIALIZED: AtomicBool = AtomicBool::new(false);

#[allow(unused)]
pub trait Game {
    const FIXED_UPDATES_PER_SECOND: f32 = 60.0;

    fn init(&mut self, world: &mut World) {}
    fn update(&mut self, world: &mut World, delta: f32) {}
    fn fixed_update(&mut self, world: &mut World) {}
}

pub fn run<G: Game>(mut game: G) {
    let mut world = World::new();
    let mut poses = HashMap::new();
    let fixed_update_delta = 1.0 / G::FIXED_UPDATES_PER_SECOND;
    let mut fixed_update_accumulator = 0.0;

    if !INITIALIZED
        .compare_exchange(false, true, Ordering::Relaxed, Ordering::Relaxed)
        .is_ok()
    {
        panic!("Simulo already initialized");
    }

    #[allow(static_mut_refs)]
    unsafe {
        simulo_set_buffers(POSE_DATA.as_mut_ptr())
    };

    world.add_workload(post_update_workload);

    let mut time = Instant::now();

    game.init(&mut world);

    let mut events = vec![0u8; 1024 * 32];

    loop {
        let len = unsafe { simulo_poll(events.as_mut_ptr(), events.len()) };
        if len < 0 {
            break;
        }

        let mut cursor = Cursor::new(&events[..len as usize]);
        while cursor.position() < len as u64 {
            let mut event_type = [0u8; 1];
            cursor.read_exact(&mut event_type).unwrap();
            match event_type[0] {
                0 => {
                    let mut id = [0u8; 4];
                    cursor.read_exact(&mut id).unwrap();
                    let id = u32::from_be_bytes(id);

                    let mut pose = [0.0; 17 * 2];
                    for i in 0..17 {
                        let mut x = [0u8; 2];
                        cursor.read_exact(&mut x).unwrap();
                        let x = i16::from_be_bytes(x);
                        let mut y = [0u8; 2];
                        cursor.read_exact(&mut y).unwrap();
                        let y = i16::from_be_bytes(y);
                        pose[i * 2] = x as f32;
                        pose[i * 2 + 1] = y as f32;
                    }

                    if let Some(entity) = poses.get(&id) {
                        let mut poses = world.borrow::<ViewMut<Pose>>().unwrap();
                        (&mut poses).get(*entity).unwrap().0 = pose;
                    } else {
                        let entity = world.add_entity((Pose(pose), Children::new([])));
                        poses.insert(id, entity);
                    }
                }
                1 => {
                    let mut id = [0u8; 4];
                    cursor.read_exact(&mut id).unwrap();
                    let id = u32::from_be_bytes(id);
                    let entity = poses.remove(&id).unwrap();
                    world.add_component(entity, Delete);
                }
                other => panic!("Unknown event type: {}", other),
            }
        }

        let now = Instant::now();
        let delta = now.duration_since(time).as_secs_f32();
        time = now;

        world.add_unique(Delta(delta));

        fixed_update_accumulator += delta;
        while fixed_update_accumulator >= fixed_update_delta {
            game.fixed_update(&mut world);
            fixed_update_accumulator -= fixed_update_delta;
        }

        game.update(&mut world, delta);

        world.run_workload(post_update_workload).unwrap();
    }
}

#[derive(Unique)]
pub struct Delta(pub f32);

impl Deref for Delta {
    type Target = f32;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

pub struct Material(u32);

impl Material {
    pub fn texture(texture_name: &str, tint_r: f32, tint_g: f32, tint_b: f32) -> Self {
        unsafe {
            Material(simulo_create_material(
                texture_name.as_ptr(),
                texture_name.len(),
                tint_r,
                tint_g,
                tint_b,
            ))
        }
    }

    pub fn solid_color(r: f32, g: f32, b: f32) -> Self {
        unsafe { Material(simulo_create_material(std::ptr::null(), 0, r, g, b)) }
    }

    pub fn set_color(&self, r: f32, g: f32, b: f32) {
        unsafe { simulo_update_material(self.0, r, g, b) }
    }
}

impl std::ops::Drop for Material {
    fn drop(&mut self) {
        unsafe { simulo_drop_material(self.0) }
    }
}

#[derive(Component)]
pub struct Rendered(u32);

impl Rendered {
    pub fn new(material: &Material) -> Self {
        Rendered(unsafe { simulo_create_rendered_object2(material.0, 0) })
    }

    pub fn new_with_layer(material: &Material, render_order: u32) -> Self {
        Rendered(unsafe { simulo_create_rendered_object2(material.0, render_order) })
    }
}

impl std::ops::Drop for Rendered {
    fn drop(&mut self) {
        unsafe {
            simulo_drop_rendered_object(self.0);
        }
    }
}

#[derive(Component, Clone, Default)]
pub struct Velocity(pub Vec3);

impl Velocity {
    pub fn new(x: f32, y: f32, z: f32) -> Self {
        Self(Vec3::new(x, y, z))
    }
}

impl Deref for Velocity {
    type Target = Vec3;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl DerefMut for Velocity {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

#[derive(Component, Clone, Default)]
#[track(Insertion, Modification)]
pub struct Transform(pub Mat4);

impl Transform {
    #[deprecated]
    pub fn from_2d_pos(position: Vec2) -> Self {
        Self(Mat4::from_translation(position.extend(0.0)))
    }

    #[deprecated]
    pub fn from_2d_pos_scale(position: Vec2, scale: Vec2) -> Self {
        Self(Mat4::from_translation(position.extend(0.0)) * Mat4::from_scale(scale.extend(1.0)))
    }

    #[deprecated]
    pub fn from_2d_pos_rotation(position: Vec2, rotation: f32) -> Self {
        Self(Mat4::from_translation(position.extend(0.0)) * Mat4::from_rotation_z(rotation))
    }

    #[deprecated]
    pub fn from_2d_pos_rotation_scale(position: Vec2, rotation: f32, scale: Vec2) -> Self {
        Self(
            Mat4::from_translation(position.extend(0.0))
                * Mat4::from_rotation_z(rotation)
                * Mat4::from_scale(scale.extend(1.0)),
        )
    }

    pub fn from_2d_pos_rotation_scale_skew(
        position: Vec2,
        rotation: f32,
        scale: Vec2,
        skew: Vec2,
    ) -> Self {
        Self(
            Mat4::from_translation(position.extend(0.0))
                * Mat4::from_rotation_z(rotation)
                * Mat4::from_scale(scale.extend(1.0))
                * Mat4::from_cols(
                    Vec4::new(1.0, skew.y, 0.0, 0.0),
                    Vec4::new(skew.x, 1.0, 0.0, 0.0),
                    Vec4::Z,
                    Vec4::W,
                ),
        )
    }

    pub fn pos(position: Vec3) -> Self {
        Self(Mat4::from_translation(position))
    }

    pub fn pos_rotation(position: Vec3, rotation: f32) -> Self {
        Self(Mat4::from_translation(position) * Mat4::from_rotation_z(rotation))
    }

    pub fn pos_rotation_scale(position: Vec3, rotation: f32, scale: Vec3) -> Self {
        Self(
            Mat4::from_translation(position)
                * Mat4::from_rotation_z(rotation)
                * Mat4::from_scale(scale),
        )
    }

    pub fn with_global(self) -> (Transform, GlobalTransform) {
        (self, GlobalTransform::default())
    }
}

impl From<(&Position, &Scale)> for Transform {
    fn from((position, scale): (&Position, &Scale)) -> Self {
        Self(Mat4::from_translation(position.0) * Mat4::from_scale(scale.0))
    }
}

impl From<Position> for Transform {
    fn from(position: Position) -> Self {
        Self(Mat4::from_translation(position.0))
    }
}

impl From<(Position, Scale)> for Transform {
    fn from((position, scale): (Position, Scale)) -> Self {
        Self(Mat4::from_translation(position.0) * Mat4::from_scale(scale.0))
    }
}

impl From<Transform> for (Transform, GlobalTransform) {
    fn from(value: Transform) -> Self {
        (value, GlobalTransform::default())
    }
}

impl From<(Position, Rotation, Scale)> for Transform {
    fn from((position, rotation, scale): (Position, Rotation, Scale)) -> Self {
        Self(
            Mat4::from_translation(position.0)
                * Mat4::from_rotation_z(rotation.0)
                * Mat4::from_scale(scale.0),
        )
    }
}

#[derive(Component, Clone)]
#[track(All)]
pub struct GlobalTransform {
    pub parent: Mat4,
    pub global: Mat4,
}

impl Default for GlobalTransform {
    fn default() -> Self {
        Self {
            parent: Mat4::IDENTITY,
            global: Mat4::IDENTITY,
        }
    }
}

#[derive(Borrow, BorrowInfo)]
pub struct TransformHierarchyMut<'v> {
    pub v_transforms: ViewMut<'v, Transform>,
    pub v_global_transforms: ViewMut<'v, GlobalTransform>,
}

impl<'v> TransformHierarchyMut<'v> {
    pub fn view(
        &mut self,
    ) -> (
        &mut ViewMut<'v, Transform>,
        &mut ViewMut<'v, GlobalTransform>,
    ) {
        (&mut self.v_transforms, &mut self.v_global_transforms)
    }
}

#[derive(Component)]
pub struct Children(pub Vec<EntityId>);

impl Children {
    pub fn new<const N: usize>(children: [EntityId; N]) -> Self {
        Self(children.to_vec())
    }
}

#[derive(Component)]
pub struct Delete;

fn velocity_tick(
    delta: UniqueView<Delta>,
    mut positions: ViewMut<Position>,
    velocities: View<Velocity>,
) {
    for (position, velocity) in (&mut positions, &velocities).iter() {
        position.0 += velocity.0 * delta.0;
    }
}

fn recalculate_transforms(
    transforms: View<Transform>,
    entites: EntitiesViewMut,
    mut transform_states: ViewMut<GlobalTransform>,
    v_children: View<Children>,
) {
    let mut bfs = (transforms.inserted_or_modified(), &transform_states)
        .iter()
        .with_id()
        .map(|(entity, (_, transform_state))| (entity, transform_state.parent.clone()))
        .collect::<VecDeque<_>>();

    while let Some((entity, parent_transform)) = bfs.pop_front() {
        let global_transform = parent_transform * transforms.get(entity).unwrap().0;

        entites.add_component(
            entity,
            &mut transform_states,
            GlobalTransform {
                parent: parent_transform,
                global: global_transform,
            },
        );

        if let Ok(children) = v_children.get(entity) {
            for &child in &children.0 {
                bfs.push_back((child, global_transform));
            }
        }
    }
}

fn update_global_transforms(transform_states: View<GlobalTransform>, renders: View<Rendered>) {
    for (transform, rendered) in (transform_states.inserted_or_modified(), &renders).iter() {
        unsafe {
            simulo_set_rendered_object_transform(
                rendered.0,
                transform.global.to_cols_array().as_ptr(),
            );
        }
    }
}

fn propagate_delete_to_children(
    entities: EntitiesView,
    v_children: View<Children>,
    mut deleted: ViewMut<Delete>,
) {
    let mut bfs = VecDeque::new();
    let mut seen_children = HashSet::new();

    for (children, _) in (&v_children, &deleted).iter() {
        for &child in &children.0 {
            if seen_children.insert(child) {
                bfs.push_back(child);
            }
        }
    }

    while let Some(entity) = bfs.pop_front() {
        if let Ok(children) = v_children.get(entity) {
            for &child in &children.0 {
                if seen_children.insert(child) {
                    bfs.push_back(child);
                }
            }
        }
        entities.add_component(entity, &mut deleted, Delete);
    }
}

fn do_delete(mut all: AllStoragesViewMut) {
    all.delete_any::<SparseSet<Delete>>();
}

fn post_update_workload() -> Workload {
    (
        velocity_tick,
        recalculate_transforms,
        update_global_transforms,
        propagate_delete_to_children,
        do_delete,
    )
        .into_workload()
}

pub fn window_size() -> IVec2 {
    unsafe { IVec2::new(simulo_window_width(), simulo_window_height()) }
}

unsafe extern "C" {
    fn simulo_set_buffers(pose: *mut f32);

    fn simulo_create_material(name: *const u8, name_len: usize, r: f32, g: f32, b: f32) -> u32;
    fn simulo_update_material(material: u32, r: f32, g: f32, b: f32);
    fn simulo_drop_material(material: u32);

    fn simulo_poll(buf: *mut u8, len: usize) -> i32;

    fn simulo_create_rendered_object2(material: u32, render_order: u32) -> u32;
    fn simulo_set_rendered_object_material(id: u32, material: u32);
    fn simulo_set_rendered_object_transform(id: u32, matrix: *const f32);
    fn simulo_drop_rendered_object(id: u32);

    fn simulo_window_width() -> i32;
    fn simulo_window_height() -> i32;
}
