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
update_vdev_labels(int fd, uint64_t size, char *new_path, char *new_phys,
    char *new_devid)
{
	vdev_label_t vl;
	nvlist_t *config;
	nvlist_t *vdt;
	vdev_phys_t *phys;
	zio_cksum_t ck;
	char *buf, *s;
	size_t buflen;
	int label;
	vdev_t *v;
	uint64_t ashift, txg;

	/*
	 * Read the first VDEV label from the disk...
	 * There is no support here for reading a different label if the
	 * first is corrupt. Since the pool should have been exported, it is
	 * expected that all labels are consistent.
	 *	typedef struct vdev_label {
	 *		char		vl_pad1[VDEV_PAD_SIZE];
	 *		char		vl_pad2[VDEV_PAD_SIZE];
	 *		vdev_phys_t	vl_vdev_phys;
	 *		char		vl_uberblock[VDEV_UBERBLOCK_RING];
	 *	} vdev_label_t;
	 */
	assert(pread64(fd, &vl, sizeof(vdev_label_t), 0)
	    == sizeof(vdev_label_t));
	printf("Loaded label from disk, %ld\n", sizeof(vdev_label_t));

	/*
	 * typedef struct vdev_phys {
	 *	char		vp_nvlist[VDEV_PHYS_SIZE - sizeof (zio_eck_t)];
	 *	zio_eck_t	vp_zbt;
	 *	} vdev_phys_t;
	 */
	phys = &vl.vl_vdev_phys;

	/* Unpack the nvlist */
	assert(!nvlist_unpack(phys->vp_nvlist, sizeof(phys->vp_nvlist),
	    &config, 0));
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
	assert(!nvlist_lookup_nvlist(config, ZPOOL_CONFIG_VDEV_TREE, &vdt));

	/* Report the current values */
	if (!nvlist_lookup_string(vdt, ZPOOL_CONFIG_PATH, &s))
		printf("                 Path: '%s'\n", s);
	if (!nvlist_lookup_string(vdt, ZPOOL_CONFIG_PHYS_PATH, &s))
		printf("        Physical path: '%s'\n", s);
	if (!nvlist_lookup_string(vdt, ZPOOL_CONFIG_DEVID, &s))
		printf("                Devid: '%s'\n", s);

	/* Update the values */
	assert(!nvlist_remove_all(vdt, ZPOOL_CONFIG_PHYS_PATH));
	assert(!nvlist_add_string(vdt, ZPOOL_CONFIG_PHYS_PATH, new_phys));

	assert(!nvlist_remove_all(vdt, ZPOOL_CONFIG_PATH));
	assert(!nvlist_add_string(vdt, ZPOOL_CONFIG_PATH, new_path));

	/* devid may not exist */
	nvlist_remove_all(vdt, ZPOOL_CONFIG_DEVID);
	/* and we may not want a new one */
	if (strlen(new_devid))
		assert(!nvlist_add_string(vdt, ZPOOL_CONFIG_DEVID, new_devid));

	/* Mark the pool as active */
	assert(!nvlist_remove_all(config, ZPOOL_CONFIG_POOL_STATE));
	assert(!nvlist_add_uint64(config, ZPOOL_CONFIG_POOL_STATE,
	    POOL_STATE_ACTIVE));

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
	assert(!nvlist_pack(config, &buf, &buflen, NV_ENCODE_XDR, 0));
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
		printf("Wrote label %d (@%p) to disk\n", label, (void *)offset);
	}

	/* Create a vdev structure representing this vdev */

	assert((v = calloc(1, sizeof(vdev_t))) != NULL);
	v->v_state = VDEV_STATE_HEALTHY;
	assert(!nvlist_lookup_string(config, ZPOOL_CONFIG_POOL_NAME,
	    (char **)&v->v_name));
	assert(!nvlist_lookup_uint64(config, ZPOOL_CONFIG_GUID, &v->v_guid));
	assert(!nvlist_lookup_uint64(vdt, ZPOOL_CONFIG_ASHIFT, &ashift));
	v->v_ashift = ashift;
	v->v_top = v;

	assert(!nvlist_lookup_uint64(config, ZPOOL_CONFIG_POOL_TXG, &txg));
	printf("Pool transaction group: %ld\n", txg);

	/*
	 * typedef struct uberblock {
	 *	uint64_t        ub_magic;
	 *	uint64_t        ub_version;
	 *	uint64_t        ub_txg;
	 *	uint64_t        ub_guid_sum;
	 *	uint64_t        ub_timestamp;
	 *	blkptr_t        ub_rootbp;
	 * } uberblock_t;
	 */

	uberblock_t *ub = NULL;

	for (int i = 0; i < VDEV_UBERBLOCK_COUNT(v); i++)
	{
		uint64_t uoff = VDEV_UBERBLOCK_OFFSET(v, i);
		uberblock_t *_ub = (void *)((char *)&vl + uoff);

		if (verbose)
			printf("[%2d] %#010lx %5ld %ld\n", i,
			    _ub->ub_magic, _ub->ub_txg, _ub->ub_timestamp);

		if (_ub->ub_magic != UBERBLOCK_MAGIC)
			continue;
		if (_ub->ub_txg < txg)
			continue;

		if (!ub || _ub->ub_txg > ub->ub_txg ||
		    (_ub->ub_txg == ub->ub_txg &&
		    _ub->ub_timestamp > ub->ub_timestamp))
			ub = _ub;
	}
	if (verbose)
		printf("Best uberblock: %ld %ld\n",
		    ub->ub_txg, ub->ub_timestamp);
}

int
main(int argc, char **argv)
{
	struct stat64 st;
	uint64_t size;
	char *path, *phys, *devid;
	int fd;

	if (argc >= 2 && !strcmp(argv[1], "-v"))
		verbose++, argc--, argv++;

	if (argc == 5)
	{
		path = argv[2];
		phys = argv[3];
		devid = argv[4];
	}
	else if (argc == 2)
	{
		path = XEN_PATH;
		phys = XEN_PHYS;
		devid = XEN_DEVID;
	}
	else
	{
		fprintf(stderr,
		    "Syntax: %s [-v] <path to vdev> [<path> <phys> <devid>]\n",
		    argv[0]);
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

	update_vdev_labels(fd, size, path, phys, devid);

	fsync(fd);
	close(fd);

	return 0;
}

// vim:fdm=marker
