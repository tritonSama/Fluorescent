//! BVH unit tests and benchmark.

#[cfg(test)]
mod tests {
    use super::super::spatial::bvh::{Aabb, BvhBuilder, intersect_aabb};
    use glam::Vec3A;
    use rand::{Rng, SeedableRng};
    use rand::rngs::StdRng;
    use std::time::Instant;

    fn random_aabb(rng: &mut StdRng) -> Aabb {
        // Generate a random center and half-extent.
        let center = Vec3A::new(
            rng.gen_range(-100.0..100.0),
            rng.gen_range(-100.0..100.0),
            rng.gen_range(-100.0..100.0),
        );
        let extent = Vec3A::new(
            rng.gen_range(0.1..5.0),
            rng.gen_range(0.1..5.0),
            rng.gen_range(0.1..5.0),
        );
        let min = center - extent;
        let max = center + extent;
        Aabb::new(min, max)
    }

    #[test]
    fn bvh_build_performance() {
        let mut rng = StdRng::seed_from_u64(0);
        let primitives: Vec<Aabb> = (0..10_000).map(|_| random_aabb(&mut rng)).collect();
        let start = Instant::now();
        let nodes = BvhBuilder::build(&primitives);
        let elapsed = start.elapsed();
        println!("BVH built {} nodes in {:?}", nodes.len(), elapsed);
        // Expect build under 2 ms on typical hardware.
        assert!(elapsed.as_millis() < 2, "BVH build took too long: {} ms", elapsed.as_millis());
    }

    #[test]
    fn ray_aabb_intersection_correctness() {
        let aabb = Aabb::new(Vec3A::new(-1.0, -1.0, -1.0), Vec3A::new(1.0, 1.0, 1.0));
        // Ray from outside pointing towards center.
        let origin = Vec3A::new(0.0, 0.0, -5.0);
        let dir = Vec3A::new(0.0, 0.0, 1.0);
        let dir_inv = Vec3A::new(1.0 / dir.x, 1.0 / dir.y, 1.0 / dir.z);
        assert!(intersect_aabb(origin, dir_inv, &aabb));
        // Ray missing the box.
        let origin2 = Vec3A::new(5.0, 5.0, -5.0);
        let dir2 = Vec3A::new(0.0, 0.0, 1.0);
        let dir_inv2 = Vec3A::new(1.0 / dir2.x, 1.0 / dir2.y, 1.0 / dir2.z);
        assert!(!intersect_aabb(origin2, dir_inv2, &aabb));
    }
}
