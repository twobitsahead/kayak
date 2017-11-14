/*
 *
 * Based on a program written by Jeff Bonwick
 * http://www.mail-archive.com/zfs-discuss@opensolaris.org/msg15748.html/
 *
 * Modified to update the 'path' and 'phys_path' attributes in a disk
 * vdev label.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <assert.h>

#include <libnvpair.h>
#include <sys/queue.h>
#include <zfsimpl.h>

#include <sha256.c>

#define XEN_PHYS "/xpvd/xdf@51712:a"
#define XEN_PATH "/dev/dsk/c2t0d0s0"

static void
label_write(int fd, uint64_t offset, uint64_t size, void *buf)
{
	zio_eck_t *zbt, zbt_orig;
	zio_cksum_t zc;

	zbt = (zio_eck_t *)((char *)buf + size) - 1;
	zbt_orig = *zbt;

	ZIO_SET_CHECKSUM(&zbt->zec_cksum, offset, 0, 0, 0);

	//zio_checksum(ZIO_CHECKSUM_LABEL, &zc, buf, size);
	zio_checksum_SHA256(buf, size, NULL, &zc);
	zbt->zec_cksum = zc;

	assert(pwrite64(fd, buf, size, offset) == size);

	*zbt = zbt_orig;
}

int
main(int argc, char **argv)
{
	int fd;
	vdev_label_t vl;
	nvlist_t *config, *vdt;
	char *buf, *s;
	size_t buflen;

	if (argc != 2)
	{
		fprintf(stderr, "Syntax: %s <path to vdev>\n", argv[0]);
		return -1;
	}

	fd = open(argv[1], O_RDWR);
	assert(fd > 0);

	assert(pread64(fd, &vl, sizeof(vdev_label_t), 0)
	    == sizeof(vdev_label_t));
	assert(nvlist_unpack(vl.vl_vdev_phys.vp_nvlist,
	    sizeof(vl.vl_vdev_phys.vp_nvlist), &config, 0) == 0);

	/*
		version: 5000
		name: 'syspool'
		vdev_children: 1
		vdev_tree:
		    type: 'disk'
		    id: 0
		    guid: 14081435818166446876
		    path: '/dev/dsk/c2t0d0s0'
		    phys_path: '/xpvd/xdf@51712:a'
	*/
	//dump_nvlist(config, 8);

	// VDEV tree
	assert(nvlist_lookup_nvlist(config, ZPOOL_CONFIG_VDEV_TREE, &vdt)
	    == 0);

	assert(nvlist_lookup_string(vdt, ZPOOL_CONFIG_PATH, &s) == 0);
	printf("             Path: '%s'\n", s);
	assert(nvlist_lookup_string(vdt, ZPOOL_CONFIG_PHYS_PATH, &s) == 0);
	printf("    Physical path: '%s'\n", s);

	assert(nvlist_remove_all(vdt, ZPOOL_CONFIG_PHYS_PATH) == 0);
	assert(nvlist_add_string(vdt, ZPOOL_CONFIG_PHYS_PATH, XEN_PHYS) == 0);
	assert(nvlist_remove_all(vdt, ZPOOL_CONFIG_PATH) == 0);
	assert(nvlist_add_string(vdt, ZPOOL_CONFIG_PATH, XEN_PATH) == 0);

	assert(nvlist_lookup_string(vdt, ZPOOL_CONFIG_PATH, &s) == 0);
	printf("         New path: '%s'\n", s);
	assert(nvlist_lookup_string(vdt, ZPOOL_CONFIG_PHYS_PATH, &s) == 0);
	printf("New physical path: '%s'\n", s);

	printf("\n");
	dump_nvlist(config, 8);

	buf = vl.vl_vdev_phys.vp_nvlist;
	buflen = sizeof (vl.vl_vdev_phys.vp_nvlist);
	assert(nvlist_pack(config, &buf, &buflen, NV_ENCODE_XDR, 0) == 0);

	label_write(fd, offsetof(vdev_label_t, vl_vdev_phys),
	   VDEV_PHYS_SIZE, &vl.vl_vdev_phys);

	fsync(fd);

	return 0;
}

