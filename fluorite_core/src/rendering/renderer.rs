use serde::{Deserialize, Serialize};

/// Dynamic quality tiers for the scalable AAA renderer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum QualityTier {
    /// Tier 1: Simplified renderer targeted at Mobile Android GPUs.
    Tier1,
    /// Tier 2: Enhanced renderer for high-end mobile and lower-end desktop.
    Tier2,
    /// Tier 3: High-quality renderer for mid-range desktop.
    Tier3,
    /// Tier 4: AAA renderer with advanced features (Dynamic GI, Virtual Geometry) for high-end desktop.
    Tier4,
}

/// Core renderer structure.
#[derive(Debug)]
pub struct Renderer {
    tier: QualityTier,
}

impl Renderer {
    /// Creates a new Renderer initialized with the specified quality tier.
    pub fn new(tier: QualityTier) -> Self {
        Self { tier }
    }

    /// Returns the current quality tier of the renderer.
    pub fn quality_tier(&self) -> QualityTier {
        self.tier
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_renderer_initialization_tier1() {
        let renderer = Renderer::new(QualityTier::Tier1);
        assert_eq!(renderer.quality_tier(), QualityTier::Tier1);
    }

    #[test]
    fn test_renderer_initialization_tier4() {
        let renderer = Renderer::new(QualityTier::Tier4);
        assert_eq!(renderer.quality_tier(), QualityTier::Tier4);
    }
}
