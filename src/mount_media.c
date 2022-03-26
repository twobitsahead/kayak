/*
 * CDDL HEADER START
 *
 * The contents of this file are subject to the terms of the
 * Common Development and Distribution License (the "License").
 * You may not use this file except in compliance with the License.
 *
 * You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
 * or http://www.opensolaris.org/os/licensing.
 * See the License for the specific language governing permissions
 * and limitations under the License.
 *
 * When distributing Covered Code, include this CDDL HEADER in each
 * file and include the License file at usr/src/OPENSOLARIS.LICENSE.
 * If applicable, add the following below this CDDL HEADER, with the
 * fields enclosed by brackets "[]" replaced with your own identifying
 * information: Portions Copyright [yyyy] [name of copyright owner]
 *
 * CDDL HEADER END
 */

/*
 * Copyright (c) 2008, 2011, Oracle and/or its affiliates. All rights reserved.
 */

/*
 * The install boot_archive contains a minimal set of utilities under /usr and
 * devfs is not populated.  The SMF service live-fs-root bootstraps the process
 * by locating the media device and mounting the compressed /usr and /opt
 * to provide a fully functioning system.  This utility traverses the device
 * tree looking for devices that potentially contain the media image, mounts
 * each in turn and checks whether it contains the volume set id passed on
 * the comamnd line.  An exit of 0 means we succeeded, non-zero means we failed.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <libdevinfo.h>
#include <limits.h>
#include <fts.h>
#include <sys/sunddi.h>
#include <sys/types.h>
#include <sys/dkio.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <stdbool.h>

#define	HSFS_OPTS	"ro"
#define	UFS_OPTS	"ro,nologging,noatime"
#define	PCFS_OPTS	"ro"

static bool mounted = false;
static bool verbose = false;

static int
check_volsetid(const char *volid)
{
	FILE *fp;
	char buf[BUFSIZ], *cp;
	int ret = -1;

	/* Check volume set id against requested */
	if ((fp = fopen("/.cdrom/.volsetid", "r")) != NULL) {
		if (fgets(buf, BUFSIZ, fp) != NULL) {
			/* Strip newline if present */
			if ((cp = strchr(buf, '\n')) != NULL)
				*cp = '\0';
			if (verbose)
				printf("        [%s]\n", buf);
			ret = strcmp(volid, buf);
		}
		(void) fclose(fp);
	} else if (verbose) {
		printf("/.cdrom/.volsetid: %s\n", strerror(errno));
	}
	return (ret);
}

/*
 * Mounts and tests supplied path to iso file for supplied volid
 * Returns 0 if volid found, -1 otherwise.
 */
static int
test_iso_file(const char *path, const char *volid)
{
	int ret = -1;
	char opts[MAX_MNTOPT_STR];

	strcpy(opts, HSFS_OPTS);
	if (verbose)
		printf("%s: mount hsfs (iso)\n", path);
	if (mount(path, "/.cdrom", MS_RDONLY | MS_OPTIONSTR,
	    "hsfs", NULL, 0, opts, sizeof (opts)) != 0) {
		return (ret); /* mount failed */
	}

	/* Mounted, see if it's the image we're looking for, unmount if not */
	ret = check_volsetid(volid);
	if (ret != 0) {
		if (verbose)
			printf("%s: wrong ID, unmounting\n", path);
		(void) umount("/.cdrom");
	}
	return (ret);
}

/*
 * Attempt to mount the path as pcfs. Then walk the file tree
 * and look for any iso files.
 * For every one found, mount it and check for volid
 * and umount if failed. return's 0 if the right iso is found
 * and -1 otherwise.
 */
static int
check_for_iso(const char *path, const char *volid)
{
	int ret = -1;
	char opts[MAX_MNTOPT_STR];

	strcpy(opts, PCFS_OPTS);

	if (verbose)
		printf("%s: mount PCFS\n", path);

	if (mount(path, "/.usbdrive", MS_RDONLY | MS_OPTIONSTR,
	    "pcfs", NULL, 0, opts, sizeof (opts)) != 0) {
		return (ret); /* mount failed */
	} else {
		/* mount succeeded, look for iso files */
		FTS *tree;
		FTSENT *f;
		char *pathtowalk[] = { "/.usbdrive", NULL };

		tree = fts_open(pathtowalk, FTS_LOGICAL | FTS_NOSTAT, NULL);
		if (tree == 0) {
			if (verbose)
				printf("%s: fts_open failed\n", path);
			return (ret); /* traverse failed */
		}

		while ((f = fts_read(tree)) != 0) {
			if (f->fts_info != FTS_F) /* regular file */
				continue;

			if (f->fts_namelen > 4 &&
			    (strcasecmp(".iso",
			    f->fts_name + f->fts_namelen - 4) == 0)) {
				if (verbose)
					printf("iso found: %s\n", f->fts_name);

				ret = test_iso_file(f->fts_path, volid);
				if (ret == 0)
					break; /* correct iso found */
			}
		}

		if (fts_close(tree) < 0) {
			if (verbose)
				printf("error closing tree\n");
		}

		if (ret != 0) {
			if (verbose)
				printf("%s: wrong volume, unmounting\n", path);
			(void) umount("/.usbdrive");
			/* if ret==0 we do not unmount the usbdrive mount */
		}
	}

	return (ret);
}

static int
mount_image(const char *path, const char *volid)
{
	int ret = -1;
	char opts[MAX_MNTOPT_STR];

	/*
	 * First try mounting it as hsfs; if that fails, try ufs; if
	 * that fails try check_for_iso()
	 */
	strcpy(opts, HSFS_OPTS);

	if (verbose)
		printf("%s: mount HSFS\n", path);

	if (mount(path, "/.cdrom", MS_RDONLY | MS_OPTIONSTR, "hsfs",
	    NULL, 0, opts, sizeof (opts)) != 0) {
		strcpy(opts, UFS_OPTS);
		if (verbose)
			printf("%s: mount UFS\n", path);
		if (mount(path, "/.cdrom", MS_OPTIONSTR, "ufs", NULL, 0,
		    opts, sizeof (opts)) != 0) {
			if (check_for_iso(path, volid) != 0)
				return (ret);
		}
	}

	if (verbose)
		printf("Mounted %s\n", path);

	/* Mounted, see if it's the image we're looking for, unmount if not */
	ret = check_volsetid(volid);
	if (ret != 0) {
		if (verbose)
			printf("%s: wrong ID, unmounting\n", path);
		(void) umount("/.cdrom");
	}
	return (ret);
}

/*
 * Callback function for di_walk_minor.  For each node that appears to match
 * our criteria (a USB block device, or a CD), mount it and see if it
 * matches the volume set id passed on the command line.  If so, we're done
 * and can terminate the walk.  In all error cases, just continue walking the
 * tree.
 */
static int
mount_minor(di_node_t node, di_minor_t minor, void *arg)
{
	int fd, ret, **prop;
	struct dk_cinfo dkinfo;
	char *nt, *mnp, *cp, *volid = (char *)arg;
	char mpath[PATH_MAX];

	nt = di_minor_nodetype(minor);
	if (nt == NULL)
		return (DI_WALK_CONTINUE);

	mnp = di_devfs_minor_path(minor);
	if (mnp == NULL)
		return (DI_WALK_CONTINUE);

	strcpy(mpath, "/devices");
	strlcat(mpath, mnp, PATH_MAX);

	if (verbose) {
		printf("Checking %s (%s)[%d]\n", mnp, nt,
		    di_minor_spectype(minor));
	}

	/* If it's a block device and claims to be USB, try mounting it */
	if ((di_minor_spectype(minor) == S_IFBLK) &&
	    (di_prop_lookup_ints(DDI_DEV_T_ANY, node, "usb", prop) != -1)) {
		goto mount;
	}

	/* Node type is a CD.  Try mounting it */
	if (strstr(nt, DDI_NT_CD) != NULL ||
	    strstr(nt, DDI_NT_CD_CHAN) != NULL) {
		goto mount;
	}

	/*
	 * If node type is not marked, Xvm devices for instance
	 * need to check device type via ioctls
	 */
	if ((fd = open(mpath, O_NDELAY | O_RDONLY)) == -1)
		goto end;
	ret = ioctl(fd, DKIOCINFO, &dkinfo);
	(void) close(fd);
	if (ret != 0 || dkinfo.dki_ctype != DKC_CDROM)
		goto end;

mount:
	/* Remove raw suffix from path to get to block device for mount */
	if ((cp = strstr(mpath, ",raw")) != NULL)
		*cp = '\0';
	if (mount_image(mpath, volid) == 0) {
		printf("Found %s media at %s\n", volid, mpath);
		mounted = true;
	}

end:
	di_devfs_path_free(mnp);
	return (mounted ? DI_WALK_TERMINATE : DI_WALK_CONTINUE);
}

int
main(int argc, char **argv)
{
	di_node_t root_node;

	if (argc > 1 && strcmp(argv[1], "-v") == 0) {
		verbose = true;
		argc--, argv++;
	}

	if (argc == 1) {
		fprintf(stderr, "Usage: mount_media [-v] <volsetid>\n");
		return (1);
	}

	/* Initialize libdevinfo and walk the tree */
	if ((root_node = di_init("/", DINFOCPYALL)) == DI_NODE_NIL)
		return (1);
	(void) di_walk_minor(root_node, DDI_NT_BLOCK, 0, argv[1], mount_minor);
	di_fini(root_node);

	return (mounted ? 0 : 1);
}
