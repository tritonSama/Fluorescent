use tokio::net::TcpStream;
use tokio_tungstenite::{connect_async, WebSocketStream, MaybeTlsStream};
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "type")]
pub enum RailMessage {
    Telemetry { payload: String },
    TensorDiff { diff_buffer: String, node_id: String },
    Ping,
}

pub struct NexusClient {
    // We would hold a channel sender here to send messages to a background thread
    // that handles the websocket connection, but for simplicity we just provide a struct.
}

impl NexusClient {
    pub fn new() -> Self {
        Self {}
    }

    pub async fn connect(url: &str) -> Result<WebSocketStream<MaybeTlsStream<TcpStream>>, Box<dyn std::error::Error>> {
        let (ws_stream, _) = connect_async(url).await?;
        Ok(ws_stream)
    }
}
