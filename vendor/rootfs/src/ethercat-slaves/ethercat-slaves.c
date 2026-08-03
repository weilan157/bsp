/*
 * Minimal IgH EtherCAT slave scanner (ioctl on /dev/EtherCAT0).
 * Built against in-tree master/ioctl.h — no libethercat required.
 *
 * Usage:
 *   ethercat-slaves              # list master + slaves
 *   ethercat-slaves -r           # request rescan, wait, then list
 *   ethercat-slaves -d /dev/EtherCAT0
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "ioctl.h"

static const char *al_state_name(uint8_t s)
{
	switch (s & 0x0f) {
	case 0x01: return "INIT";
	case 0x02: return "PREOP";
	case 0x03: return "BOOT";
	case 0x04: return "SAFEOP";
	case 0x08: return "OP";
	default:   return "?";
	}
}

static const char *phase_name(uint8_t p)
{
	/* ec_master_phase_t: EC_ORPHANED=0, EC_IDLE=1, EC_OPERATION=2 */
	switch (p) {
	case 0: return "Orphaned";
	case 1: return "Idle";
	case 2: return "Operation";
	default: return "?";
	}
}

static void print_mac(const uint8_t *a)
{
	printf("%02x:%02x:%02x:%02x:%02x:%02x",
	       a[0], a[1], a[2], a[3], a[4], a[5]);
}

static int open_master(const char *dev, int wr)
{
	int fd = open(dev, wr ? O_RDWR : O_RDONLY);
	if (fd < 0)
		fprintf(stderr, "open %s: %s\n", dev, strerror(errno));
	return fd;
}

static int do_rescan(int fd)
{
	if (ioctl(fd, EC_IOCTL_MASTER_RESCAN) < 0) {
		fprintf(stderr, "ioctl MASTER_RESCAN: %s\n", strerror(errno));
		return -1;
	}
	return 0;
}

static int wait_scan(int fd, int timeout_sec)
{
	ec_ioctl_master_t m;
	int i;

	for (i = 0; i < timeout_sec * 10; i++) {
		memset(&m, 0, sizeof(m));
		if (ioctl(fd, EC_IOCTL_MASTER, &m) < 0) {
			fprintf(stderr, "ioctl MASTER: %s\n", strerror(errno));
			return -1;
		}
		if (!m.scan_busy)
			return 0;
		usleep(100000);
	}
	fprintf(stderr, "scan still busy after %ds\n", timeout_sec);
	return -1;
}

static int list_all(int fd)
{
	ec_ioctl_master_t m;
	ec_ioctl_slave_t s;
	unsigned int i, j;

	memset(&m, 0, sizeof(m));
	if (ioctl(fd, EC_IOCTL_MASTER, &m) < 0) {
		fprintf(stderr, "ioctl MASTER: %s\n", strerror(errno));
		return -1;
	}

	printf("Master phase=%s(%u) active=%u scan_busy=%u slaves=%u\n",
	       phase_name(m.phase), m.phase, m.active, m.scan_busy, m.slave_count);

	for (i = 0; i < m.num_devices && i < EC_MAX_NUM_DEVICES; i++) {
		printf("  device[%u] ", i);
		print_mac(m.devices[i].address);
		printf(" attached=%u link=%u tx=%llu rx=%llu\n",
		       m.devices[i].attached, m.devices[i].link_state,
		       (unsigned long long)m.devices[i].tx_count,
		       (unsigned long long)m.devices[i].rx_count);
	}

	if (m.slave_count == 0) {
		printf("\nNo slaves. Connect EtherCAT slave(s) to main port,\n");
		printf("then: ethercat-slaves -r\n");
		return 0;
	}

	printf("\n%-4s %-10s %-10s %-8s %-5s %s\n",
	       "Pos", "Vendor", "Product", "AL", "Err", "Name");
	for (i = 0; i < m.slave_count; i++) {
		memset(&s, 0, sizeof(s));
		s.position = (uint16_t)i;
		if (ioctl(fd, EC_IOCTL_SLAVE, &s) < 0) {
			fprintf(stderr, "ioctl SLAVE %u: %s\n", i, strerror(errno));
			continue;
		}
		printf("%-4u 0x%08x 0x%08x %-8s %-5u %s\n",
		       i, s.vendor_id, s.product_code,
		       al_state_name(s.al_state), s.error_flag,
		       s.name[0] ? s.name : "(unnamed)");
		for (j = 0; j < EC_MAX_PORTS; j++) {
			if (!s.ports[j].link.link_up &&
			    !s.ports[j].link.signal_detected)
				continue;
			printf("       port%u link=%u loop=%u signal=%u next=%u\n",
			       j,
			       s.ports[j].link.link_up,
			       s.ports[j].link.loop_closed,
			       s.ports[j].link.signal_detected,
			       s.ports[j].next_slave);
		}
	}
	return 0;
}

static void usage(const char *argv0)
{
	fprintf(stderr,
		"Usage: %s [-d /dev/EtherCAT0] [-r] [-t sec]\n"
		"  -d DEV   master device (default /dev/EtherCAT0)\n"
		"  -r       request bus rescan before listing\n"
		"  -t SEC   wait up to SEC for scan to finish (default 5)\n",
		argv0);
}

int main(int argc, char **argv)
{
	const char *dev = "/dev/EtherCAT0";
	int rescan = 0;
	int timeout = 5;
	int opt;
	int fd;
	int ret;

	while ((opt = getopt(argc, argv, "d:rt:h")) != -1) {
		switch (opt) {
		case 'd':
			dev = optarg;
			break;
		case 'r':
			rescan = 1;
			break;
		case 't':
			timeout = atoi(optarg);
			if (timeout < 1)
				timeout = 1;
			break;
		case 'h':
		default:
			usage(argv[0]);
			return opt == 'h' ? 0 : 1;
		}
	}

	fd = open_master(dev, rescan);
	if (fd < 0)
		return 1;

	if (rescan) {
		printf("Requesting rescan...\n");
		if (do_rescan(fd) < 0) {
			close(fd);
			return 1;
		}
		if (wait_scan(fd, timeout) < 0) {
			close(fd);
			return 1;
		}
	} else {
		/* If a scan is already running, wait briefly. */
		wait_scan(fd, timeout);
	}

	ret = list_all(fd);
	close(fd);
	return ret ? 1 : 0;
}
