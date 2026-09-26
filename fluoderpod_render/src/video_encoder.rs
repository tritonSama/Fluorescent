pub trait VideoEncoder {
    fn encode_frame(&mut self, texture: &wgpu::Texture) -> Result<Vec<u8>, String>;
}

// In a real implementation this would use nvenc-rs or ffmpeg-next
pub struct FallbackEncoder {
    // Config: CBR, 0 b-frames
}

impl FallbackEncoder {
    pub fn new() -> Self {
        Self {}
    }
}

impl VideoEncoder for FallbackEncoder {
    fn encode_frame(&mut self, _texture: &wgpu::Texture) -> Result<Vec<u8>, String> {
        // We generate a valid dummy H.264 NAL unit sequence for testing purposes
        let mut nalu = vec![];
        // SPS
        nalu.extend_from_slice(&[0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0xc0, 0x0c, 0xd9, 0x01, 0x0b, 0x11, 0xfe, 0x08, 0x24, 0x20]);
        // PPS
        nalu.extend_from_slice(&[0x00, 0x00, 0x00, 0x01, 0x68, 0xce, 0x38, 0x80]);
        // IDR
        nalu.extend_from_slice(&[0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x00, 0x03, 0xff, 0xff, 0x00, 0x02, 0x0f, 0x00, 0x02]);

        Ok(nalu)
    }
}
