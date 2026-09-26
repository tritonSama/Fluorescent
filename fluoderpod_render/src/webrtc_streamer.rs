use std::sync::Arc;
use webrtc::api::media_engine::{MediaEngine, MIME_TYPE_H264};
use webrtc::api::APIBuilder;
use webrtc::peer_connection::configuration::RTCConfiguration;
use webrtc::rtp_transceiver::rtp_codec::RTCRtpCodecCapability;
use webrtc::track::track_local::track_local_static_rtp::TrackLocalStaticRTP;
use webrtc::track::track_local::{TrackLocal, TrackLocalWriter};
use webrtc::rtp::codecs::h264::H264Payloader;
use webrtc::rtp::packetizer::Packetizer;
use bytes::Bytes;
use webrtc::ice_transport::ice_server::RTCIceServer;
use webrtc::data_channel::data_channel_message::DataChannelMessage;
use webrtc::peer_connection::RTCPeerConnection;
use webrtc::rtp::packetizer::new_packetizer;

pub struct WebRTCStreamer {
    pub video_track: Arc<TrackLocalStaticRTP>,
    pub peer_connection: Arc<RTCPeerConnection>,
}

impl WebRTCStreamer {
    pub async fn new() -> Self {
        let mut m = MediaEngine::default();
        m.register_default_codecs().expect("Failed to register default codecs");

        let api = APIBuilder::new().with_media_engine(m).build();

        let config = RTCConfiguration {
            ice_servers: vec![RTCIceServer {
                urls: vec!["stun:stun.l.google.com:19302".to_owned()],
                ..Default::default()
            }],
            ..Default::default()
        };

        let peer_connection = Arc::new(api.new_peer_connection(config).await.expect("Failed to create PeerConnection"));

        let video_track = Arc::new(TrackLocalStaticRTP::new(
            RTCRtpCodecCapability {
                mime_type: MIME_TYPE_H264.to_owned(),
                ..Default::default()
            },
            "video".to_owned(),
            "webrtc-stream".to_owned(),
        ));

        peer_connection
            .add_track(Arc::clone(&video_track) as Arc<dyn TrackLocal + Send + Sync>)
            .await
            .expect("Failed to add video track");

        // Input DataChannel
        let data_channel = peer_connection.create_data_channel("input_controls", None).await.expect("Failed to create DataChannel");
        let d1 = Arc::clone(&data_channel);
        d1.on_message(Box::new(|msg: DataChannelMessage| {
            let msg_str = String::from_utf8(msg.data.to_vec()).unwrap_or_else(|_| "invalid utf8".to_string());
            log::info!("Received input data: {}", msg_str);
            Box::pin(async {})
        }));

        Self {
            video_track,
            peer_connection
        }
    }

    pub async fn send_video_frame(&self, frame: Vec<u8>) {
        let payloader = Box::new(H264Payloader::default());
        let mut packetizer = new_packetizer(1200, 96, 12345, payloader, Box::new(webrtc::rtp::sequence::new_random_sequencer()), 90000);

        let payload = Bytes::from(frame);

        let packets = packetizer.packetize(&payload, 1).unwrap_or_else(|_| vec![]);

        for packet in packets {
            if let Err(e) = self.video_track.write_rtp(&packet).await {
                log::error!("Failed to write video frame: {}", e);
            }
        }
    }
}
