#!/usr/bin/env python3
"""Send a Wake-on-LAN magic packet. See .claude/notes/remote-pc-wake.md.

Usage: python3 wake_on_lan.py <MAC address> [broadcast IP] [port]
Example: python3 wake_on_lan.py AA:BB:CC:DD:EE:FF 192.168.1.255 9
"""

import socket
import sys


def send_magic_packet(mac: str, broadcast_ip: str = "255.255.255.255", port: int = 9) -> None:
    mac_bytes = bytes.fromhex(mac.replace(":", "").replace("-", ""))
    if len(mac_bytes) != 6:
        raise ValueError(f"Invalid MAC address: {mac}")
    packet = b"\xff" * 6 + mac_bytes * 16
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.sendto(packet, (broadcast_ip, port))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    mac_arg = sys.argv[1]
    broadcast_arg = sys.argv[2] if len(sys.argv) > 2 else "255.255.255.255"
    port_arg = int(sys.argv[3]) if len(sys.argv) > 3 else 9
    send_magic_packet(mac_arg, broadcast_arg, port_arg)
    print(f"Magic packet sent to {mac_arg} via {broadcast_arg}:{port_arg}")
