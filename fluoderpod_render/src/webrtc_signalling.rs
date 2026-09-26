use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::accept_async;
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;
use webrtc::peer_connection::RTCPeerConnection;
use webrtc::ice_transport::ice_candidate::{RTCIceCandidate, RTCIceCandidateInit};

#[derive(Serialize, Deserialize, Debug)]
pub struct SignalMessage {
    pub sdp: Option<SDPInfo>,
    pub ice: Option<ICEInfo>,
    #[serde(rename = "type")]
    pub msg_type: String,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct SDPInfo {
    pub sdp: String,
    #[serde(rename = "type")]
    pub sdp_type: String,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct ICEInfo {
    pub candidate: String,
    #[serde(rename = "sdpMid")]
    pub sdp_mid: Option<String>,
    #[serde(rename = "sdpMLineIndex")]
    pub sdp_mline_index: Option<u16>,
}

pub struct SignallingServer {
    pub port: u16,
}

impl SignallingServer {
    pub fn new(port: u16) -> Self {
        Self { port }
    }

    pub async fn start(&self, peer_connection: Arc<RTCPeerConnection>) {
        let addr = format!("0.0.0.0:{}", self.port);
        let listener = TcpListener::bind(&addr).await.expect("Failed to bind signalling server");
        log::info!("Signalling Server listening on: {}", addr);

        while let Ok((stream, _)) = listener.accept().await {
            let pc = Arc::clone(&peer_connection);
            tokio::spawn(Self::handle_connection(stream, pc));
        }
    }

    async fn handle_connection(stream: TcpStream, peer_connection: Arc<RTCPeerConnection>) {
        let ws_stream = match accept_async(stream).await {
            Ok(ws) => ws,
            Err(e) => {
                log::error!("Error during websocket handshake: {}", e);
                return;
            }
        };

        log::info!("New signalling client connected");
        let (_, mut receiver) = ws_stream.split();

        let pc_clone = Arc::clone(&peer_connection);
        pc_clone.on_ice_candidate(Box::new(move |candidate: Option<RTCIceCandidate>| {
            Box::pin(async move {
                if let Some(c) = candidate {
                    if let Ok(json) = c.to_json() {
                        log::info!("Generated ICE candidate: {:?}", json);
                    }
                }
            })
        }));

        while let Some(msg) = receiver.next().await {
            match msg {
                Ok(tokio_tungstenite::tungstenite::Message::Text(text)) => {
                    log::info!("Received signalling msg: {}", text);
                    if let Ok(signal) = serde_json::from_str::<SignalMessage>(&text) {
                        if signal.msg_type == "offer" {
                            if let Some(sdp_info) = signal.sdp {
                                let desc = RTCSessionDescription::offer(sdp_info.sdp).unwrap();
                                let _ = peer_connection.set_remote_description(desc).await;

                                if let Ok(answer) = peer_connection.create_answer(None).await {
                                    let _ = peer_connection.set_local_description(answer).await;
                                }
                            }
                        } else if signal.msg_type == "ice" {
                            if let Some(ice_info) = signal.ice {
                                let init = RTCIceCandidateInit {
                                    candidate: ice_info.candidate,
                                    sdp_mid: ice_info.sdp_mid,
                                    sdp_mline_index: ice_info.sdp_mline_index,
                                    username_fragment: None,
                                };
                                let _ = peer_connection.add_ice_candidate(init).await;
                            }
                        }
                    }
                }
                Ok(tokio_tungstenite::tungstenite::Message::Close(_)) => {
                    log::info!("Signalling client disconnected");
                    break;
                }
                _ => {}
            }
        }
    }
}
