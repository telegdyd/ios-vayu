/*
 * flash_stage: a new boot image for vayu's `boot`, from iOS (2026-11-07: deploys no longer go through the
 * loader's USB mode, which hangs after a forced restart -- NOTES.md "Loader-mode hang (parked)").
 *
 * iOS never writes `boot` itself: it may only write darwin, past ufs_write_first (hakios.ufs.c), and the
 * loader on core 0, which performs those writes, refuses anything else. So the image is staged in darwin
 * and the loader writes it at its next start (xnuloader/loader.c, standalone_staged_flash, loader 2.8):
 *
 *   flash_stage stage IMAGE    IMAGE (an Android boot image, "ANDROID!") into darwin from block 2621440
 *                              (var_store's second slot, unused since /private/var lives on its own volume),
 *                              read back; then the header into block 3145727 (where "loader" puts its flag):
 *                              "XNUFLASH", first block, bytes, FNV-1a 64 of the bytes. Reboot after this.
 *   flash_stage cancel         the header zeroed: the next start is an ordinary one
 *   flash_stage verify IMAGE   does `boot` (/dev/rufs_boot, read only) begin with IMAGE's bytes?
 *
 * Exit 0 on success. Built by hand like net_test: xnu-clang -arch arm64 -isysroot <iPhoneOS16.5.sdk> -O1.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <unistd.h>

#define BLOCK           4096
#define CHUNK           (4u << 20)              /* the loader's buffer: one request a write */
#define DARWIN          "/dev/rufs_darwin"
#define BOOT            "/dev/rufs_boot"
#define STAGE_BLOCK     2621440ULL              /* var_store's second slot */
#define HEAD_BLOCK      3145727ULL              /* the end of that slot: the loader's flag block */
#define MAX_BYTES       (0x04000000ULL - 0x100000ULL - 0x100000ULL)     /* what the loader can hold, with room */

struct head {
	char magic[8];                  /* "XNUFLASH" */
	uint64_t first_block;
	uint64_t bytes;
	uint64_t fnv;
};

/* darwin takes writes only from the holder of kern.hakios.var_busy (hakios.ufs.c): one writer at a time */
static int
claim(int on)
{
	int v = on;

	if (sysctlbyname("kern.hakios.var_busy", NULL, NULL, &v, sizeof(v)) != 0) {
		printf("flash_stage: kern.hakios.var_busy=%d: %s\n", on, strerror(errno));
		return -1;
	}
	return 0;
}

static uint64_t
fnv(uint64_t h, const uint8_t *p, size_t n)
{
	for (size_t i = 0; i < n; i++) {
		h = (h ^ p[i]) * 0x100000001b3ULL;
	}
	return h;
}

static uint8_t *
load(const char *path, size_t *bytes, size_t *rounded)
{
	struct stat st;
	uint8_t *buf;
	int fd = open(path, O_RDONLY);

	if (fd < 0 || fstat(fd, &st) != 0) {
		printf("flash_stage: %s: %s\n", path, strerror(errno));
		return NULL;
	}
	*bytes = (size_t)st.st_size;
	*rounded = (*bytes + BLOCK - 1) / BLOCK * BLOCK;
	if (*bytes < BLOCK || *bytes > MAX_BYTES) {
		printf("flash_stage: %s: %zu bytes: not a size the loader takes\n", path, *bytes);
		return NULL;
	}
	buf = calloc(1, *rounded);
	if (buf == NULL || read(fd, buf, *bytes) != (ssize_t)*bytes) {
		printf("flash_stage: %s: could not read it whole\n", path);
		return NULL;
	}
	close(fd);
	if (memcmp(buf, "ANDROID!", 8) != 0) {
		printf("flash_stage: %s: not an Android boot image\n", path);
		return NULL;
	}
	return buf;
}

static int
put(int fd, const uint8_t *p, size_t n, off_t at)
{
	for (size_t done = 0; done < n;) {
		size_t k = n - done < CHUNK ? n - done : CHUNK;
		ssize_t w = pwrite(fd, p + done, k, at + (off_t)done);

		if (w != (ssize_t)k) {
			printf("flash_stage: write at byte %lld: %s\n", (long long)(at + (off_t)done), w < 0 ? strerror(errno) : "short");
			return -1;
		}
		done += k;
	}
	return 0;
}

static int
same(int fd, const uint8_t *p, size_t n, off_t at, const char *what)
{
	uint8_t *b = malloc(CHUNK);

	for (size_t done = 0; b != NULL && done < n;) {
		size_t k = n - done < CHUNK ? n - done : CHUNK;

		if (pread(fd, b, k, at + (off_t)done) != (ssize_t)k) {
			printf("flash_stage: %s: read at byte %lld: %s\n", what, (long long)(at + (off_t)done), strerror(errno));
			free(b);
			return -1;
		}
		if (memcmp(b, p + done, k) != 0) {
			printf("flash_stage: %s: DIFFERENT at byte %zu\n", what, done);
			free(b);
			return -1;
		}
		done += k;
	}
	free(b);
	return b == NULL ? -1 : 0;
}

static int
write_head(int fd, const struct head *h)
{
	uint8_t block[BLOCK];

	memset(block, 0, sizeof(block));
	if (h != NULL) {
		memcpy(block, h, sizeof(*h));
	}
	return put(fd, block, sizeof(block), (off_t)(HEAD_BLOCK * BLOCK)) == 0 && fsync(fd) == 0 &&
	    same(fd, block, sizeof(block), (off_t)(HEAD_BLOCK * BLOCK), "header") == 0 ? 0 : -1;
}

int
main(int argc, char **argv)
{
	const char *what = argc > 1 ? argv[1] : "";
	size_t bytes = 0, rounded = 0;
	uint8_t *img = NULL;
	int fd;

	if (strcmp(what, "cancel") == 0) {
		fd = open(DARWIN, O_RDWR);
		if (fd < 0 || claim(1) != 0 || write_head(fd, NULL) != 0) {
			printf("flash_stage: cancel: FAILED (%s)\n", strerror(errno));
			(void)claim(0);
			return 1;
		}
		(void)claim(0);
		printf("flash_stage: cancelled: the next start is an ordinary one\n");
		return 0;
	}
	if (argc != 3 || (strcmp(what, "stage") != 0 && strcmp(what, "verify") != 0)) {
		printf("usage: flash_stage stage IMAGE | cancel | verify IMAGE\n");
		return 2;
	}
	if ((img = load(argv[2], &bytes, &rounded)) == NULL) {
		return 1;
	}
	if (strcmp(what, "verify") == 0) {
		fd = open(BOOT, O_RDONLY);
		if (fd < 0) {
			printf("flash_stage: %s: %s\n", BOOT, strerror(errno));
			return 1;
		}
		if (same(fd, img, bytes, 0, "boot") != 0) {
			return 1;
		}
		printf("flash_stage: boot holds %s (%zu bytes, fnv %016llx)\n", argv[2], bytes,
		    (unsigned long long)fnv(0xcbf29ce484222325ULL, img, bytes));
		return 0;
	}

	struct head h;

	memcpy(h.magic, "XNUFLASH", 8);
	h.first_block = STAGE_BLOCK;
	h.bytes = bytes;
	h.fnv = fnv(0xcbf29ce484222325ULL, img, bytes);
	fd = open(DARWIN, O_RDWR);
	if (fd < 0) {
		printf("flash_stage: %s: %s\n", DARWIN, strerror(errno));
		return 1;
	}
	if (claim(1) != 0) {
		return 1;
	}
	/* the header off first: a stage that does not finish is never taken */
	if (write_head(fd, NULL) != 0 || put(fd, img, rounded, (off_t)(STAGE_BLOCK * BLOCK)) != 0 || fsync(fd) != 0 ||
	    same(fd, img, rounded, (off_t)(STAGE_BLOCK * BLOCK), "staged image") != 0 || write_head(fd, &h) != 0) {
		printf("flash_stage: stage: FAILED; nothing will be flashed\n");
		(void)write_head(fd, NULL);
		(void)claim(0);
		return 1;
	}
	(void)claim(0);
	printf("flash_stage: staged %s: %zu bytes at darwin block %llu, fnv %016llx; the loader writes boot at the next "
	    "start\n", argv[2], bytes, (unsigned long long)STAGE_BLOCK, (unsigned long long)h.fnv);
	return 0;
}
