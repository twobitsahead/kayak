/*
 * This file and its contents are supplied under the terms of the
 * Common Development and Distribution License ("CDDL"), version 1.0.
 * You may only use this file in accordance with the terms of version
 * 1.0 of the CDDL.
 *
 * A full copy of the text of the CDDL should have accompanied this
 * source.  A copy of the CDDL is also available via the Internet at
 * http://www.illumos.org/license/CDDL.
 */

/*
 * Copyright 2012 Citrus IT Limited, All rights reserved.
 */

#include <stdio.h>
#include <strings.h>
#include <stdlib.h>
#include <crypt.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <pwd.h>
#include <shadow.h>

enum { MODE_SET, MODE_SETHASH, MODE_PRINTHASH };

static int debug = 0;

int
usage()
{
	printf("Syntax: passutil [-f <shadow file>] -s <user> <password>\n");
	printf("        passutil [-f <shadow file>] -S <user> <hash>\n");
	printf("        passutil -H <password>\n");
	return 0;
}

int
copy_file(char *src, char *dst)
{
	char buf[0x400];
	struct stat st;
	int sfd, dfd;
	off_t offset;
	size_t b;

	if ((sfd = open(src, O_RDONLY)) < 0)
	{
		perror(src);
		return 0;
	}

	if (fstat(sfd, &st) < 0)
	{
		perror("fstat");
		close(sfd);
		return 0;
	}

	if ((dfd = open(dst, O_WRONLY|O_CREAT|O_TRUNC, 0600)) < 0)
	{
		perror(dst);
		close(sfd);
		return 0;
	}

	offset = 0;
	while ((b = read(sfd, buf, sizeof(buf) - 1)) > 0)
	{
		if (write(dfd, buf, b) <= 0)
		{
			perror("write");
			return 0;
		}
	}

	close(sfd);
	close(dfd);

	return 1;
}

int
main(int argc, char **argv)
{
	char *shadowfile = "/etc/shadow";
	char *nshadowfile;
	char *tempfile = tmpnam(NULL);
	char *user, *passwd;
	int mode;
	int lock = 1;
	int fd;
	FILE *fp, *of;
	struct passwd *pwd;
	struct spwd *spwd;

	if (argc < 3 || !strcmp(argv[1], "-h"))
		return usage();

	if (!strcmp(argv[1], "-d"))
	{
		debug++;
		argc--, argv++;
	}

	if (argc < 3)
		return usage();

	if (!strcmp(argv[1], "-f"))
	{
		shadowfile = argv[2];
		lock = 0;
		argc -= 2; argv += 2;
	}

	if (argc < 3 || *argv[1] != '-')
		return usage();

	switch (argv[1][1])
	{
	    case 's':
		mode = MODE_SET;
		if (argc < 4)
			return usage();
		break;

	    case 'S':
		mode = MODE_SETHASH;
		if (argc < 4)
			return usage();
		break;

	    case 'H':
		mode = MODE_PRINTHASH;
		break;

	    default:
		return usage();
	}

	if (mode == MODE_PRINTHASH)
		passwd = argv[2];
	else
	{
		user = argv[2];
		passwd = argv[3];

		if (!(pwd = getpwnam(user)))
		{
			fprintf(stderr, "Unknown user, %s\n", user);
			return -1;
		}
	}

	if (mode == MODE_SET || mode == MODE_PRINTHASH)
	{
		char *salt = crypt_gensalt(NULL, NULL);

		if (!salt)
		{
			perror("gensalt");
			return -1;
		}
		if (debug)
			printf("Using salt: %s\n", salt);
		passwd = crypt(passwd, salt);
		free(salt);
		if (debug)
			printf("Crypted:    %s\n", passwd);
	}

	if (mode == MODE_PRINTHASH)
	{
		printf("%s\n", passwd);
		return 0;
	}

	if (lock)
	{
		if (lckpwdf())
		{
			perror("shadow lock");
			return -1;
		}
		if (debug)
			printf("Locked shadow file.\n");
	}

	if (!(fp = fopen(shadowfile, "r")))
	{
		perror(shadowfile);
		if (lock)
			ulckpwdf();
		return -1;
	}

	if ((fd = open(tempfile, O_WRONLY | O_CREAT | O_TRUNC, 0600)) == -1)
	{
		perror(tempfile);
		if (lock)
			ulckpwdf();
		return -1;
	}
	if (!(of = fdopen(fd, "wb")))
	{
		perror("fdopen");
		if (lock)
			ulckpwdf();
		return -1;
	}
	if (debug)
		printf("Opened temporary file: %s\n", tempfile);

	while (spwd = fgetspent(fp))
	{
		if (debug)
			printf("Read entry for user: %s\n", spwd->sp_namp);
		if (!strcmp(spwd->sp_namp, pwd->pw_name))
		{
			if (debug)
				printf(" ! Found user !\n");
			spwd->sp_pwdp = passwd;
			/* Disable password aging while we're here... */
			spwd->sp_min = -1;
			spwd->sp_max = -1;
			spwd->sp_warn = -1;
		}
		putspent(spwd, of);
	}

	fclose(fp);
	fclose(of);

	nshadowfile = (char *)malloc(strlen(shadowfile) + 2);
	sprintf(nshadowfile, "%s~", shadowfile);

	copy_file(shadowfile, nshadowfile);
	copy_file(tempfile, shadowfile);
	unlink(tempfile);

	if (lock)
		ulckpwdf();

	return 0;
}

