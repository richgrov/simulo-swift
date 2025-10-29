use std::ops::{Add, Deref, DerefMut};

use glam::Vec3;
use shipyard::{Borrow, BorrowInfo, Component, View, ViewMut};

#[derive(Component, Clone, Copy, Default)]
pub struct Position(pub Vec3);

impl Position {
    pub fn new(x: f32, y: f32, z: f32) -> Self {
        Self(Vec3::new(x, y, z))
    }
}

impl Add<Vec3> for Position {
    type Output = Self;

    fn add(self, other: Vec3) -> Self::Output {
        Self(self.0 + other)
    }
}

impl Deref for Position {
    type Target = Vec3;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl DerefMut for Position {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

#[derive(Component, Clone, Copy, Default)]
pub struct Rotation(pub f32);

impl Deref for Rotation {
    type Target = f32;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl DerefMut for Rotation {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

#[derive(Component, Clone, Copy, Default)]
pub struct Scale(pub Vec3);

impl Scale {
    pub fn new(x: f32, y: f32, z: f32) -> Self {
        Self(Vec3::new(x, y, z))
    }
}

impl Deref for Scale {
    type Target = Vec3;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl DerefMut for Scale {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

#[derive(Borrow, BorrowInfo)]
pub struct PosScaleView<'v> {
    pub v_positions: View<'v, Position>,
    pub v_scales: View<'v, Scale>,
}

impl<'v> PosScaleView<'v> {
    pub fn view(&self) -> (&View<'v, Position>, &View<'v, Scale>) {
        (&self.v_positions, &self.v_scales)
    }
}

#[derive(Borrow, BorrowInfo)]
pub struct PosScaleViewMut<'v> {
    pub v_positions: ViewMut<'v, Position>,
    pub v_scales: ViewMut<'v, Scale>,
}

impl<'v> PosScaleViewMut<'v> {
    pub fn view(&mut self) -> (&mut ViewMut<'v, Position>, &mut ViewMut<'v, Scale>) {
        (&mut self.v_positions, &mut self.v_scales)
    }
}

#[derive(Borrow, BorrowInfo)]
pub struct PosRotScaleView<'v> {
    pub v_positions: View<'v, Position>,
    pub v_rotations: View<'v, Rotation>,
    pub v_scales: View<'v, Scale>,
}

impl<'v> PosRotScaleView<'v> {
    pub fn view(&self) -> (&View<'v, Position>, &View<'v, Rotation>, &View<'v, Scale>) {
        (&self.v_positions, &self.v_rotations, &self.v_scales)
    }
}

#[derive(Borrow, BorrowInfo)]
pub struct PosRotScaleViewMut<'v> {
    pub v_positions: ViewMut<'v, Position>,
    pub v_rotations: ViewMut<'v, Rotation>,
    pub v_scales: ViewMut<'v, Scale>,
}

impl<'v> PosRotScaleViewMut<'v> {
    pub fn view(
        &mut self,
    ) -> (
        &mut ViewMut<'v, Position>,
        &mut ViewMut<'v, Rotation>,
        &mut ViewMut<'v, Scale>,
    ) {
        (
            &mut self.v_positions,
            &mut self.v_rotations,
            &mut self.v_scales,
        )
    }
}
