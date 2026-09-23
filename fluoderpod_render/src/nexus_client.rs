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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json;

    #[test]
    fn test_rail_message_serialization() {
        let msg = RailMessage::Telemetry {
            payload: "hello".to_string(),
        };

        let json = serde_json::to_string(&msg).unwrap();
        assert_eq!(json, r#"{"type":"Telemetry","payload":"hello"}"#);

        let parsed: RailMessage = serde_json::from_str(&json).unwrap();
        match parsed {
            RailMessage::Telemetry { payload } => assert_eq!(payload, "hello"),
            _ => panic!("Deserialized wrong type"),
        }
    }

    #[test]
    fn test_rail_message_ping() {
        let msg = RailMessage::Ping;
        let json = serde_json::to_string(&msg).unwrap();
        assert_eq!(json, r#"{"type":"Ping"}"#);
    }
}
