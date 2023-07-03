/*
 * This file and its contents are supplied under the terms of the
 * Common Development and Distribution License ("CDDL"), version 1.0.
 * You may only use this file in accordance with the terms of version
 * 1.0 of the CDDL.
 *
 * A full copy of the text of the CDDL should have accompanied this
 * source. A copy of the CDDL is also available via the Internet at
 * http://www.illumos.org/license/CDDL.
 */

/*
 * Copyright 2023 OmniOS Community Edition (OmniOSce) Association.
 */

#include <err.h>
#include <fcntl.h>
#include <libnvpair.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>

#define	FILE_STAT	"boot/solaris/filestat.ramdisk"

static void
read_stat(const char *root)
{
	char path[PATH_MAX];
	nvlist_t *nvlp;
	struct stat st;
	char *ostat;
	int e, fd;

	(void) snprintf(path, sizeof (path), "%s/%s", root, FILE_STAT);

	if ((fd = open(path, O_RDONLY)) == -1)
		err(EXIT_FAILURE, "Could not open %s for read", path);

	if (fstat(fd, &st) != 0)
		err(EXIT_FAILURE, "stat fd failed");

	ostat = calloc(st.st_size, 1);
	if (read(fd, ostat, st.st_size) != st.st_size)
		err(EXIT_FAILURE, "short read");

	(void) close(fd);

	e = nvlist_unpack(ostat, st.st_size, &nvlp, 0);
	if (e != 0)
		err(EXIT_FAILURE, "unpack failed");
	free(ostat);

	nvlist_print(stdout, nvlp);

	nvlist_free(nvlp);
}

static void
write_stat(const char *root, const char *data)
{
	char path[PATH_MAX];
	nvlist_t *nvlp;
	int e, fd;
	FILE *fp;
	char *buf = NULL;
	size_t cap = 0;

	e = nvlist_alloc(&nvlp, NV_UNIQUE_NAME, 0);
	if (e != 0)
		errc(EXIT_FAILURE, e, "failed to create nvlist");

	(void) snprintf(path, sizeof (path), "%s/%s", root, FILE_STAT);

	if ((fd = open(path, O_WRONLY | O_TRUNC | O_CREAT, 0644)) == -1)
		err(EXIT_FAILURE, "Could not open %s for write", path);

	fp = fopen(data, "r");
	if (fp == NULL)
		err(EXIT_FAILURE, "Could not open %s for read", data);

	while (getline(&buf, &cap, fp) >= 0) {
		struct stat st;
		uint64_t filestat[2];
		char *p;

		/* /kernel/fs/aarch64/tmpfs=./kernel/fs/aarch64/tmpfs */
		if (*buf != '/' || (p = strchr(buf, '=')) == NULL) {
			warnx("Skipping line: %s", buf);
			continue;
		}
		*p = '\0';

		if (snprintf(path, sizeof (path), "%s/%s", root, buf) >=
		    sizeof (path)) {
			errx(EXIT_FAILURE, "Path too long - %s", buf);
		}

		if (stat(path, &st) == -1) {
			warn("Skipping %s", buf);
			continue;
		}

		if (!S_ISREG(st.st_mode))
			continue;

		filestat[0] = st.st_size;
		filestat[1] = st.st_mtime;

		e = nvlist_add_uint64_array(nvlp, buf + 1, filestat, 2);
		if (e != 0) {
			errc(EXIT_FAILURE, e, "failed to add stat data for %s",
			    buf);
		}
	}

	fclose(fp);
	free(buf);

	buf = NULL;
	cap = 0;
	e = nvlist_pack(nvlp, &buf, &cap, NV_ENCODE_XDR, 0);
	if (e != 0)
		errc(EXIT_FAILURE, e, "failed to pack nvlist");

	if (write(fd, buf, cap) != cap)
		err(EXIT_FAILURE, "short write");

	close(fd);
	nvlist_free(nvlp);
	free(buf);
}

int
main(int argc, char **argv)
{
	const char *optstring = "R:w:";
	const char *root = "/";
	const char *datafile = NULL;
	int c;

	while ((c = getopt(argc, argv, optstring)) != -1) {
		switch (c) {
		case 'R':
			root = optarg;
			break;
		case 'w':
			datafile = optarg;
			break;
		}
	}

	if (datafile == NULL)
		read_stat(root);
	else
		write_stat(root, datafile);

	return (0);
}

