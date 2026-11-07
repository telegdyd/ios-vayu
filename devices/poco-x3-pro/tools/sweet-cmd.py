#!/usr/bin/env python3
"""Send a command to the phone's kernel over USB Ethernet (vayu: xnu/files/bsd/dev/vayu_usbnet_ecm.c; from ios-jasmine).

    sweet-cmd.py reboot      sync, then the loader restarts the phone: iOS again
    sweet-cmd.py loader      sync, then the loader stays in its USB command mode (alias: fastboot):
                             xl runs kernels from there, "fastboot flash:boot" writes boot, "fastboot
                             reboot" starts the flashed system (loader 2.5)
    sweet-cmd.py ping        "pong" when the kernel is there

TCP port 5141 at 169.254.7.2, one line per
connection; prints the phone's answer.
"""
import socket
import sys

HOSTS = ('192.168.7.2', '169.254.7.2', '10.11.0.2')   # 192.168.7.2: the USB link outlives Wi-Fi (W26)
PORT = 5141


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    for host in HOSTS:
        try:
            with socket.create_connection((host, PORT), timeout=3) as s:
                s.sendall(sys.argv[1].encode() + b'\n')
                s.settimeout(5)
                print(s.recv(256).decode(errors='replace').strip() or '(no answer)')
                return
        except OSError:
            continue
    sys.exit(f'no command port at {" or ".join(HOSTS)}:{PORT}')


if __name__ == '__main__':
    main()
