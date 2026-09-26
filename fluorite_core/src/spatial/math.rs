//! Spatial math primitives: AABB, Plane, Frustum, Ray, and FrustumIntersection.

use glam::{Mat4, Vec3A, Vec4};

/// Axis-Aligned Bounding Box (AABB) using 16-byte aligned SIMD vectors.
#[repr(C, align(16))]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Aabb {
    pub min: Vec3A,
    pub max: Vec3A,
}

impl Default for Aabb {
    #[inline]
    fn default() -> Self {
        Self::EMPTY
    }
}

impl Aabb {
    /// An empty, inverted AABB for accumulating bounds.
    pub const EMPTY: Self = Self {
        min: Vec3A::splat(f32::INFINITY),
        max: Vec3A::splat(-f32::INFINITY),
    };

    /// Creates an AABB from explicit minimum and maximum coordinates.
    #[inline]
    pub fn new(min: Vec3A, max: Vec3A) -> Self {
        Self { min, max }
    }

    /// Creates an AABB ensuring min <= max component-wise.
    #[inline]
    pub fn from_min_max(min: Vec3A, max: Vec3A) -> Self {
        Self {
            min: min.min(max),
            max: min.max(max),
        }
    }

    /// Creates an AABB enclosing a single point (zero volume).
    #[inline]
    pub fn from_point(point: Vec3A) -> Self {
        Self {
            min: point,
            max: point,
        }
    }

    /// Creates an AABB enclosing a slice of points.
    pub fn from_points(points: &[Vec3A]) -> Self {
        if points.is_empty() {
            return Self::EMPTY;
        }
        let mut min = points[0];
        let mut max = points[0];
        for &p in &points[1..] {
            min = min.min(p);
            max = max.max(p);
        }
        Self { min, max }
    }

    /// Creates an AABB from float arrays [f32; 3].
    #[inline]
    pub fn from_arrays(min: [f32; 3], max: [f32; 3]) -> Self {
        Self {
            min: Vec3A::from_slice(&min),
            max: Vec3A::from_slice(&max),
        }
    }

    /// Returns the minimum coordinates as a float array.
    #[inline]
    pub fn min_array(&self) -> [f32; 3] {
        self.min.to_array()
    }

    /// Returns the maximum coordinates as a float array.
    #[inline]
    pub fn max_array(&self) -> [f32; 3] {
        self.max.to_array()
    }

    /// Center of the bounding box.
    #[inline]
    pub fn center(&self) -> Vec3A {
        (self.min + self.max) * 0.5
    }

    /// Half-extents (radii along X, Y, Z axes).
    #[inline]
    pub fn extents(&self) -> Vec3A {
        (self.max - self.min) * 0.5
    }

    /// Total size (width, height, depth) of the bounding box.
    #[inline]
    pub fn size(&self) -> Vec3A {
        (self.max - self.min).max(Vec3A::ZERO)
    }

    /// Surface area of the AABB, used for SAH (Surface Area Heuristic) cost calculation.
    #[inline]
    pub fn surface_area(&self) -> f32 {
        let d = self.size();
        2.0 * (d.x * d.y + d.y * d.z + d.z * d.x)
    }

    /// Returns the smallest bounding box containing both `self` and `other`.
    #[inline]
    pub fn merge(&self, other: &Self) -> Self {
        Self {
            min: self.min.min(other.min),
            max: self.max.max(other.max),
        }
    }

    /// Alias for `merge`.
    #[inline]
    pub fn union(&self, other: &Self) -> Self {
        self.merge(other)
    }

    /// Expands this AABB to enclose the given point.
    #[inline]
    pub fn expand_to_point(&self, point: Vec3A) -> Self {
        Self {
            min: self.min.min(point),
            max: self.max.max(point),
        }
    }

    /// Checks if this AABB intersects another AABB (overlapping or touching).
    #[inline]
    pub fn intersects(&self, other: &Self) -> bool {
        self.min.x <= other.max.x
            && self.max.x >= other.min.x
            && self.min.y <= other.max.y
            && self.max.y >= other.min.y
            && self.min.z <= other.max.z
            && self.max.z >= other.min.z
    }

    /// Checks if a point lies on or inside this AABB.
    #[inline]
    pub fn contains_point(&self, point: Vec3A) -> bool {
        point.x >= self.min.x
            && point.x <= self.max.x
            && point.y >= self.min.y
            && point.y <= self.max.y
            && point.z >= self.min.z
            && point.z <= self.max.z
    }

    /// Checks if this AABB fully contains another AABB.
    #[inline]
    pub fn contains_aabb(&self, other: &Self) -> bool {
        self.min.x <= other.min.x
            && self.max.x >= other.max.x
            && self.min.y <= other.min.y
            && self.max.y >= other.max.y
            && self.min.z <= other.min.z
            && self.max.z >= other.max.z
    }

    /// Checks if the bounding box has inverted or invalid dimensions.
    #[inline]
    pub fn is_empty(&self) -> bool {
        self.min.x > self.max.x || self.min.y > self.max.y || self.min.z > self.max.z
    }
}

/// 3D Plane represented in Hesse normal form: `dot(normal, point) + distance = 0`.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Plane {
    pub normal: Vec3A,
    pub distance: f32,
}

impl Plane {
    /// Creates a plane with given normal and distance.
    #[inline]
    pub fn new(normal: Vec3A, distance: f32) -> Self {
        Self { normal, distance }
    }

    /// Creates a plane from a point on the plane and a surface normal.
    #[inline]
    pub fn from_point_and_normal(point: Vec3A, normal: Vec3A) -> Self {
        let n = normal.normalize();
        let d = -n.dot(point);
        Self {
            normal: n,
            distance: d,
        }
    }

    /// Signed distance from a point to the plane.
    /// Returns > 0 if the point is in the positive (front / inside) half-space,
    /// < 0 if in the negative (behind / outside) half-space.
    #[inline]
    pub fn signed_distance(&self, point: Vec3A) -> f32 {
        self.normal.dot(point) + self.distance
    }

    /// Normalizes plane equation such that |normal| == 1.
    #[inline]
    pub fn normalized(&self) -> Self {
        let len = self.normal.length();
        if len > 1e-8 {
            let inv_len = 1.0 / len;
            Self {
                normal: self.normal * inv_len,
                distance: self.distance * inv_len,
            }
        } else {
            *self
        }
    }
}

/// Classification of an AABB against a viewing frustum.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FrustumIntersection {
    /// AABB is completely outside the frustum; subtree can be pruned immediately.
    Outside,
    /// AABB is completely inside all frustum planes; all descendants inherit inside state.
    Inside,
    /// AABB intersects one or more frustum planes; traversal continues.
    Intersecting,
}

/// 6-plane viewing frustum for hierarchical frustum culling.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Frustum {
    /// Order: [Left, Right, Bottom, Top, Near, Far]
    pub planes: [Plane; 6],
}

impl Frustum {
    /// Creates a Frustum from an array of 6 normalized planes.
    #[inline]
    pub fn new(planes: [Plane; 6]) -> Self {
        Self { planes }
    }

    /// Extracts 6 frustum planes from a combined View-Projection matrix using Gribb-Hartmann.
    ///
    /// Handles standard WebGPU/Vulkan/DirectX depth range [0, 1] as produced by
    /// `glam::Mat4::perspective_rh`.
    pub fn from_view_projection(vp: Mat4) -> Self {
        Self::from_view_projection_ext(vp, false)
    }

    /// Extracts 6 frustum planes for OpenGL depth range [-1, 1].
    pub fn from_view_projection_gl(vp: Mat4) -> Self {
        Self::from_view_projection_ext(vp, true)
    }

    fn from_view_projection_ext(vp: Mat4, is_opengl: bool) -> Self {
        // In glam column-major Mat4:
        // x_axis, y_axis, z_axis, w_axis are columns 0, 1, 2, 3.
        let c0 = vp.x_axis;
        let c1 = vp.y_axis;
        let c2 = vp.z_axis;
        let c3 = vp.w_axis;

        // Rows of the matrix
        let r0 = Vec4::new(c0.x, c1.x, c2.x, c3.x);
        let r1 = Vec4::new(c0.y, c1.y, c2.y, c3.y);
        let r2 = Vec4::new(c0.z, c1.z, c2.z, c3.z);
        let r3 = Vec4::new(c0.w, c1.w, c2.w, c3.w);

        // Plane equations:
        // Left:   r3 + r0 >= 0
        // Right:  r3 - r0 >= 0
        // Bottom: r3 + r1 >= 0
        // Top:    r3 - r1 >= 0
        // Near:   r2 >= 0 (WebGPU [0, 1]) or r3 + r2 >= 0 (OpenGL [-1, 1])
        // Far:    r3 - r2 >= 0
        let left_v = r3 + r0;
        let right_v = r3 - r0;
        let bottom_v = r3 + r1;
        let top_v = r3 - r1;
        let near_v = if is_opengl { r3 + r2 } else { r2 };
        let far_v = r3 - r2;

        let normalize = |v: Vec4| -> Plane {
            let normal = Vec3A::new(v.x, v.y, v.z);
            let len = normal.length();
            if len > 1e-8 {
                let inv = 1.0 / len;
                Plane {
                    normal: normal * inv,
                    distance: v.w * inv,
                }
            } else {
                Plane {
                    normal: Vec3A::ZERO,
                    distance: 0.0,
                }
            }
        };

        Self {
            planes: [
                normalize(left_v),
                normalize(right_v),
                normalize(bottom_v),
                normalize(top_v),
                normalize(near_v),
                normalize(far_v),
            ],
        }
    }

    /// Tests an AABB against the frustum using center-extents projection.
    #[inline]
    pub fn test_aabb(&self, aabb: &Aabb) -> FrustumIntersection {
        self.test_box_center_extents(aabb.center(), aabb.extents())
    }

    /// Tests an AABB defined by min and max vectors.
    #[inline]
    pub fn test_min_max(&self, min: Vec3A, max: Vec3A) -> FrustumIntersection {
        let center = (min + max) * 0.5;
        let extents = (max - min) * 0.5;
        self.test_box_center_extents(center, extents)
    }

    /// High-performance center-extents projection test against 6 frustum planes.
    ///
    /// For each plane:
    /// - r = extents · |normal|
    /// - s = normal · center + distance
    /// If s < -r for ANY plane, the box is strictly Outside.
    /// If s > r for ALL planes, the box is strictly Inside.
    /// Otherwise, the box is Intersecting.
    #[inline]
    pub fn test_box_center_extents(&self, center: Vec3A, extents: Vec3A) -> FrustumIntersection {
        let mut fully_inside = true;
        for plane in &self.planes {
            let normal_abs = plane.normal.abs();
            let r = extents.dot(normal_abs);
            let s = plane.normal.dot(center) + plane.distance;

            if s < -r {
                return FrustumIntersection::Outside;
            }
            if s <= r {
                fully_inside = false;
            }
        }

        if fully_inside {
            FrustumIntersection::Inside
        } else {
            FrustumIntersection::Intersecting
        }
    }
}

/// 3D Ray with precomputed reciprocal direction for branchless slab intersection tests.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Ray {
    pub origin: Vec3A,
    pub dir: Vec3A,
    pub inv_dir: Vec3A,
    pub t_min: f32,
    pub t_max: f32,
}

impl Ray {
    /// Creates a new ray with origin, direction, and parametric distance bounds.
    #[inline]
    pub fn new(origin: Vec3A, dir: Vec3A, t_min: f32, t_max: f32) -> Self {
        let dir_norm = dir.normalize();
        let inv_x = if dir_norm.x.abs() > 1e-9 {
            1.0 / dir_norm.x
        } else {
            if dir_norm.x >= 0.0 {
                1e9
            } else {
                -1e9
            }
        };
        let inv_y = if dir_norm.y.abs() > 1e-9 {
            1.0 / dir_norm.y
        } else {
            if dir_norm.y >= 0.0 {
                1e9
            } else {
                -1e9
            }
        };
        let inv_z = if dir_norm.z.abs() > 1e-9 {
            1.0 / dir_norm.z
        } else {
            if dir_norm.z >= 0.0 {
                1e9
            } else {
                -1e9
            }
        };

        Self {
            origin,
            dir: dir_norm,
            inv_dir: Vec3A::new(inv_x, inv_y, inv_z),
            t_min,
            t_max,
        }
    }

    /// Creates a ray pointing from origin to a target point.
    #[inline]
    pub fn from_points(origin: Vec3A, target: Vec3A) -> Self {
        let delta = target - origin;
        let dist = delta.length();
        let dir = if dist > 1e-8 { delta / dist } else { Vec3A::Z };
        Self::new(origin, dir, 0.0, dist)
    }

    /// Evaluates the point along the ray at parametric distance `t`.
    #[inline]
    pub fn at(&self, t: f32) -> Vec3A {
        self.origin + self.dir * t
    }

    /// Branchless SIMD slab ray-AABB intersection test.
    ///
    /// Returns `(true, t_enter)` if the ray intersects the box within `[self.t_min, current_t_max]`.
    #[inline]
    pub fn slab_test_with_tmax(&self, min: Vec3A, max: Vec3A, current_t_max: f32) -> (bool, f32) {
        let t0 = (min - self.origin) * self.inv_dir;
        let t1 = (max - self.origin) * self.inv_dir;

        let tmin = t0.min(t1);
        let tmax = t0.max(t1);

        let t_enter = tmin.x.max(tmin.y).max(tmin.z).max(self.t_min);
        let t_exit = tmax.x.min(tmax.y).min(tmax.z).min(current_t_max);

        if t_enter <= t_exit && t_exit >= self.t_min && t_enter < f32::INFINITY {
            (true, t_enter)
        } else {
            (false, f32::INFINITY)
        }
    }

    /// Tests ray against an AABB within `[self.t_min, self.t_max]`.
    #[inline]
    pub fn intersects_aabb(&self, aabb: &Aabb) -> Option<f32> {
        self.intersects_aabb_tmax(aabb, self.t_max)
    }

    /// Tests ray against an AABB with an explicit maximum distance clamp.
    #[inline]
    pub fn intersects_aabb_tmax(&self, aabb: &Aabb, current_t_max: f32) -> Option<f32> {
        let (hit, t_enter) = self.slab_test_with_tmax(aabb.min, aabb.max, current_t_max);
        if hit {
            Some(t_enter)
        } else {
            None
        }
    }
}
