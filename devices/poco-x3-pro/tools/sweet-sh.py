#!/usr/bin/env python3
"""Run a program on the phone's iOS userland through sweetd (userland/src/sweetd.c, TCP 5143).

    sweet-sh.py [--timeout S] /absolute/program [args...]
    sweet-sh.py ls|cat|sysctl|rm|mkdir|kill ARGS...     sweetd's own commands
    sweet-sh.py --put LOCAL REMOTE [MODE]               a file onto the phone (MODE default 755)

Prints the program's output (stdout and stderr merged) as it comes and exits
with its status (128 + signal when it was killed). From Git Bash, set
MSYS_NO_PATHCONV=1 so absolute phone paths are not rewritten. The token
sweetd wants is userland/sweetd.token (userland/build.sh makes it, and puts it
in the image; never in git). The phone is 169.254.7.2 (kernel usbnet_ip=0xa9fe0702,
usbnet_static=1): the PC's USB Ethernet adapter gives itself a 169.254 address
when nobody answers its DHCP. From ios-jasmine's tools/sweet-sh.py.
"""
import os
import socket
import sys

HOSTS = ('169.254.7.2', '10.11.0.2')
PORT = 5143
END = b'__SWEETD_END__'
TOKEN = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'userland', 'sweetd.token')


def main():
    args = sys.argv[1:]
    timeout = 60
    if args[:1] == ['--timeout']:
        timeout = int(args[1])
        args = args[2:]
    data = b''
    if args[:1] == ['--put'] and len(args) in (3, 4):
        data = open(args[1], 'rb').read()
        args = ['put', args[2], args[3] if len(args) == 4 else '755', str(len(data))]
    if not args or (not args[0].startswith('/') and args[0] not in ('ls', 'cat', 'sysctl', 'put', 'rm', 'mkdir', 'kill')):
        sys.exit(__doc__)
    for host in HOSTS:
        try:
            s = socket.create_connection((host, PORT), timeout=5)
            break
        except OSError:
            s = None
    if s is None:
        sys.exit(f'no sweetd at {" or ".join(HOSTS)}:{PORT}')
    s.settimeout(timeout + 30)
    token = open(TOKEN).read().strip()
    s.sendall(f'RUN {token} {timeout} {len(args)}\n'.encode() + b''.join(a.encode() + b'\n' for a in args) + data)
    buf = b''
    while True:
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
        # print everything that cannot be the start of the end marker
        cut = buf.rfind(b'\n' + END)
        keep = len(buf) - len(END) - 16 if cut < 0 else cut
        if keep > 0:
            sys.stdout.buffer.write(buf[:keep])
            sys.stdout.buffer.flush()
            buf = buf[keep:]
    cut = buf.rfind(b'\n' + END)
    if cut < 0:
        sys.stdout.buffer.write(buf)
        sys.exit('\n(connection closed without a status)')
    sys.stdout.buffer.write(buf[:cut] + b'\n')
    status = int(buf[cut + len(END) + 1:].split()[0])
    sys.exit(status if status >= 0 else 128 - status)


if __name__ == '__main__':
    main()
