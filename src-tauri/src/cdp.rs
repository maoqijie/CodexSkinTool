use crate::error::{AppError, Result};
use serde::Deserialize;
use serde_json::{json, Value};
use std::io::{Read, Write};
use std::net::{Ipv4Addr, SocketAddrV4, TcpStream};
use std::time::Duration;
use tungstenite::client::connect_with_config;
use tungstenite::handshake::client::Response;
use tungstenite::{stream::MaybeTlsStream, Message, WebSocket};
use url::Url;

const MAX_HTTP_RESPONSE: usize = 1_048_576;
const WEBSOCKET_REDIRECT_LIMIT: u8 = 0;

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Target {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub url: String,
    pub web_socket_debugger_url: String,
}

pub fn list_targets(port: u16) -> Result<Vec<Target>> {
    let mut stream = TcpStream::connect_timeout(
        &SocketAddrV4::new(Ipv4Addr::LOCALHOST, port).into(),
        Duration::from_secs(2),
    )
    .map_err(|error| AppError::io("连接 Codex 本机调试端点", error))?;
    stream
        .set_read_timeout(Some(Duration::from_secs(2)))
        .map_err(|error| AppError::io("配置调试端点读取超时", error))?;
    write!(
        stream,
        "GET /json/list HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\n\r\n"
    )
    .map_err(|error| AppError::io("请求 Codex 调试目标", error))?;
    let response = read_http_response(&mut stream)?;
    parse_targets_response(&response)
}

fn read_http_response(stream: &mut TcpStream) -> Result<Vec<u8>> {
    let mut response = Vec::new();
    let expected = loop {
        if let Some(split) = response.windows(4).position(|window| window == b"\r\n\r\n") {
            let header = std::str::from_utf8(&response[..split])
                .map_err(|_| AppError::AppControl("CDP HTTP 头不是 UTF-8".into()))?;
            let length = content_length(header)?;
            break (split + 4)
                .checked_add(length)
                .filter(|length| *length <= MAX_HTTP_RESPONSE)
                .ok_or_else(|| AppError::AppControl("CDP 目标响应超过安全限制".into()))?;
        }
        read_http_chunk(stream, &mut response)?;
    };
    while response.len() < expected {
        read_http_chunk(stream, &mut response)?;
    }
    response.truncate(expected);
    Ok(response)
}

fn read_http_chunk(stream: &mut TcpStream, response: &mut Vec<u8>) -> Result<()> {
    if response.len() >= MAX_HTTP_RESPONSE {
        return Err(AppError::AppControl("CDP 目标响应超过安全限制".into()));
    }
    let mut buffer = [0_u8; 8192];
    let limit = buffer.len().min(MAX_HTTP_RESPONSE - response.len());
    let read = stream
        .read(&mut buffer[..limit])
        .map_err(|error| AppError::io("读取 Codex 调试目标", error))?;
    if read == 0 {
        return Err(AppError::AppControl("CDP HTTP 响应提前结束".into()));
    }
    response.extend_from_slice(&buffer[..read]);
    Ok(())
}

fn content_length(header: &str) -> Result<usize> {
    if header.lines().skip(1).any(|line| {
        line.split_once(':')
            .is_some_and(|(name, _)| name.trim().eq_ignore_ascii_case("transfer-encoding"))
    }) {
        return Err(AppError::AppControl("CDP 不支持分块 HTTP 响应".into()));
    }
    let lengths = header.lines().skip(1).filter_map(|line| {
        let (name, value) = line.split_once(':')?;
        name.trim()
            .eq_ignore_ascii_case("content-length")
            .then(|| value.trim())
    });
    let values: Vec<&str> = lengths.collect();
    if values.len() != 1 {
        return Err(AppError::AppControl(
            "CDP HTTP 响应缺少唯一 Content-Length".into(),
        ));
    }
    values[0]
        .parse()
        .map_err(|_| AppError::AppControl("CDP Content-Length 无效".into()))
}

fn parse_targets_response(response: &[u8]) -> Result<Vec<Target>> {
    let split = response
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .ok_or_else(|| AppError::AppControl("CDP 返回了无效 HTTP 响应".into()))?;
    let header = std::str::from_utf8(&response[..split])
        .map_err(|_| AppError::AppControl("CDP HTTP 头不是 UTF-8".into()))?;
    if !header.lines().next().is_some_and(|line| {
        let mut parts = line.split_ascii_whitespace();
        parts.next().is_some_and(|value| value.starts_with("HTTP/")) && parts.next() == Some("200")
    }) {
        return Err(AppError::AppControl("CDP 目标发现请求未成功".into()));
    }
    let targets: Vec<Target> = serde_json::from_slice(&response[split + 4..])?;
    Ok(targets
        .into_iter()
        .filter(|target| target.kind == "page" && target.url.starts_with("app://"))
        .collect())
}

pub fn validated_socket_url(target: &Target, port: u16) -> Result<Url> {
    if target.id.is_empty()
        || target.id.len() > 200
        || !target
            .id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"._-".contains(&byte))
    {
        return Err(AppError::AppControl("CDP target ID 无效".into()));
    }
    let url = Url::parse(&target.web_socket_debugger_url)
        .map_err(|_| AppError::AppControl("CDP WebSocket URL 无效".into()))?;
    let trusted_host = matches!(url.host_str(), Some("127.0.0.1" | "localhost" | "::1"));
    if url.scheme() != "ws"
        || !trusted_host
        || url.port() != Some(port)
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || url.path() != format!("/devtools/page/{}", target.id)
    {
        return Err(AppError::AppControl(
            "CDP 端点不是受信任的本机 Codex 页面".into(),
        ));
    }
    Ok(url)
}

pub fn evaluate(url: Url, expression: &str) -> Result<Value> {
    let (mut socket, _) = connect_socket(&url)
        .map_err(|error| AppError::AppControl(format!("CDP WebSocket 连接失败：{error}")))?;
    if let MaybeTlsStream::Plain(stream) = socket.get_mut() {
        stream
            .set_read_timeout(Some(Duration::from_secs(3)))
            .and_then(|_| stream.set_write_timeout(Some(Duration::from_secs(3))))
            .map_err(|error| AppError::io("配置 CDP WebSocket 超时", error))?;
    }
    socket
        .send(Message::Text(
            json!({
                "id": 1,
                "method": "Runtime.evaluate",
                "params": {"expression": expression, "awaitPromise": true, "returnByValue": true}
            })
            .to_string()
            .into(),
        ))
        .map_err(|error| AppError::AppControl(format!("发送 CDP 请求失败：{error}")))?;
    loop {
        let message = socket
            .read()
            .map_err(|error| AppError::AppControl(format!("读取 CDP 响应失败：{error}")))?;
        let bytes = match message {
            Message::Text(value) => value.as_bytes().to_vec(),
            Message::Binary(value) => value.to_vec(),
            Message::Ping(value) => {
                socket
                    .send(Message::Pong(value))
                    .map_err(|error| AppError::AppControl(format!("回复 CDP 心跳失败：{error}")))?;
                continue;
            }
            Message::Close(_) => return Err(AppError::AppControl("CDP 提前关闭连接".into())),
            _ => continue,
        };
        let response: Value = serde_json::from_slice(&bytes)?;
        if response.get("id") != Some(&Value::from(1)) {
            continue;
        }
        if let Some(error) = response.get("error") {
            return Err(AppError::AppControl(format!("CDP 协议错误：{error}")));
        }
        if response.pointer("/result/exceptionDetails").is_some() {
            return Err(AppError::AppControl("Codex 渲染器拒绝执行注入".into()));
        }
        return Ok(response
            .pointer("/result/result/value")
            .cloned()
            .unwrap_or(Value::Null));
    }
}

fn connect_socket(
    url: &Url,
) -> std::result::Result<(WebSocket<MaybeTlsStream<TcpStream>>, Response), Box<tungstenite::Error>>
{
    connect_with_config(url.as_str(), None, WEBSOCKET_REDIRECT_LIMIT).map_err(Box::new)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;
    use std::sync::mpsc;
    use std::thread;

    #[test]
    fn filters_targets_and_rejects_untrusted_sockets() {
        let body = br#"[{"id":"ok-1","type":"page","url":"app://codex/home","webSocketDebuggerUrl":"ws://127.0.0.1:9341/devtools/page/ok-1"},{"id":"web","type":"page","url":"https://example.com","webSocketDebuggerUrl":"ws://127.0.0.1:9341/devtools/page/web"}]"#;
        let mut response = b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n".to_vec();
        response.extend(body);
        let targets = parse_targets_response(&response).unwrap();
        assert_eq!(targets.len(), 1);
        assert!(validated_socket_url(&targets[0], 9341).is_ok());
        let mut target = targets[0].clone();
        target.web_socket_debugger_url = "ws://example.com:9341/devtools/page/ok-1".into();
        assert!(validated_socket_url(&target, 9341).is_err());
        target.web_socket_debugger_url = "ws://127.0.0.1:9341/devtools/page/different".into();
        assert!(validated_socket_url(&target, 9341).is_err());
    }

    #[test]
    fn target_discovery_does_not_wait_for_connection_close() {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let port = listener.local_addr().unwrap().port();
        let (done_tx, done_rx) = mpsc::channel();
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0_u8; 2048];
            let _ = stream.read(&mut request).unwrap();
            let body = br#"[{"id":"ok","type":"page","url":"app://codex/home","webSocketDebuggerUrl":"ws://127.0.0.1:1/devtools/page/ok"}]"#;
            write!(
                stream,
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: application/json\r\n\r\n",
                body.len()
            )
            .unwrap();
            stream.write_all(body).unwrap();
            done_rx.recv_timeout(Duration::from_secs(3)).unwrap();
        });
        let targets = list_targets(port).unwrap();
        assert_eq!(targets.len(), 1);
        done_tx.send(()).unwrap();
        server.join().unwrap();
    }

    #[test]
    fn websocket_handshake_rejects_redirects() {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let address = listener.local_addr().unwrap();
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0_u8; 2048];
            let _ = stream.read(&mut request).unwrap();
            stream
                .write_all(
                    b"HTTP/1.1 302 Found\r\nLocation: ws://example.com/redirected\r\nContent-Length: 0\r\n\r\n",
                )
                .unwrap();
        });
        let url = Url::parse(&format!("ws://{address}/devtools/page/target")).unwrap();
        let error = connect_socket(&url).unwrap_err();
        assert!(
            matches!(*error, tungstenite::Error::Http(response) if response.status().is_redirection())
        );
        server.join().unwrap();
    }
}
