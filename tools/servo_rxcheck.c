// servo_rxcheck.c —— 按 Feetech SCS 帧格式解析，统计"校验和正确的完整帧"个数
// 用法: servo_rxcheck <port> <baud> <ms>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>
#include <sys/select.h>
#include <time.h>
#include <string.h>

static speed_t baud_of(unsigned int b) {
	switch (b) {
	case 115200: return B115200;
	case 460800: return B460800;
	case 921600: return B921600;
	case 1000000: return B1000000;
	case 1500000: return B1500000;
	case 2000000: return B2000000;
	default: return B1000000;
	}
}

int main(int argc, char **argv)
{
	const char *port = argc > 1 ? argv[1] : "/dev/ttyAS0";
	unsigned int baud = argc > 2 ? (unsigned int)atoi(argv[2]) : 1000000;
	int ms = argc > 3 ? atoi(argv[3]) : 1000;

	int fd = open(port, O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (fd < 0) { perror("open"); return 1; }
	struct termios tio;
	tcgetattr(fd, &tio);
	cfmakeraw(&tio);
	cfsetispeed(&tio, baud_of(baud));
	cfsetospeed(&tio, baud_of(baud));
	tio.c_cflag |= (CLOCAL | CREAD);
	tio.c_cflag &= ~CRTSCTS;
	tio.c_cc[VMIN] = 0; tio.c_cc[VTIME] = 0;
	tcsetattr(fd, TCSANOW, &tio);
	tcflush(fd, TCIOFLUSH);

	unsigned char b[2048];
	int len = 0, valid = 0, seen = 0;
	unsigned char first[32]; int firstlen = 0;

	struct timespec t0, now;
	clock_gettime(CLOCK_MONOTONIC, &t0);
	for (;;) {
		fd_set rf; struct timeval tv = { 0, 50000 };
		FD_ZERO(&rf); FD_SET(fd, &rf);
		if (select(fd + 1, &rf, NULL, NULL, &tv) > 0) {
			int n = read(fd, b + len, sizeof(b) - len);
			if (n > 0) len += n;
		}
		/* 解析 */
		int i = 0;
		while (i + 4 <= len) {
			if (b[i] != 0xFF || b[i + 1] != 0xFF) { i++; continue; }
			int l = b[i + 3];
			if (l < 2 || l > 32) { i += 2; continue; }
			if (i + 4 + l > len) break;      /* 等更多数据 */
			unsigned char sum = 0;
			for (int k = i + 2; k < i + 4 + l - 1; k++) sum += b[k];
			sum = (unsigned char)~sum;
			seen++;
			if (sum == b[i + 4 + l - 1]) {
				valid++;
				if (!firstlen) {
					firstlen = 4 + l; if (firstlen > 32) firstlen = 32;
					memcpy(first, b + i, firstlen);
				}
			}
			i += 4 + l;
		}
		if (i > 0) { memmove(b, b + i, len - i); len -= i; }

		clock_gettime(CLOCK_MONOTONIC, &now);
		long el = (now.tv_sec - t0.tv_sec) * 1000 + (now.tv_nsec - t0.tv_nsec) / 1000000;
		if (el >= ms) break;
	}
	printf("baud=%-8u frames=%-3d valid=%-3d first=", baud, seen, valid);
	for (int k = 0; k < firstlen; k++) printf("%02x ", first[k]);
	printf("\n");
	close(fd);
	return 0;
}
