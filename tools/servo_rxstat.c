// servo_rxstat.c —— 扫波特率，统计收到的 "FF FF" 帧头次数，用来反推板子的真实波特率
// 用法: servo_rxstat <port> <baud> <ms>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>
#include <sys/select.h>
#include <time.h>

static speed_t baud_of(unsigned int b) {
	switch (b) {
	case 9600: return B9600;
	case 57600: return B57600;
	case 115200: return B115200;
	case 500000: return B500000;
	case 1000000: return B1000000;
	case 1500000: return B1500000;
	case 2000000: return B2000000;
	case 3000000: return B3000000;
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

	unsigned char buf[512];
	long total = 0, headers = 0, prev = -1;
	struct timespec t0, now;
	clock_gettime(CLOCK_MONOTONIC, &t0);
	while (1) {
		fd_set rf; struct timeval tv = { 0, 100000 };
		FD_ZERO(&rf); FD_SET(fd, &rf);
		if (select(fd + 1, &rf, NULL, NULL, &tv) > 0) {
			int n = read(fd, buf, sizeof(buf));
			for (int i = 0; i < n; i++) {
				total++;
				if (prev == 0xFF && buf[i] == 0xFF) headers++;
				prev = buf[i];
			}
		}
		clock_gettime(CLOCK_MONOTONIC, &now);
		long el = (now.tv_sec - t0.tv_sec) * 1000 + (now.tv_nsec - t0.tv_nsec) / 1000000;
		if (el >= ms) break;
	}
	printf("baud=%-8u bytes=%-6ld ff_ff=%-4ld\n", baud, total, headers);
	close(fd);
	return 0;
}
