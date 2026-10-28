/*
 * i2c-recover —— 给卡死的 I2C 从机打恢复时序（纯软件）
 *
 * 场景：TLV320AIC3104 把 SDA 拉死在低电平（一次传输被打断后从机在等时钟），
 * 之后所有访问都 NAK。标准解法是手动打 9 个 SCL 时钟 + 一个 STOP，
 * 让从机把剩下的位吐完、释放 SDA。
 *
 * 依赖：内核 CONFIG_GPIO_CDEV=y（v1 ABI），/dev/gpiochip0 上的全局行号。
 * 用法：i2c-recover <scl_line> <sda_line>
 *       本板实测 i2c-gpio 报 "using lines 311 (SDA) and 310 (SCL)"，
 *       即 SCL=310、SDA=311。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <linux/gpio.h>

static int chip_fd = -1;
static struct gpiohandle_request req;
static int opened = 0;

static int gpio_setup(int scl, int sda)
{
	chip_fd = open("/dev/gpiochip0", O_RDWR);
	if (chip_fd < 0) {
		fprintf(stderr, "open /dev/gpiochip0: %s\n", strerror(errno));
		return -1;
	}

	memset(&req, 0, sizeof(req));
	req.lineoffsets[0] = (unsigned)scl;
	req.lineoffsets[1] = (unsigned)sda;
	req.flags = GPIOHANDLE_REQUEST_OUTPUT | GPIOHANDLE_REQUEST_OPEN_DRAIN;
	req.default_values[0] = 1;	/* SCL 释放（高） */
	req.default_values[1] = 1;	/* SDA 释放（高） */
	req.lines = 2;
	strncpy(req.consumer_label, "i2c-recover", sizeof(req.consumer_label) - 1);

	if (ioctl(chip_fd, GPIO_GET_LINEHANDLE_IOCTL, &req) < 0) {
		fprintf(stderr, "GPIO_GET_LINEHANDLE_IOCTL(scl=%d, sda=%d): %s\n",
			scl, sda, strerror(errno));
		close(chip_fd);
		chip_fd = -1;
		return -1;
	}
	opened = 1;
	return 0;
}

static void gpio_set(int scl, int sda)
{
	struct gpiohandle_data d;

	memset(&d, 0, sizeof(d));
	d.values[0] = (unsigned char)(scl ? 1 : 0);
	d.values[1] = (unsigned char)(sda ? 1 : 0);
	if (ioctl(req.fd, GPIOHANDLE_SET_LINE_VALUES_IOCTL, &d) < 0)
		fprintf(stderr, "set values: %s\n", strerror(errno));
}

static void gpio_cleanup(void)
{
	if (opened) {
		gpio_set(1, 1);
		close(req.fd);
		opened = 0;
	}
	if (chip_fd >= 0) {
		close(chip_fd);
		chip_fd = -1;
	}
}

int main(int argc, char **argv)
{
	int scl = 310, sda = 311;
	int i;

	if (argc >= 3) {
		scl = atoi(argv[1]);
		sda = atoi(argv[2]);
	}

	printf("i2c-recover: SCL=%d SDA=%d\n", scl, sda);

	if (gpio_setup(scl, sda) < 0)
		return 1;

	/* 起始条件：SDA 在 SCL 高时拉低 */
	gpio_set(1, 1);
	usleep(10);
	gpio_set(1, 0);
	usleep(10);

	/* 打 9 个时钟，让从机把卡住的位全部吐完 */
	for (i = 0; i < 9; i++) {
		gpio_set(0, 0);
		usleep(10);
		gpio_set(1, 0);
		usleep(10);
	}

	/* STOP：SCL 高时 SDA 由低变高 */
	gpio_set(1, 1);
	usleep(10);

	gpio_cleanup();
	printf("i2c-recover: done (9 clocks + STOP)\n");
	return 0;
}
