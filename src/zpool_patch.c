/*
 * {{{ CDDL HEADER
 *
 * This file and its contents are supplied under the terms of the
 * Common Development and Distribution License ("CDDL"), version 1.0.
 * You may only use this file in accordance with the terms of version
 * 1.0 of the CDDL.
 *
 * A full copy of the text of the CDDL should have accompanied this
 * source. A copy of the CDDL is also available via the Internet at
 * http://www.illumos.org/license/CDDL.
 *
 * }}}
 */

/* Copyright 2018 OmniOS Community Edition (OmniOSce) Association. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <ctype.h>
#include <assert.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <inttypes.h>

#include <libnvpair.h>
#include <sys/queue.h>
#include <sys/sysmacros.h>

#include <zfsimpl.h>
#include <sha256.c>

#define XEN_PHYS "/xpvd/xdf@51712:a"
#define XEN_PATH "/dev/dsk/c1t0d0s0"
#define XEN_DEVID "id1,kdev@AQM00001~~~~~~~~~~~~~/a"

int verbose = 0;

uint64_t
label_offset(uint64_t size, int label)
{
	return label * sizeof(vdev_label_t) +
	    (label < VDEV_LABELS / 2 ? 0 :
	    size - VDEV_LABELS * sizeof(vdev_label_t));
}

void
update_vdev_labels(int fd, uint64_t size)
{
	vdev_label_t vl;
	nvlist_t *config;
	nvlist_t *vdt;
	vdev_phys_t *phys;
	zio_cksum_t ck;
	char *buf, *s;
	size_t buflen;
	int label, i;
	uint64_t ashift, txg, offset;

	/*
	 * Read the first VDEV label from the disk...
	 * There is no support here for reading a different label if the
	 * first is corrupt.
	 *	typedef struct vdev_label {
	 *	char		vl_pad1[VDEV_PAD_SIZE];
	 *	char		vl_pad2[VDEV_PAD_SIZE];
	 *	vdev_phys_t	vl_vdev_phys;
	 *	char		vl_uberblock[VDEV_UBERBLOCK_RING];
	 *	} vdev_label_t;
	 */
	assert(pread64(fd, &vl, sizeof(vdev_label_t), 0)
	    == sizeof(vdev_label_t));
	printf("Loaded label from disk\n");

	/*
	 * typedef struct vdev_phys {
	 *	char		vp_nvlist[VDEV_PHYS_SIZE - sizeof (zio_eck_t)];
	 *	zio_eck_t	vp_zbt;
	 *	} vdev_phys_t;
	 */
	phys = &vl.vl_vdev_phys;

	/* Unpack the nvlist */
	assert(nvlist_unpack(phys->vp_nvlist, sizeof(phys->vp_nvlist),
	    &config, 0) == 0);
	printf("Unpacked nvlist\n");

	/*
	 * The nvlist is a set of name/value pairs. Some of the values are
	 * nvlists themselves. Here's the start of the output from
	 * dump_nvlist(config, 8)
	 *
	 *	version: 5000
	 *	name: 'syspool'
	 *	vdev_children: 1
	 *	vdev_tree:
	 *	    type: 'disk'
	 *	    id: 0
	 *	    guid: 14081435818166446876
	 *	    path: '/dev/dsk/c2t0d0s0'
	 *	    phys_path: '/xpvd/xdf@51712:a'
	 */

	/* Get the 'vdev_tree' value which is itself an nvlist */
	assert(nvlist_lookup_nvlist(config, ZPOOL_CONFIG_VDEV_TREE,
	    &vdt) == 0);

	/* Report the current values */
	assert(nvlist_lookup_string(vdt, ZPOOL_CONFIG_PATH, &s) == 0);
	printf("                 Path: '%s'\n", s);
	assert(nvlist_lookup_string(vdt, ZPOOL_CONFIG_PHYS_PATH, &s) == 0);
	printf("        Physical path: '%s'\n", s);
	assert(nvlist_lookup_string(vdt, ZPOOL_CONFIG_DEVID, &s) == 0);
	printf("                Devid: '%s'\n", s);

	/* Update the values */
	assert(nvlist_remove_all(vdt, ZPOOL_CONFIG_PHYS_PATH) == 0);
	assert(nvlist_remove_all(vdt, ZPOOL_CONFIG_PATH) == 0);
	assert(nvlist_remove_all(vdt, ZPOOL_CONFIG_DEVID) == 0);

	assert(nvlist_add_string(vdt, ZPOOL_CONFIG_PHYS_PATH, XEN_PHYS) == 0);
	assert(nvlist_add_string(vdt, ZPOOL_CONFIG_PATH, XEN_PATH) == 0);
	assert(nvlist_add_string(vdt, ZPOOL_CONFIG_DEVID, XEN_DEVID) == 0);

	/* Output the new pool configuration */
	printf("Updated paths\n");
	if (verbose)
	{
		printf("\n");
		dump_nvlist(config, 16);
		printf("\n");
	}

	/* Pack the nvlist... */
	buf = phys->vp_nvlist;
	buflen = sizeof(phys->vp_nvlist);
	assert(nvlist_pack(config, &buf, &buflen, NV_ENCODE_XDR, 0) == 0);
	printf("Packed nvlist\n");

	/* ...and write the updated vdev_phys_t to the disk */

	for (label = 0; label < VDEV_LABELS; label++)
	{
		off_t offset;

		offset = label_offset(size, label) +
                    offsetof(vdev_label_t, vl_vdev_phys);

		/* ...fix the checksum - the offset on disk is used
		 * as the external verifier  */
		ZIO_SET_CHECKSUM(&phys->vp_zbt.zec_cksum, offset, 0, 0, 0);
		zio_checksum_SHA256(phys, VDEV_PHYS_SIZE, NULL, &ck);
		phys->vp_zbt.zec_cksum = ck;

		assert(pwrite64(fd, phys, VDEV_PHYS_SIZE, offset)
		    == VDEV_PHYS_SIZE);
		printf("Wrote label %d (@%p) to disk\n", label, offset);
	}
}

int
main(int argc, char **argv)
{
	struct stat64 st;
	vdev_label_t vl;
	nvlist_t *config;
	uint64_t size;
	int fd;

	if (argc >= 2 && !strcmp(argv[1], "-v"))
		verbose++, argc--, argv++;

	if (argc != 2)
	{
		fprintf(stderr, "Syntax: %s [-v] <path to vdev>\n", argv[0]);
		return -1;
	}

	if ((fd = open(argv[1], O_RDWR)) == -1)
	{
		perror("open");
		return 1;
	}

	if (fstat64(fd, &st) == -1)
	{
		perror("fstat");
		return 0;
	}
	size = P2ALIGN_TYPED(st.st_size, sizeof(vdev_label_t), uint64_t);

	update_vdev_labels(fd, size);

	fsync(fd);
	close(fd);

	return 0;
}

// vim:fdm=marker
