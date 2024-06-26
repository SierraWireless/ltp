#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2016-2018 Oracle and/or its affiliates. All Rights Reserved.

TST_SETUP="setup"
TST_TESTFUNC="test"
TST_CLEANUP="cleanup"
TST_NEEDS_TMPDIR=1
TST_NEEDS_ROOT=1
TST_NEEDS_CMDS="pkill sysctl ethtool"
# for more stable results set to a single thread
TST_NETLOAD_CLN_NUMBER=1

busy_poll_check_config()
{
	if [ ! -f "/proc/sys/net/core/busy_read" -a \
	     ! -f "/proc/sys/net/core/busy_poll" ]; then
		tst_brk TCONF "busy poll not configured, CONFIG_NET_RX_BUSY_POLL"
	fi

	if tst_kvcmp -lt "4.5"; then
		ethtool --show-features $(tst_iface) | \
			grep -q 'busy-poll.*on' || \
			tst_brk TCONF "busy poll not supported by driver"
	fi
}

. tst_net.sh
