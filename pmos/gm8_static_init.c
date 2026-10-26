#define _GNU_SOURCE

#include <fcntl.h>
#include <signal.h>
#include <stddef.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

/*
 * Static PID 1 probe for the stock GM8 kernel.  It deliberately has no shell,
 * dynamic-loader, Alpine, OpenRC, or configfs dependency.  If the kernel can
 * mount system_a and exec this ELF, the marker will survive in misc for EDL
 * readback.  misc is GPT partition 30; only its final sector is touched.
 */
int main(void)
{
	static const char marker[] = "GM8_STATIC_RAN1\n";
	const char *dev = "/dev/mmcblk0p30";
	int fd;

	mkdir("/dev", 0755);
	mount("tmpfs", "/dev", "tmpfs", 0, "mode=0755");
	mknod(dev, S_IFBLK | 0600, makedev(179, 30));

	fd = open(dev, O_WRONLY | O_SYNC);
	if (fd >= 0) {
		if (lseek(fd, 2047 * 512, SEEK_SET) >= 0)
			write(fd, marker, sizeof(marker) - 1);
		fsync(fd);
		close(fd);
		sync();
	}

	for (;;)
		pause();
}
