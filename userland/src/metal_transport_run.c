/* Temporary on-device runner for roadmap task 5. No launchd or boot changes.
 * Paused mode stops the UI's producers and compositor, preserving their state.
 * An independent watchdog resumes them even if this runner is killed. */
#include <sys/types.h>
#include <sys/sysctl.h>
#include <sys/proc.h>
#include <sys/wait.h>
#include <mach/mach.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static pid_t ui[2];
static void resume_ui(void) {
    for (int i = 1; i >= 0; i--) if (ui[i] > 0) kill(ui[i], SIGCONT);
}
static int find_ui(void) {
    int mib[] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0)) return 1;
    len *= 2;
    struct kinfo_proc *p = malloc(len);
    if (!p || sysctl(mib, 4, p, &len, NULL, 0)) { free(p); return 1; }
    for (size_t i = 0; i < len / sizeof(*p); i++) {
        for (int j = 0; j < 2; j++) {
            if (!strcmp(p[i].kp_proc.p_comm, j ? "backboardd" : "SpringBoard")) {
                if (p[i].kp_proc.p_stat == SSTOP) { free(p); return 1; }
                ui[j] = p[i].kp_proc.p_pid;
            }
        }
    }
    free(p);
    return !ui[0] || !ui[1];
}
static int states(int paused) {
    for (int i = 0; i < 2; i++) {
        int mib[] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, ui[i] };
        struct kinfo_proc p;
        size_t len = sizeof(p);
        if (sysctl(mib, 4, &p, &len, NULL, 0) || len != sizeof(p)) return 1;
        printf("runner: %s pid=%d state=%d expected=%s\n", i ? "backboardd" : "SpringBoard",
               ui[i], p.kp_proc.p_stat, paused ? "stopped" : "running/sleeping");
        if ((p.kp_proc.p_stat == SSTOP) != paused) return 1;
    }
    return 0;
}
static void memory(void) {
    vm_statistics64_data_t s;
    mach_msg_type_number_t n = HOST_VM_INFO64_COUNT;
    mach_port_t host = mach_host_self();
    if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&s, &n) == KERN_SUCCESS)
        printf("runner: wired_pages=%u (system-wide observation)\n", s.wire_count);
    mach_port_deallocate(mach_task_self(), host);
}
int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if ((argc != 4 && argc != 5) || (argc == 5 && strcmp(argv[4], "compute")) || (strcmp(argv[1], "paused") && strcmp(argv[1], "live"))) {
        fprintf(stderr, "usage: metal_transport_run paused|live PROBE REPETITIONS [compute]\n");
        return 2;
    }
    int compute = argc == 5;
    int paused = !strcmp(argv[1], "paused"), count = atoi(argv[3]);
    if (count < 1 || count > 20 || find_ui()) return 2;
    printf("runner: mode=%s repetitions=%d\n", argv[1], count);
    pid_t watchdog = -1;
    if (paused) {
        watchdog = fork();
        if (watchdog < 0) return 2;
        if (watchdog == 0) {
            sleep(20);
            resume_ui();
            fprintf(stderr, "runner: watchdog resumed UI\n");
            _exit(124);
        }
        for (int i = 0; i < 2; i++) {
            if (kill(ui[i], SIGSTOP)) { resume_ui(); kill(watchdog, SIGKILL); return 2; }
        }
        usleep(100000);
    }
    int failures = states(paused);
    memory();
    for (int i = 0; i < count && !failures; i++) {
        printf("runner: iteration=%d suite=%s\n", i + 1, compute ? "compute" : "stages=1-4");
        pid_t child = fork();
        if (child == 0) {
            if (compute) execl(argv[2], argv[2], "--compute-only", "--transport-audit", NULL);
            else execl(argv[2], argv[2], "--stages", "4", "--transport-audit", NULL);
            _exit(127);
        }
        int status = 0;
        if (child < 0 || waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status)) failures++;
        memory();
    }
    failures += states(paused);
    if (paused) {
        resume_ui();
        kill(watchdog, SIGKILL);
        waitpid(watchdog, NULL, 0);
        usleep(100000);
        failures += states(0);
    }
    printf("runner: %s failures=%d\n", failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
