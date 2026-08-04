/*****************************************************************************
 * ServoDrive_FSMC (0x00000009 / 0x26483052) — 最小 PDO 周期例程
 *
 * 板上 PDO：SM2 RxPDO 0x1601（8×LED + u32）、SM3 TxPDO 0x1a00/0x1a02（开关+AI）
 * 用法: sudo ethercat-io-demo [周期_us] [运行秒数，0=一直跑]
 * 另开终端: ethercat slaves   # 应见 OP
 ****************************************************************************/

#include <errno.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

#include "ecrt.h"

#define PERIOD_NS_DEFAULT 1000000U /* 1 ms */
#define SlavePos          0, 0
#define ServoDrive_FSMC   0x00000009, 0x26483052

static volatile sig_atomic_t run = 1;

static ec_master_t *master = NULL;
static ec_domain_t *domain = NULL;
static uint8_t *pd = NULL;

static unsigned int off_led;
static unsigned int off_out32;
static unsigned int off_switch;
static unsigned int off_ai_status;
static unsigned int off_ai_value;

/* 与 ethercat cstruct -p 0 一致 */
static ec_pdo_entry_info_t slave_0_pdo_entries[] = {
	{0x7010, 0x01, 1},
	{0x7010, 0x02, 1},
	{0x7010, 0x03, 1},
	{0x7010, 0x04, 1},
	{0x7010, 0x05, 1},
	{0x7010, 0x06, 1},
	{0x7010, 0x07, 1},
	{0x7010, 0x08, 1},
	{0x0000, 0x00, 8},
	{0x7011, 0x00, 32},
	{0x6000, 0x01, 1},
	{0x6000, 0x02, 1},
	{0x6000, 0x03, 1},
	{0x6000, 0x04, 1},
	{0x6000, 0x05, 1},
	{0x6000, 0x06, 1},
	{0x6000, 0x07, 1},
	{0x6000, 0x08, 1},
	{0x0000, 0x00, 8},
	{0x6020, 0x01, 1},
	{0x6020, 0x02, 1},
	{0x6020, 0x03, 2},
	{0x6020, 0x05, 2},
	{0x0000, 0x00, 8},
	{0x1802, 0x07, 1},
	{0x1802, 0x09, 1},
	{0x6020, 0x11, 16},
};

static ec_pdo_info_t slave_0_pdos[] = {
	{0x1601, 10, slave_0_pdo_entries + 0},
	{0x1a00, 9, slave_0_pdo_entries + 10},
	{0x1a02, 8, slave_0_pdo_entries + 19},
};

static ec_sync_info_t slave_0_syncs[] = {
	{0, EC_DIR_OUTPUT, 0, NULL, EC_WD_DISABLE},
	{1, EC_DIR_INPUT, 0, NULL, EC_WD_DISABLE},
	{2, EC_DIR_OUTPUT, 1, slave_0_pdos + 0, EC_WD_ENABLE},
	{3, EC_DIR_INPUT, 2, slave_0_pdos + 1, EC_WD_DISABLE},
	{0xff, EC_DIR_INVALID, 0, NULL, EC_WD_DISABLE}
};

static ec_pdo_entry_reg_t domain_regs[] = {
	{SlavePos, ServoDrive_FSMC, 0x7010, 0x01, &off_led, NULL},
	{SlavePos, ServoDrive_FSMC, 0x7011, 0x00, &off_out32, NULL},
	{SlavePos, ServoDrive_FSMC, 0x6000, 0x01, &off_switch, NULL},
	{SlavePos, ServoDrive_FSMC, 0x6020, 0x01, &off_ai_status, NULL},
	{SlavePos, ServoDrive_FSMC, 0x6020, 0x11, &off_ai_value, NULL},
	{}
};

static void on_signal(int sig)
{
	(void)sig;
	run = 0;
}

static void stack_prefault(void)
{
	unsigned char dummy[8 * 1024];
	memset(dummy, 0, sizeof(dummy));
}

static int set_realtime(void)
{
	struct sched_param param = {.sched_priority = 80};
	if (mlockall(MCL_CURRENT | MCL_FUTURE) != 0)
		perror("mlockall");
	stack_prefault();
	if (sched_setscheduler(0, SCHED_FIFO, &param) != 0) {
		perror("sched_setscheduler");
		return -1;
	}
	return 0;
}

static void timespec_add_ns(struct timespec *t, long ns)
{
	t->tv_nsec += ns;
	while (t->tv_nsec >= 1000000000L) {
		t->tv_nsec -= 1000000000L;
		t->tv_sec++;
	}
}

static long long timespec_diff_ns(const struct timespec *a, const struct timespec *b)
{
	return (long long)(a->tv_sec - b->tv_sec) * 1000000000LL +
	       (a->tv_nsec - b->tv_nsec);
}

int main(int argc, char **argv)
{
	ec_slave_config_t *sc;
	unsigned period_ns = PERIOD_NS_DEFAULT;
	unsigned run_sec = 0;
	unsigned cycle = 0;
	uint8_t led = 0x01;
	struct timespec wakeup, now, prev;
	long long dt_ns, dt_min = 0, dt_max = 0, dt_sum = 0;
	unsigned dt_n = 0;

	if (argc >= 2)
		period_ns = (unsigned)strtoul(argv[1], NULL, 0) * 1000U; /* us → ns */
	if (argc >= 3)
		run_sec = (unsigned)strtoul(argv[2], NULL, 0);

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);
	set_realtime();

	master = ecrt_request_master(0);
	if (!master) {
		fprintf(stderr, "ecrt_request_master failed（确认 ethercat 已 start）\n");
		return 1;
	}

	domain = ecrt_master_create_domain(master);
	if (!domain) {
		fprintf(stderr, "create_domain failed\n");
		return 1;
	}

	sc = ecrt_master_slave_config(master, SlavePos, ServoDrive_FSMC);
	if (!sc) {
		fprintf(stderr, "slave_config failed（Vendor/Product 不匹配？）\n");
		return 1;
	}

	if (ecrt_slave_config_pdos(sc, EC_END, slave_0_syncs)) {
		fprintf(stderr, "config_pdos failed\n");
		return 1;
	}

	if (ecrt_domain_reg_pdo_entry_list(domain, domain_regs)) {
		fprintf(stderr, "reg_pdo_entry_list failed\n");
		return 1;
	}

	printf("Activating master (period=%u us)...\n", period_ns / 1000U);
	if (ecrt_master_activate(master)) {
		fprintf(stderr, "activate failed\n");
		return 1;
	}

	pd = ecrt_domain_data(domain);
	if (!pd) {
		fprintf(stderr, "domain_data failed\n");
		return 1;
	}

	printf("offsets: led=%u out32=%u switch=%u ai_st=%u ai=%u\n",
	       off_led, off_out32, off_switch, off_ai_status, off_ai_value);
	printf("Ctrl+C 停止。另开终端看: ethercat slaves / ethercat domain\n");

	clock_gettime(CLOCK_MONOTONIC, &wakeup);
	prev = wakeup;

	while (run) {
		timespec_add_ns(&wakeup, (long)period_ns);
		clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &wakeup, NULL);

		clock_gettime(CLOCK_MONOTONIC, &now);
		dt_ns = timespec_diff_ns(&now, &prev);
		prev = now;
		if (dt_n == 0) {
			dt_min = dt_max = dt_ns;
		} else {
			if (dt_ns < dt_min)
				dt_min = dt_ns;
			if (dt_ns > dt_max)
				dt_max = dt_ns;
		}
		dt_sum += dt_ns;
		dt_n++;

		ecrt_master_receive(master);
		ecrt_domain_process(domain);

		/* 跑马灯 + 写 32bit 输出；读开关与模拟量 */
		if ((cycle % 200) == 0) {
			led = (uint8_t)((led << 1) | ((led & 0x80) ? 1 : 0));
			if (!(led & 0xff))
				led = 0x01;
		}
		EC_WRITE_U8(pd + off_led, led);
		EC_WRITE_U32(pd + off_out32, cycle);

		if ((cycle % 1000) == 0) {
			uint8_t sw = EC_READ_U8(pd + off_switch);
			uint16_t ai = EC_READ_U16(pd + off_ai_value);
			printf("cycle=%u led=0x%02x switch=0x%02x ai=%u  "
			       "dt_us min/avg/max = %lld / %lld / %lld\n",
			       cycle, led, sw, ai,
			       dt_min / 1000, (dt_sum / dt_n) / 1000, dt_max / 1000);
		}

		ecrt_domain_queue(domain);
		ecrt_master_send(master);
		cycle++;

		if (run_sec > 0 && cycle >= (run_sec * (1000000000ULL / period_ns)))
			break;
	}

	printf("stopped. latency_us min/avg/max = %lld / %lld / %lld (n=%u)\n",
	       dt_n ? dt_min / 1000 : 0,
	       dt_n ? (dt_sum / dt_n) / 1000 : 0,
	       dt_n ? dt_max / 1000 : 0,
	       dt_n);

	ecrt_release_master(master);
	return 0;
}
