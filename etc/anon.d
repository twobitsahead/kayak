/*
 * CDDL HEADER START
 *
 * The contents of this file are subject to the terms of the
 * Common Development and Distribution License, Version 1.0 only
 * (the "License").  You may not use this file except in compliance
 * with the License.
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
 * Copyright 2012 OmniTI Computer Consulting, Inc.  All rights reserved.
 * Copyright 2023 OmniOS Community Edition (OmniOSce) Association.
 */

/*
 * An anonymous dtrace script to build a list of files which are accessed.
 * It is used along with a big miniroot (see BIGROOT in build/miniroot)
 * to determine the files which cannot be culled from the miniroot.
 * These days we tend to just add new files by hand as required.
 */

fsinfo:genunix::
/args[0]->fi_mount=="/"/
{
        @[args[0]->fi_pathname] = count();
}

