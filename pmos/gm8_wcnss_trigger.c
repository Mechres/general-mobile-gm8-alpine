#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

int main(void)
{
	int fd;

	for (;;) {
		fd = open("/dev/wcnss_wlan", O_RDWR);
		if (fd >= 0)
			break;
		sleep(1);
	}

	for (;;)
		pause();
}
