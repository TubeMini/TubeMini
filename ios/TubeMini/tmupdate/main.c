// tmupdate — installs a TubeMini update package as root, then restarts SpringBoard (respring).
//
// The app downloads the package into UPDATE_DIR and runs this tool, which the package's postinst makes
// setuid root (the way Cydia's own helper works). It only accepts a .deb inside UPDATE_DIR whose
// Package field is PACKAGE, so it cannot be used to install anything else. It detaches before
// installing: dpkg replaces the running app, which gets killed.
//
//   tmupdate /var/mobile/Documents/TubeMini-Update/update.deb
// Log: UPDATE_DIR/install.log (last line "dpkg exit <code>"; the app shows an error when it is not 0).

#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#define UPDATE_DIR "/var/mobile/Documents/TubeMini-Update/"
#define PACKAGE "vn.tubemini.io"
#define LOG_FILE UPDATE_DIR "install.log"

/// Runs argv (absolute path, no shell); returns the exit code, -1 on failure.
static int run(const char *const argv[]) {
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        execv(argv[0], (char *const *)argv);
        _exit(127);
    }
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

/// Like run(), keeping the first `size - 1` bytes of its standard output in `out`.
static int capture(const char *const argv[], char *out, size_t size) {
    int fd[2];
    out[0] = 0;
    if (pipe(fd) != 0) return -1;
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        dup2(fd[1], STDOUT_FILENO);
        close(fd[0]);
        close(fd[1]);
        execv(argv[0], (char *const *)argv);
        _exit(127);
    }
    close(fd[1]);
    size_t used = 0;
    ssize_t n;
    while (used < size - 1 && (n = read(fd[0], out + used, size - 1 - used)) > 0) used += (size_t)n;
    out[used] = 0;
    close(fd[0]);
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: tmupdate <file.deb>\n");
        return 2;
    }
    // Compare resolved paths: on iOS /var is a link to /private/var
    char path[PATH_MAX], dir[PATH_MAX];
    struct stat st;
    if (!realpath(UPDATE_DIR, dir)) {
        fprintf(stderr, "tmupdate: %s is missing\n", UPDATE_DIR);
        return 3;
    }
    strncat(dir, "/", sizeof dir - strlen(dir) - 1);
    if (!realpath(argv[1], path) || strncmp(path, dir, strlen(dir)) != 0 || stat(path, &st) != 0 || !S_ISREG(st.st_mode)) {
        fprintf(stderr, "tmupdate: the package must be a file in %s\n", UPDATE_DIR);
        return 3;
    }
    char name[256];
    const char *field[] = {"/usr/bin/dpkg-deb", "-f", path, "Package", NULL};
    if (capture(field, name, sizeof name) != 0) {
        fprintf(stderr, "tmupdate: not a valid package\n");
        return 4;
    }
    name[strcspn(name, "\r\n")] = 0;
    if (strcmp(name, PACKAGE) != 0) {
        fprintf(stderr, "tmupdate: refusing package \"%s\" (only %s)\n", name, PACKAGE);
        return 5;
    }
    if (setgid(0) != 0 || setuid(0) != 0) {
        fprintf(stderr, "tmupdate: not setuid root (reinstall the package from Cydia)\n");
        return 6;
    }

    // Detach: the app that started us is killed when dpkg replaces it
    pid_t pid = fork();
    if (pid < 0) return 7;
    if (pid > 0) return 0;
    setsid();
    signal(SIGHUP, SIG_IGN);
    int devnull = open("/dev/null", O_RDONLY);
    int log = open(LOG_FILE, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (devnull >= 0) dup2(devnull, STDIN_FILENO);
    if (log >= 0) {
        dup2(log, STDOUT_FILENO);
        dup2(log, STDERR_FILENO);
        fchown(log, st.st_uid, st.st_gid); // readable / removable by the app
    }
    setenv("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", 1);
    sleep(1); // let the app show its message
    printf("installing %s\n", path);
    fflush(stdout);
    const char *dpkg[] = {"/usr/bin/dpkg", "-i", path, NULL};
    int rc = run(dpkg);
    printf("dpkg exit %d\n", rc);
    fflush(stdout);
    if (rc != 0) return rc;
    unlink(path);
    sleep(1);
    const char *respring[] = {"/usr/bin/killall", "-9", "SpringBoard", NULL};
    run(respring);
    return 0;
}
