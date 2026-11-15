//! mDNS / DNS-SD responder (RFC 6762, 6763): just enough for the app's NSNetServiceBrowser to find
//! the server on the home network. Answers
//!
//! - `_tubemini._tcp.local` PTR → `TubeMini (<host>)._tubemini._tcp.local`, with SRV, TXT and A;
//! - `_services._dns-sd._udp.local` PTR → `_tubemini._tcp.local`;
//! - SRV / TXT of the instance, A of `tubemini-<host>.local`.
//!
//! One UDP socket on 5353 (shared with the OS responder) joined to 224.0.0.251. Multicast stays in
//! the local subnet, so an iPad on another subnet will not see the server (docs/API.md).

use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, UdpSocket as StdUdp};
use std::time::Duration;

use anyhow::{Context, Result};
use socket2::{Domain, Protocol, Socket, Type};

const GROUP: Ipv4Addr = Ipv4Addr::new(224, 0, 0, 251);
const PORT: u16 = 5353;
const SERVICE: &str = "_tubemini._tcp.local";
const META: &str = "_services._dns-sd._udp.local";

const T_A: u16 = 1;
const T_PTR: u16 = 12;
const T_TXT: u16 = 16;
const T_SRV: u16 = 33;
const T_ANY: u16 = 255;
const CLASS_IN: u16 = 1;
/// "Cache flush" bit on records only this host owns.
const FLUSH: u16 = 0x8000;

/// What the server announces.
#[derive(Debug, Clone)]
pub struct Service {
    pub instance: String, // "TubeMini (pc)._tubemini._tcp.local"
    pub host: String,     // "tubemini-pc.local"
    pub ip: Ipv4Addr,
    pub port: u16,
    pub txt: Vec<String>,
}

impl Service {
    pub fn new(machine: &str, ip: Ipv4Addr, port: u16, version: &str) -> Self {
        let label: String = machine
            .to_lowercase()
            .chars()
            .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
            .collect::<String>()
            .trim_matches('-')
            .to_owned();
        let label = if label.is_empty() {
            "server".to_owned()
        } else {
            label
        };
        Self {
            instance: format!("TubeMini ({label}).{SERVICE}"),
            host: format!("tubemini-{label}.local"),
            ip,
            port,
            txt: vec![format!("v={version}"), "path=/".to_owned()],
        }
    }
}

// ---------- wire format ----------

fn put_name(out: &mut Vec<u8>, name: &str) {
    // The instance label ("TubeMini (pc)") is one label even with spaces / parentheses: it ends at
    // the first "._"; the rest splits on dots.
    let (first, rest) = match name.find("._") {
        Some(i) => (&name[..i], &name[i + 1..]),
        None => ("", name),
    };
    if !first.is_empty() {
        out.push(first.len() as u8);
        out.extend_from_slice(first.as_bytes());
    }
    for label in rest.split('.').filter(|l| !l.is_empty()) {
        out.push(label.len() as u8);
        out.extend_from_slice(label.as_bytes());
    }
    out.push(0);
}

fn put_record(out: &mut Vec<u8>, name: &str, rtype: u16, class: u16, ttl: u32, data: &[u8]) {
    put_name(out, name);
    out.extend_from_slice(&rtype.to_be_bytes());
    out.extend_from_slice(&class.to_be_bytes());
    out.extend_from_slice(&ttl.to_be_bytes());
    out.extend_from_slice(&(data.len() as u16).to_be_bytes());
    out.extend_from_slice(data);
}

fn name_bytes(name: &str) -> Vec<u8> {
    let mut v = Vec::new();
    put_name(&mut v, name);
    v
}

/// Reads a (possibly compressed) name at `pos`; returns it and the position after it.
fn read_name(msg: &[u8], mut pos: usize) -> Option<(String, usize)> {
    let mut labels = Vec::new();
    let mut end = None;
    for _ in 0..64 {
        let len = *msg.get(pos)? as usize;
        if len == 0 {
            return Some((labels.join("."), end.unwrap_or(pos + 1)));
        }
        if len & 0xC0 == 0xC0 {
            let target = ((len & 0x3F) << 8) | *msg.get(pos + 1)? as usize;
            end.get_or_insert(pos + 2);
            pos = target;
            continue;
        }
        let label = msg.get(pos + 1..pos + 1 + len)?;
        labels.push(String::from_utf8_lossy(label).into_owned());
        pos += 1 + len;
    }
    None
}

/// (name, type) of each question of a query; None for responses and malformed messages.
fn questions(msg: &[u8]) -> Option<Vec<(String, u16)>> {
    if msg.len() < 12 || msg[2] & 0x80 != 0 {
        return None; // too short, or a response
    }
    let count = u16::from_be_bytes([msg[4], msg[5]]);
    let mut pos = 12;
    let mut out = Vec::new();
    for _ in 0..count {
        let (name, next) = read_name(msg, pos)?;
        let rtype = u16::from_be_bytes([*msg.get(next)?, *msg.get(next + 1)?]);
        out.push((name, rtype));
        pos = next + 4;
    }
    Some(out)
}

/// The answer to `query` (DNS message), or None when nothing in it is about us. `id` is echoed for
/// legacy unicast queries (source port ≠ 5353), 0 otherwise.
pub fn respond(svc: &Service, query: &[u8], id: u16) -> Option<Vec<u8>> {
    let qs = questions(query)?;
    let is = |a: &str, b: &str| a.eq_ignore_ascii_case(b);
    let mut ptr_service = false;
    let mut ptr_meta = false;
    let mut instance = false;
    let mut host = false;
    for (name, t) in &qs {
        let any = *t == T_ANY;
        if is(name, SERVICE) && (*t == T_PTR || any) {
            ptr_service = true;
        } else if is(name, META) && (*t == T_PTR || any) {
            ptr_meta = true;
        } else if is(name, &svc.instance) && matches!(*t, T_SRV | T_TXT | T_ANY) {
            instance = true;
        } else if is(name, &svc.host) && (*t == T_A || any) {
            host = true;
        }
    }
    if !(ptr_service || ptr_meta || instance || host) {
        return None;
    }
    Some(message(
        svc,
        id,
        ptr_service,
        ptr_meta,
        instance || ptr_service,
        host || instance || ptr_service,
    ))
}

/// A response with the requested records (answers) — used for replies and announcements.
fn message(
    svc: &Service,
    id: u16,
    ptr_service: bool,
    ptr_meta: bool,
    instance: bool,
    host: bool,
) -> Vec<u8> {
    let mut records = Vec::new();
    let mut count = 0u16;
    if ptr_meta {
        put_record(
            &mut records,
            META,
            T_PTR,
            CLASS_IN,
            4500,
            &name_bytes(SERVICE),
        );
        count += 1;
    }
    if ptr_service {
        put_record(
            &mut records,
            SERVICE,
            T_PTR,
            CLASS_IN,
            4500,
            &name_bytes(&svc.instance),
        );
        count += 1;
    }
    if instance {
        let mut srv = vec![0, 0, 0, 0]; // priority, weight
        srv.extend_from_slice(&svc.port.to_be_bytes());
        srv.extend(name_bytes(&svc.host));
        put_record(
            &mut records,
            &svc.instance,
            T_SRV,
            CLASS_IN | FLUSH,
            120,
            &srv,
        );
        let mut txt = Vec::new();
        for entry in &svc.txt {
            txt.push(entry.len() as u8);
            txt.extend_from_slice(entry.as_bytes());
        }
        put_record(
            &mut records,
            &svc.instance,
            T_TXT,
            CLASS_IN | FLUSH,
            4500,
            &txt,
        );
        count += 2;
    }
    if host {
        put_record(
            &mut records,
            &svc.host,
            T_A,
            CLASS_IN | FLUSH,
            120,
            &svc.ip.octets(),
        );
        count += 1;
    }
    let mut out = Vec::with_capacity(12 + records.len());
    out.extend_from_slice(&id.to_be_bytes());
    out.extend_from_slice(&0x8400u16.to_be_bytes()); // response, authoritative
    out.extend_from_slice(&[0, 0]); // questions
    out.extend_from_slice(&count.to_be_bytes());
    out.extend_from_slice(&[0, 0, 0, 0]); // authority, additional
    out.extend(records);
    out
}

// ---------- network ----------

/// IPv4 of the interface that routes outward (no packet is sent by `connect` on UDP).
pub fn local_ip() -> Option<Ipv4Addr> {
    let s = StdUdp::bind("0.0.0.0:0").ok()?;
    s.connect("192.0.2.1:9").ok()?;
    match s.local_addr().ok()? {
        SocketAddr::V4(a) if !a.ip().is_unspecified() => Some(*a.ip()),
        _ => None,
    }
}

fn open(ip: Ipv4Addr) -> Result<tokio::net::UdpSocket> {
    let sock = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    sock.set_reuse_address(true)?;
    #[cfg(unix)]
    sock.set_reuse_port(true)?;
    sock.bind(&SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, PORT).into())
        .context("binding UDP 5353")?;
    sock.join_multicast_v4(&GROUP, &ip)
        .context("joining 224.0.0.251")?;
    sock.set_multicast_if_v4(&ip)?;
    sock.set_multicast_ttl_v4(255)?;
    sock.set_nonblocking(true)?;
    Ok(tokio::net::UdpSocket::from_std(sock.into())?)
}

/// Announces the service and answers queries until the process ends. Errors are logged, not fatal.
pub fn spawn(port: u16, version: &'static str) {
    tokio::spawn(async move {
        if let Err(e) = run(port, version).await {
            tracing::warn!("mDNS: {e:#}");
        }
    });
}

async fn run(port: u16, version: &str) -> Result<()> {
    let ip = local_ip().context("no IPv4 address on the local network")?;
    let machine = std::env::var("COMPUTERNAME")
        .or_else(|_| std::env::var("HOSTNAME"))
        .or_else(|_| std::fs::read_to_string("/etc/hostname"))
        .unwrap_or_default();
    let svc = Service::new(machine.trim(), ip, port, version);
    let sock = open(ip)?;
    let group = SocketAddr::from((GROUP, PORT));
    tracing::info!("mDNS: {} → {}:{}", svc.instance, ip, port);
    // Two unsolicited announcements, one second apart (RFC 6762 §8.3)
    let announce = message(&svc, 0, true, false, true, true);
    for _ in 0..2 {
        sock.send_to(&announce, group).await?;
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
    let mut buf = vec![0u8; 9000];
    loop {
        let (n, from) = sock.recv_from(&mut buf).await?;
        let legacy = from.port() != PORT;
        let id = if legacy {
            u16::from_be_bytes([buf[0], buf[1]])
        } else {
            0
        };
        if let Some(reply) = respond(&svc, &buf[..n], id) {
            let to = if legacy { from } else { group };
            if let Err(e) = sock.send_to(&reply, to).await {
                tracing::debug!("mDNS reply to {to}: {e}");
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn svc() -> Service {
        Service::new(
            "Living-Room PC",
            Ipv4Addr::new(192, 168, 1, 30),
            8080,
            "0.5.0",
        )
    }

    fn query(name: &str, rtype: u16) -> Vec<u8> {
        let mut q = vec![0x12, 0x34, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0];
        put_name(&mut q, name);
        q.extend_from_slice(&rtype.to_be_bytes());
        q.extend_from_slice(&0x8001u16.to_be_bytes()); // IN + unicast-response bit
        q
    }

    /// (name, type, data) of every answer record.
    fn answers(msg: &[u8]) -> Vec<(String, u16, Vec<u8>)> {
        let count = u16::from_be_bytes([msg[6], msg[7]]);
        let mut pos = 12;
        let mut out = Vec::new();
        for _ in 0..count {
            let (name, next) = read_name(msg, pos).unwrap();
            let rtype = u16::from_be_bytes([msg[next], msg[next + 1]]);
            let len = u16::from_be_bytes([msg[next + 8], msg[next + 9]]) as usize;
            out.push((name, rtype, msg[next + 10..next + 10 + len].to_vec()));
            pos = next + 10 + len;
        }
        out
    }

    #[test]
    fn names_are_sanitised() {
        let s = svc();
        assert_eq!(s.instance, "TubeMini (living-room-pc)._tubemini._tcp.local");
        assert_eq!(s.host, "tubemini-living-room-pc.local");
        assert_eq!(
            Service::new("", Ipv4Addr::LOCALHOST, 1, "x").host,
            "tubemini-server.local"
        );
    }

    #[test]
    fn browsing_gets_ptr_srv_txt_and_a() {
        let s = svc();
        let reply = respond(&s, &query("_TubeMini._tcp.local", T_PTR), 0).unwrap();
        assert_eq!(&reply[..4], &[0, 0, 0x84, 0]);
        let recs = answers(&reply);
        let types: Vec<u16> = recs.iter().map(|r| r.1).collect();
        assert_eq!(types, [T_PTR, T_SRV, T_TXT, T_A]);
        let (instance, _) = read_name(&recs[0].2, 0).unwrap();
        assert_eq!(instance, "TubeMini (living-room-pc)._tubemini._tcp.local");
        // SRV: priority 0, weight 0, port 8080, target host
        assert_eq!(&recs[1].2[4..6], &8080u16.to_be_bytes());
        assert_eq!(
            read_name(&recs[1].2, 6).unwrap().0,
            "tubemini-living-room-pc.local"
        );
        assert_eq!(recs[2].2, b"\x07v=0.5.0\x06path=/");
        assert_eq!(recs[3].2, [192, 168, 1, 30]);
    }

    #[test]
    fn answers_only_what_is_ours() {
        let s = svc();
        assert!(respond(&s, &query("_airplay._tcp.local", T_PTR), 0).is_none());
        let meta = answers(&respond(&s, &query(META, T_PTR), 0).unwrap());
        assert_eq!(meta.len(), 1);
        assert_eq!(read_name(&meta[0].2, 0).unwrap().0, SERVICE);
        let a = answers(&respond(&s, &query("tubemini-living-room-pc.local", T_A), 0).unwrap());
        assert_eq!(a.len(), 1);
        // A response is never answered
        let mut resp = query(SERVICE, T_PTR);
        resp[2] = 0x84;
        assert!(respond(&s, &resp, 0).is_none());
        // Legacy unicast: the id is echoed
        assert_eq!(
            &respond(&s, &query(SERVICE, T_PTR), 0x1234).unwrap()[..2],
            &[0x12, 0x34]
        );
    }

    #[test]
    fn compressed_names_are_read() {
        // "local" at 12, then "_tcp" + pointer to it
        let mut m = vec![0u8; 12];
        m.extend_from_slice(b"\x05local\x00");
        m.extend_from_slice(b"\x04_tcp\xC0\x0C");
        assert_eq!(read_name(&m, 19).unwrap(), ("_tcp.local".to_owned(), 26));
        // A pointer loop does not hang
        let looped = [0u8; 12]
            .iter()
            .copied()
            .chain([0xC0, 12])
            .collect::<Vec<_>>();
        assert!(read_name(&looped, 12).is_none());
    }
}
