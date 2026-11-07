// servo_probe.c — 在板子上探测 Dynamixel 总线，排除"方向控制/RTS/RS485"这类软件侧因素
//
// 用法: servo_probe <port>
//   * 1 Mbps raw
//   * 依次尝试: 普通模式 / RTS 常高 / RS485 内核模式(SER_RS485_ENABLED)
//   * 每种模式对 ID 1..12 发协议2.0 ping，并读回 0.1s 内的数据
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <linux/serial.h>

static unsigned short crc16(const unsigned char *d, int n) {
	unsigned short crc = 0xFFFF;
	for (int i = 0; i < n; i++) {
		crc ^= d[i];
		for (int b = 0; b < 8; b++)
			crc = (crc & 1) ? (unsigned short)((crc >> 1) ^ 0xA001) : (unsigned short)(crc >> 1);
	}
	return crc;
}

static speed_t baud_of(unsigned int b) {
	switch (b) {
	case 9600: return B9600;
	case 57600: return B57600;
	case 115200: return B115200;
	case 500000: return B500000;
	case 1000000: return B1000000;
	case 2000000: return B2000000;
	case 3000000: return B3000000;
	default: return B1000000;
	}
}

static int open_port(const char *port, unsigned int baud) {
	int fd = open(port, O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (fd < 0) { perror("open"); return -1; }
	struct termios tio;
	if (tcgetattr(fd, &tio) < 0) { perror("tcgetattr"); close(fd); return -1; }
	cfmakeraw(&tio);
	cfsetispeed(&tio, baud_of(baud));
	cfsetospeed(&tio, baud_of(baud));
	tio.c_cflag |= (CLOCAL | CREAD);
	tio.c_cflag &= ~CRTSCTS;
	tio.c_cc[VMIN] = 0; tio.c_cc[VTIME] = 0;
	if (tcsetattr(fd, TCSANOW, &tio) < 0) { perror("tcsetattr"); close(fd); return -1; }
	return fd;
}

static int read_reply(int fd, unsigned char *buf, int cap) {
	fd_set rf; struct timeval tv = { .tv_sec = 0, .tv_usec = 150000 };
	FD_ZERO(&rf); FD_SET(fd, &rf);
	int r = select(fd + 1, &rf, NULL, NULL, &tv);
	if (r <= 0) return 0;
	int n = read(fd, buf, cap);
	return n > 0 ? n : 0;
}

static int use_feetech;
static int use_read9;

/* Feetech SCS/STS 帧: FF FF id len instr params chk
 * len = params + 2；chk = ~(header 之后所有字节之和) & 0xff。PING = 0x01。 */
static int scs_ping(int fd, unsigned char *buf, int cap, int id)
{
	unsigned char f[6];
	f[0] = 0xFF; f[1] = 0xFF; f[2] = (unsigned char)id;
	f[3] = 0x02; f[4] = 0x01;
	f[5] = (unsigned char)(~((id + 0x02 + 0x01) & 0xFF));
	tcflush(fd, TCIOFLUSH);
	write(fd, f, 6);
	return read_reply(fd, buf, cap);
}

/* 和 FT SCServo Debug 的"搜索"完全一样的帧：
 * FF FF id 04 02 00 09 chk   —— READ 地址0 长度9（固件版本/ID/波特率/...）
 */
static int scs_read9(int fd, unsigned char *buf, int cap, int id)
{
	unsigned char f[8];
	f[0] = 0xFF; f[1] = 0xFF; f[2] = (unsigned char)id;
	f[3] = 0x04; f[4] = 0x02; f[5] = 0x00; f[6] = 0x09;
	f[7] = (unsigned char)(~((id + 0x04 + 0x02 + 0x00 + 0x09) & 0xFF));
	tcflush(fd, TCIOFLUSH);
	if (write(fd, f, 8) != 8) return 0;
	return read_reply(fd, buf, cap);
}

static int ping_all(int fd, const char *label) {
	int answered = 0;
	unsigned char buf[64];
	for (int id = 1; id <= 250; id++) {
		if (use_feetech) {
			int n2 = use_read9 ? scs_read9(fd, buf, sizeof(buf), id)
					   : scs_ping(fd, buf, sizeof(buf), id);
			if (n2 > 0) {
				answered++;
				printf("  %s: id=%d SCS reply %d bytes:", label, id, n2);
				for (int k = 0; k < n2 && k < 16; k++)
					printf(" %02x", buf[k]);
				printf("\n");
			}
			usleep(20000);
			continue;
		}
		// Dynamixel 2.0 帧: FF FF FD 00 ID LEN_L LEN_H INST PARAM... CRC_L CRC_H
		// CRC 只算 FD 开始到最后一个参数（不含前两个 FF）
		unsigned char body[6] = { 0xFD, 0x00, (unsigned char)id, 0x03, 0x00, 0x01 };
		unsigned short c = crc16(body, 6);
		unsigned char pkt[10] = { 0xFF, 0xFF, 0xFD, 0x00, (unsigned char)id,
					  0x03, 0x00, 0x01, 0x00, 0x00 };
		pkt[8] = c & 0xFF; pkt[9] = (c >> 8) & 0xFF;
		tcflush(fd, TCIOFLUSH);
		int w = write(fd, pkt, 10);
		if (w != 10) { printf("  %s: write failed (%d, %s)\n", label, w, strerror(errno)); }
		int n = read_reply(fd, buf, sizeof(buf));
		if (n > 0) {
			answered++;
			printf("  %s: id=%d reply %d bytes:", label, id, n);
			for (int i = 0; i < n && i < 16; i++) printf(" %02x", buf[i]);
			printf("\n");
		}
		usleep(20000);
	}
	if (!answered) printf("  %s: 12 个 ID 全部无回应\n", label);
	return answered;
}

int main(int argc, char **argv) {
	if (argc > 2 && strstr(argv[2], "dump")) {
		/* dump_frames <feetech|dxl> [n] */
		int n = argc > 3 ? atoi(argv[3]) : 8;
		int feet = argc > 1 && strstr(argv[1], "feetech");
		for (int id = 1; id <= n; id++) {
			if (feet) {
				unsigned char f[6] = { 0xFF, 0xFF, (unsigned char)id, 0x02, 0x01,
					(unsigned char)(~((id + 0x02 + 0x01) & 0xFF)) };
				printf("id=%2d SCS :", id);
				for (int i = 0; i < 6; i++) printf(" %02X", f[i]);
				printf("\n");
			} else {
				unsigned char body[6] = { 0xFD, 0x00, (unsigned char)id, 0x03, 0x00, 0x01 };
				unsigned short c = crc16(body, 6);
				unsigned char f[10] = { 0xFF, 0xFF, 0xFD, 0x00, (unsigned char)id,
					0x03, 0x00, 0x01, 0, 0 };
				f[8] = c & 0xFF; f[9] = (c >> 8) & 0xFF;
				printf("id=%2d DXL :", id);
				for (int i = 0; i < 10; i++) printf(" %02X", f[i]);
				printf("\n");
			}
		}
		return 0;
	}
	const char *port = argc > 1 ? argv[1] : "/dev/ttyAS0";
	unsigned int baud = argc > 2 ? (unsigned int)atoi(argv[2]) : 1000000;
	if (argc > 3 && strstr(argv[3], "feetech"))
		use_feetech = 1;
	if (argc > 3 && strstr(argv[3], "read9"))
		use_feetech = 1, use_read9 = 1;
	if (argc > 2 && strstr(argv[2], "read9"))
		use_feetech = 1, use_read9 = 1;
	int fd = open_port(port, baud);
	if (fd < 0) return 1;

	printf("== port %s @%u bps ==\n", port, baud);

	printf("[1] 普通模式\n");
	int total = ping_all(fd, "plain");

	printf("[2] RTS 常高（有些 HAT 用 RTS 做方向）\n");
	int flags;
	if (ioctl(fd, TIOCMGET, &flags) == 0) {
		flags |= TIOCM_RTS;
		ioctl(fd, TIOCMSET, &flags);
		total += ping_all(fd, "rts-high");
		flags &= ~TIOCM_RTS;
		ioctl(fd, TIOCMSET, &flags);
	} else perror("TIOCMGET");

	printf("[3] 内核 RS485 模式（SER_RS485_ENABLED）\n");
	struct serial_rs485 rs = { 0 };
	rs.flags = SER_RS485_ENABLED | SER_RS485_RTS_ON_SEND;
	rs.delay_rts_before_send = 0;
	rs.delay_rts_after_send = 0;
	if (ioctl(fd, TIOCSRS485, &rs) == 0) {
		total += ping_all(fd, "rs485");
	} else {
		printf("  TIOCSRS485 失败: %s（驱动不支持，正常）\n", strerror(errno));
	}

	printf("== 总线应答总数: %d ==\n", total);
	close(fd);
	return total > 0 ? 0 : 2;
}
