/* process-level glue: signal handlers need a c callback */

#include <signal.h>
#include <string.h>
#include <locale.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <time.h>
#include <dirent.h>
#include <sys/stat.h>

static volatile sig_atomic_t pending_signal;

static void note_signal(int sig)
{
	pending_signal = sig;
}

void mx_watch_signals(void)
{
	struct sigaction sa;

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = note_signal;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGHUP, &sa, NULL);
	signal(SIGPIPE, SIG_IGN);
}

int mx_take_signal(void)
{
	int sig = pending_signal;

	pending_signal = 0;
	return sig;
}

/* child side of fork: undo the signal setup before exec */
void mx_reset_signals(void)
{
	sigset_t none;

	signal(SIGTERM, SIG_DFL);
	signal(SIGINT, SIG_DFL);
	signal(SIGHUP, SIG_DFL);
	signal(SIGPIPE, SIG_DFL);
	sigemptyset(&none);
	sigprocmask(SIG_SETMASK, &none, NULL);
}

void mx_init_locale(void)
{
	setlocale(LC_ALL, "");
	setlocale(LC_NUMERIC, "C");
}

/* fork and exec argv in a new session; returns the pid or -1 */
pid_t mx_spawn(char *const argv[], const char *dir)
{
	pid_t pid = fork();

	if (pid != 0)
		return pid;
	setsid();
	mx_reset_signals();
	if (dir && *dir && chdir(dir) != 0)
		fprintf(stderr, "mosaic: cannot enter %s: %s\n", dir, strerror(errno));
	execvp(argv[0], argv);
	fprintf(stderr, "mosaic: cannot run %s: %s\n", argv[0], strerror(errno));
	_exit(127);
}

/* returns 0 or an errno value; follow selects stat over lstat */
int mx_file_info(const char *path, int follow, unsigned int *mode,
		 long long *size, long long *mtime)
{
	struct stat st;

	if ((follow ? stat(path, &st) : lstat(path, &st)) != 0)
		return errno;
	*mode = st.st_mode;
	*size = st.st_size;
	*mtime = st.st_mtime;
	return 0;
}

const char *mx_read_dir(DIR *dir)
{
	struct dirent *d = readdir(dir);

	return d ? d->d_name : NULL;
}

int mx_errno(void)
{
	return errno;
}

int mx_format_time(long long t, const char *fmt, char *buf, int len)
{
	time_t tt = (time_t)t;
	struct tm tm;

	if (len <= 0 || !localtime_r(&tt, &tm))
		return 0;
	return (int)strftime(buf, (size_t)len, fmt, &tm);
}
