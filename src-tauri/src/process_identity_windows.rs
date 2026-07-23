#[cfg(windows)]
use std::collections::HashSet;

#[cfg(windows)]
pub fn listener_pids(port: u16) -> Option<HashSet<u32>> {
    use std::ffi::c_void;
    use windows::Win32::Foundation::ERROR_INSUFFICIENT_BUFFER;
    use windows::Win32::NetworkManagement::IpHelper::{
        GetExtendedTcpTable, MIB_TCPROW_OWNER_PID, TCP_TABLE_OWNER_PID_LISTENER,
    };
    use windows::Win32::Networking::WinSock::AF_INET;

    let mut size = 0u32;
    let status = unsafe {
        GetExtendedTcpTable(
            None,
            &mut size,
            false,
            u32::from(AF_INET.0),
            TCP_TABLE_OWNER_PID_LISTENER,
            0,
        )
    };
    if status != ERROR_INSUFFICIENT_BUFFER.0 || size < 4 {
        return None;
    }
    let mut buffer = vec![0u8; size as usize];
    let status = unsafe {
        GetExtendedTcpTable(
            Some(buffer.as_mut_ptr().cast::<c_void>()),
            &mut size,
            false,
            u32::from(AF_INET.0),
            TCP_TABLE_OWNER_PID_LISTENER,
            0,
        )
    };
    if status != 0 {
        return None;
    }
    let count = unsafe { buffer.as_ptr().cast::<u32>().read_unaligned() } as usize;
    let rows_size = count.checked_mul(std::mem::size_of::<MIB_TCPROW_OWNER_PID>())?;
    if 4usize.checked_add(rows_size)? > buffer.len() {
        return None;
    }
    let rows = unsafe { buffer.as_ptr().add(4).cast::<MIB_TCPROW_OWNER_PID>() };
    let mut pids = HashSet::new();
    for index in 0..count {
        let row = unsafe { rows.add(index).read_unaligned() };
        let address = u32::from_be(row.dwLocalAddr);
        let row_port = u16::from_be(row.dwLocalPort as u16);
        if address == u32::from_be_bytes([127, 0, 0, 1]) && row_port == port {
            pids.insert(row.dwOwningPid);
        }
    }
    Some(pids)
}
