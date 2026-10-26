#include <fcntl.h>
#include <signal.h>
#include <stddef.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/wait.h>
#include <unistd.h>

#define MARKER_OFFSET (2047 * 512)

static const char *const marker_dev = "/dev/mmcblk0p30";
static char *const clean_env[] = {
	"HOME=/root",
	"PATH=/sbin:/bin:/usr/sbin:/usr/bin",
	"SHELL=/bin/sh",
	"TERM=linux",
	NULL,
};

static void make_node(const char *path, mode_t mode, unsigned int major,
		      unsigned int minor)
{
	mknod(path, mode, makedev(major, minor));
}

static void setup_early_mounts(void)
{
	mount("proc", "/proc", "proc", 0, NULL);
	mount("sysfs", "/sys", "sysfs", 0, NULL);
	if (mount("devtmpfs", "/dev", "devtmpfs", 0, "mode=0755") < 0)
		mount("tmpfs", "/dev", "tmpfs", 0, "mode=0755");

	make_node("/dev/console", S_IFCHR | 0600, 5, 1);
	make_node("/dev/null", S_IFCHR | 0666, 1, 3);
	make_node("/dev/zero", S_IFCHR | 0666, 1, 5);
	make_node("/dev/tty", S_IFCHR | 0666, 5, 0);
	make_node("/dev/kmsg", S_IFCHR | 0600, 1, 11);
	make_node(marker_dev, S_IFBLK | 0600, 179, 30);
	mount("tmpfs", "/run", "tmpfs", 0, "mode=0755");
	mkdir("/run/sshd", 0755);
	mount("tmpfs", "/tmp", "tmpfs", 0, "mode=1777");
}

static void write_marker(const char *marker)
{
	char sector[512] = {0};
	int fd;

	strncpy(sector, marker, sizeof(sector) - 1);
	fd = open(marker_dev, O_WRONLY | O_SYNC);
	if (fd < 0)
		return;
	if (lseek(fd, MARKER_OFFSET, SEEK_SET) >= 0)
		write(fd, sector, sizeof(sector));
	fsync(fd);
	close(fd);
	sync();
}

static int dynamic_busybox_works(void)
{
	pid_t pid = fork();
	int status;

	if (pid < 0)
		return 0;
	if (pid == 0) {
		char *const argv[] = {"/bin/busybox", "true", NULL};
		execve(argv[0], argv, clean_env);
		_exit(111);
	}
	if (waitpid(pid, &status, 0) != pid)
		return 0;
	return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static int write_text(const char *path, const char *text)
{
	int fd = open(path, O_WRONLY);
	ssize_t length = (ssize_t)strlen(text);
	ssize_t written;

	if (fd < 0)
		return 0;
	written = write(fd, text, (size_t)length);
	close(fd);
	return written == length;
}

static const char *setup_android_usb(void)
{
	static const char base[] = "/sys/class/android_usb/android0/";
	char path[sizeof(base) + 16];

#define USB_WRITE(file, value, error_marker) do { \
	strcpy(path, base); \
	strcat(path, file); \
	if (!write_text(path, value)) \
		return error_marker; \
} while (0)

	USB_WRITE("enable", "0", "GM8_USB_NO_CLASS_v1\n");
	USB_WRITE("idVendor", "18d1", "GM8_USB_ID_FAIL_v1\n");
	USB_WRITE("idProduct", "D002", "GM8_USB_ID_FAIL_v1\n");
	/* Some downstream android_usb variants omit the optional string files. */
	write_text("/sys/class/android_usb/android0/product", "GM8-node");
	USB_WRITE("functions", "rndis", "GM8_USB_FUNC_FAIL_v1\n");
	USB_WRITE("enable", "1", "GM8_USB_ENABLE_FAIL_v1\n");
	return "GM8_USB_ENABLED_v1\n";

#undef USB_WRITE
}

static int configure_usb_network(void)
{
	static const char command[] =
		"for i in rndis0 usb0; do "
		"/bin/busybox ip link set \"$i\" up 2>/dev/null || continue; "
		"/bin/busybox ip addr add 172.16.42.1/24 dev \"$i\" 2>/dev/null; "
		"exit 0; done; exit 1";
	pid_t pid = fork();
	int status;

	if (pid < 0)
		return 0;
	if (pid == 0) {
		char *const argv[] = {"/bin/busybox", "sh", "-c",
				      (char *)command, NULL};
		execve(argv[0], argv, clean_env);
		_exit(111);
	}
	if (waitpid(pid, &status, 0) != pid)
		return 0;
	return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

/* OpenRC/mdev may cycle rndis0 while userspace finishes booting.  Keep the
 * management address present so the diagnostic SSH path cannot disappear. */
static void start_usb_network_keeper(void)
{
	pid_t pid = fork();

	if (pid != 0)
		return;
	for (;;) {
		sleep(5);
		configure_usb_network();
	}
}

static int start_sshd(void)
{
	pid_t pid = fork();
	int status;

	if (pid < 0)
		return 0;
	if (pid == 0) {
		char *const argv[] = {
			"/usr/sbin/sshd",
			"-o", "AuthorizedKeysFile=/etc/ssh/gm8_authorized_keys",
			"-o", "StrictModes=no",
			"-o", "PermitRootLogin=yes",
			"-o", "PasswordAuthentication=no",
			NULL,
		};
		execve(argv[0], argv, clean_env);
		_exit(111);
	}
	if (waitpid(pid, &status, 0) != pid)
		return 0;
	return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

int main(void)
{
	char *const init_argv[] = {"/sbin/init", NULL};

	setup_early_mounts();
	write_marker("GM8_WRAPPER_START_v1\n");

	if (!dynamic_busybox_works()) {
		write_marker("GM8_DYNAMIC_FAIL_v1\n");
		for (;;)
			pause();
	}
	write_marker("GM8_DYNAMIC_OK_v1\n");
	write_marker(setup_android_usb());
	sleep(3);
	if (!configure_usb_network()) {
		write_marker("GM8_NET_CONFIG_FAIL_v1\n");
		for (;;)
			pause();
	}
	write_marker("GM8_NET_CONFIG_OK_v1\n");

	if (!start_sshd()) {
		write_marker("GM8_SSHD_FAIL_v1\n");
		for (;;)
			pause();
	}
	write_marker("GM8_SSHD_OK_v1\n");
	start_usb_network_keeper();

	execve(init_argv[0], init_argv, clean_env);
	write_marker("GM8_INIT_EXEC_FAIL_v1\n");
	for (;;)
		pause();
}
