/*
 * A file of one of this port's RAM disks, by path, for the drivers that want one before there is
 * a root or without asking it: the GPU's firmware (hakios.adreno.c), the Wi-Fi DSP's
 * (hakios.wifi.c), the audio DSP's (hakios.adsp.c) -- "fw/NAME" of the image that travels with
 * the kernel (md1; md0 when there is nothing else) or of the resident one (md0).
 *
 * The image is an APFS container (tools/apfs/mkapfs.py: what userland/build.sh makes).  A file
 * stored as it is in one piece is used where it lies in the RAM disk's memory, as the drivers
 * always did (build.sh has mkapfs.py store fw/ that way: --plain fw).
 * Any other APFS file is read out once by apfs_lib -- the same code as the volume's when
 * mounted, compressed or not -- into memory of its own, and kept: firmware is asked for once
 * or twice a session and its driver keeps it while the phone runs, so nothing gives it back.
 *
 * Firmware too big for the small images (the boot partition's payload is at most 64 MB: the modem's 77 MB
 * of modem.mdt/modem.bNN, wlanmdsp.mbn, the modem's MCFG tree) is looked for last in
 * /private/var/hakios/fw/NAME of the running root -- with the iOS volume as the root, /private/var is HFS
 * Plus on the flash (init: var_hfs=1), filled once over the USB shell (sweet-sh.py --put) -- read whole
 * into memory of its own and kept like the APFS copies. Before the root and /private/var are there, it is
 * simply not found (a driver that needs it waits: vayu_modem.c, vayu_modem_fw_wait).
 */
#include <kern/kalloc.h>
#include <kern/locks.h>
#include <libkern/libkern.h>
#include <sys/errno.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <sys/systm.h>
#include <sys/vnode.h>
#include <sys/vnode_internal.h>
#include <miscfs/apfs/apfs_lib.h>

extern dev_t mdevlookup(int devid);
extern int mdevgetkernelrange(dev_t dev, vm_offset_t *base, uint64_t *size);

const uint8_t *hakios_image_file(const char *dir, const char *name, uint64_t *size, int *disk_out);

/* ---- APFS ---- */

struct mem_dev {
	const uint8_t *base;
	uint64_t       length;
};

static int
mem_read(void *ctx, uint64_t off, void *buf, size_t len)
{
	struct mem_dev *m = ctx;

	if (off > m->length || len > m->length - off) {
		return EIO;
	}
	memcpy(buf, m->base + off, len);
	return 0;
}

static LCK_GRP_DECLARE(image_lck_grp, "hakios_image");
static LCK_MTX_DECLARE(image_lock, &image_lck_grp);    /* kept[]: the drivers start beside each other */
static struct {
	int       disk;
	char      path[96];
	uint8_t  *data;
	uint64_t  size;
} kept[128];

static const uint8_t *
apfs_file(int disk, const uint8_t *base, uint64_t length, const char *dir, const char *name, uint64_t *size)
{
	struct mem_dev m = { .base = base, .length = length };
	struct apfs_dev dev = { .ctx = &m, .size = length, .read = mem_read, .read_data = mem_read };
	struct apfs_nx *nx = NULL;
	struct apfs_vol *vol = NULL;
	struct apfs_inode ino;
	struct apfs_cfile cf;
	char path[96];
	uint64_t id = 0, fsize = 0, off = 0;
	uint8_t dt = 0, *data = NULL;
	uint32_t i;
	int error;

	if (length < 4096 || memcmp(base + 32, "NXSB", 4) != 0) {
		return NULL;
	}
	snprintf(path, sizeof(path), "/%s/%s", dir, name);
	lck_mtx_lock(&image_lock);
	for (i = 0; i < sizeof(kept) / sizeof(kept[0]) && kept[i].data != NULL; i++) {
		if (kept[i].disk == disk && strcmp(kept[i].path, path) == 0) {
			*size = kept[i].size;
			lck_mtx_unlock(&image_lock);
			return kept[i].data;
		}
	}
	nx = kalloc_type(struct apfs_nx, Z_WAITOK | Z_ZERO);
	vol = kalloc_type(struct apfs_vol, Z_WAITOK | Z_ZERO);
	if (nx == NULL || vol == NULL) {
		goto out;
	}
	if (apfs_nx_open(nx, &dev) != 0) {
		kfree_type(struct apfs_nx, nx);
		nx = NULL;
		goto out;
	}
	error = ENOENT;
	for (uint32_t v = 0; v < APFS_NX_MAX_FILE_SYSTEMS && error != 0; v++) {
		if (nx->fs_oid[v] != 0 && apfs_vol_open(nx, v, vol) == 0) {
			error = apfs_path_lookup(vol, path, &id, &dt);
		}
	}
	if (error == 0) {
		error = apfs_inode_get(vol, id, &ino);
	}
	if (error == 0 && (ino.mode & APFS_S_IFMT) != APFS_S_IFREG) {
		error = EISDIR;
	}
	if (error == 0) {
		error = apfs_inode_size(vol, &ino, &fsize);
	}
	if (error == 0 && (fsize == 0 || fsize > 256 * 1024 * 1024)) {
		error = EFBIG;
	}
	if (error == 0) {
		uint64_t addr = 0;

		/* in one piece as it is: where it lies, no copy */
		if (apfs_file_in_place(vol, &ino, &addr) == 0 && addr <= length / nx->block_size &&
		    fsize <= length - addr * nx->block_size) {
			apfs_nx_close(nx);
			*size = fsize;
			data = __DECONST(uint8_t *, base) + addr * nx->block_size;
			goto out;
		}
		if (i == sizeof(kept) / sizeof(kept[0])) {
			printf("hakios_image: %s of /dev/md%d: kept %lu files already, no room for a copy of another\n", path, disk,
			    (unsigned long)i);
			error = ENOSPC;
		}
	}
	if (error == 0) {
		data = kalloc_data((vm_size_t)fsize, Z_WAITOK);
		error = data == NULL ? ENOMEM : 0;
	}
	memset(&cf, 0, sizeof(cf));
	cf.held = APFS_NO_PIECE;
	while (error == 0 && off < fsize) {
		size_t got = 0;

		error = apfs_read_file(vol, &ino, &cf, off, data + off, (size_t)(fsize - off), &got);
		if (error == 0 && got == 0) {
			error = EIO;
		}
		off += got;
	}
	apfs_cfile_fini(&cf);
	apfs_nx_close(nx);
	if (error == 0) {
		kept[i].disk = disk;
		strlcpy(kept[i].path, path, sizeof(kept[i].path));
		kept[i].size = fsize;
		kept[i].data = data;            /* (last: a reader of the table sees all of it or none) */
		*size = fsize;
	} else if (data != NULL) {
		kfree_data(data, (vm_size_t)fsize);
		data = NULL;
	}
out:
	lck_mtx_unlock(&image_lock);
	if (vol != NULL) {
		kfree_type(struct apfs_vol, vol);
	}
	if (nx != NULL) {
		kfree_type(struct apfs_nx, nx);
	}
	return data;
}

#define VAR_DISK        (-1)            /* kept[].disk of a file read from /private/var/hakios/<dir>/ */

/* /private/var/hakios/<dir>/<name> of the running root, whole, kept (see the top of this file). */
static const uint8_t *
var_file(const char *dir, const char *name, uint64_t *size)
{
	char key[96], path[160];
	vfs_context_t context = vfs_context_kernel();
	vnode_t vnode = NULLVP;
	struct vnode_attr attributes;
	uint8_t *data;
	uint32_t i;
	int left = 0, error;

	if (rootvnode == NULLVP) {
		return NULL;                    /* no root yet */
	}
	for (const char *c = name; *c != 0; c++) {
		if (*c == '.' && (c == name || c[-1] == '/')) {
			return NULL;            /* no "..", no hidden names */
		}
	}
	snprintf(key, sizeof(key), "/%s/%s", dir, name);
	if (snprintf(path, sizeof(path), "/private/var/hakios/%s/%s", dir, name) >= (int)sizeof(path)) {
		return NULL;
	}
	lck_mtx_lock(&image_lock);
	for (i = 0; i < sizeof(kept) / sizeof(kept[0]) && kept[i].data != NULL; i++) {
		if (kept[i].disk == VAR_DISK && strcmp(kept[i].path, key) == 0) {
			*size = kept[i].size;
			lck_mtx_unlock(&image_lock);
			return kept[i].data;
		}
	}
	lck_mtx_unlock(&image_lock);
	if (vnode_lookup(path, 0, &vnode, context) != 0) {
		return NULL;
	}
	VATTR_INIT(&attributes);
	VATTR_WANTED(&attributes, va_data_size);
	if (vnode_vtype(vnode) != VREG || vnode_getattr(vnode, &attributes, context) != 0 ||
	    attributes.va_data_size == 0 || attributes.va_data_size > 256 * 1024 * 1024) {
		vnode_put(vnode);
		return NULL;
	}
	data = kalloc_data((vm_size_t)attributes.va_data_size, Z_WAITOK);
	if (data == NULL) {
		vnode_put(vnode);
		return NULL;
	}
	error = vn_rdwr(UIO_READ, vnode, (caddr_t)data, (int)attributes.va_data_size, 0, UIO_SYSSPACE, 0,
	    vfs_context_ucred(context), &left, vfs_context_proc(context));
	vnode_put(vnode);
	if (error != 0 || left != 0) {
		printf("hakios_image: %s: read error %d, %d bytes left\n", path, error, left);
		kfree_data(data, (vm_size_t)attributes.va_data_size);
		return NULL;
	}
	lck_mtx_lock(&image_lock);
	for (i = 0; i < sizeof(kept) / sizeof(kept[0]) && kept[i].data != NULL; i++) {
		if (kept[i].disk == VAR_DISK && strcmp(kept[i].path, key) == 0) {
			break;                  /* read by another driver meanwhile: keep the first */
		}
	}
	if (i == sizeof(kept) / sizeof(kept[0])) {
		lck_mtx_unlock(&image_lock);
		printf("hakios_image: %s: kept %lu files already, no room for another\n", path, (unsigned long)i);
		kfree_data(data, (vm_size_t)attributes.va_data_size);
		return NULL;
	}
	if (kept[i].data != NULL) {
		*size = kept[i].size;
		lck_mtx_unlock(&image_lock);
		kfree_data(data, (vm_size_t)attributes.va_data_size);
		return kept[i].data;
	}
	kept[i].disk = VAR_DISK;
	strlcpy(kept[i].path, key, sizeof(kept[i].path));
	kept[i].size = attributes.va_data_size;
	kept[i].data = data;
	*size = attributes.va_data_size;
	lck_mtx_unlock(&image_lock);
	return data;
}

const uint8_t *
hakios_image_file(const char *dir, const char *name, uint64_t *size, int *disk_out)
{
	for (int disk = 1; disk >= 0; disk--) {
		vm_offset_t base = 0;
		uint64_t length = 0;
		const uint8_t *data;
		dev_t dev = mdevlookup(disk);

		if (dev == (dev_t)-1 || mdevgetkernelrange(dev, &base, &length) != 0) {
			continue;
		}
		data = apfs_file(disk, (const uint8_t *)base, length, dir, name, size);
		if (data != NULL) {
			if (disk_out != NULL) {
				*disk_out = disk;
			}
			return data;
		}
	}
	{
		const uint8_t *data = var_file(dir, name, size);

		if (data != NULL && disk_out != NULL) {
			*disk_out = VAR_DISK;
		}
		return data;
	}
}
