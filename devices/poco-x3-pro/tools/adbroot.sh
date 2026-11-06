# Sourced, not run: talk to the phone over adb as root when there is a way to.
#   adb_detect   sets ADB_STATE (device | recovery | whatever adb says) and ADB_ROOT:
#                direct  adb's own shell is root (a recovery booted with `fastboot boot`)
#                su      through `su -c` (Android with Magisk; the first call may ask on the phone's screen)
#                none    no root (stock Android: /vendor/firmware and the block devices are not readable)
#   rsh CMD      run CMD on the phone, as root when possible; its output raw (adb exec-out, binary-safe).
#                CMD must not contain single quotes. exec-out mixes the remote stderr into the output, so
#                commands whose output is data send their stderr to /dev/null on the phone.
# Git Bash (MSYS) would rewrite arguments that look like POSIX paths (/vendor/...) into Windows paths
# before they reach adb.exe; keep them as they are.
export MSYS_NO_PATHCONV=1

adb_detect() {
	ADB_STATE=$(adb get-state 2>/dev/null | tr -d '\r')
	ADB_ROOT=none
	case $ADB_STATE in device|recovery) ;; *) return 1 ;; esac
	if [ "$(adb shell id -u 2>/dev/null | tr -d '\r')" = 0 ]; then
		ADB_ROOT=direct
	elif [ "$(adb shell "su -c 'id -u'" 2>/dev/null | tr -d '\r')" = 0 ]; then
		ADB_ROOT=su
	fi
	return 0
}

rsh() {
	case $ADB_ROOT in
	su) adb exec-out "su -c '$1'" ;;
	*) adb exec-out "$1" ;;
	esac
}

# rline CMD: the first line of CMD's output, without CR
rline() { rsh "$1" | tr -d '\r' | head -1; }
