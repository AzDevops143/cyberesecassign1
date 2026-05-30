#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/socket.h>
#include <linux/if_alg.h>
#include <string.h>
#include <errno.h>

/* 
 * Hexa Force - Copy Fail (CVE-2026-31431) Structural Analysis Tool
 * 
 * This tool demonstrates the initial vector for the 2026 AF_ALG 
 * kernel crypto API vulnerability. It attempts to open an AF_ALG 
 * socket and bind to the vulnerable `aead` (algif_aead) module.
 */

#ifndef AF_ALG
#define AF_ALG 38
#endif

int main(int argc, char **argv) {
    printf("[*] Hexa Force: Initiating Copy Fail (CVE-2026-31431) Vector...\n");
    printf("[*] Attempting to create AF_ALG (Userspace Crypto) socket...\n");

    // 1. Create the AF_ALG socket
    int alg_fd = socket(AF_ALG, SOCK_SEQPACKET, 0);
    if (alg_fd < 0) {
        if (errno == EPERM) {
            printf("[+] BLOCKED by SECCOMP: socket(AF_ALG) returned EPERM (Operation not permitted).\n");
            printf("[+] Hexa Force Mitigation successful. CVE-2026-31431 neutralized!\n");
            return EXIT_SUCCESS;
        } else if (errno == EAFNOSUPPORT) {
            printf("[-] Kernel does not support AF_ALG (Expected on some WS2 environments).\n");
            return EXIT_FAILURE;
        }
        perror("[!] socket() failed");
        return EXIT_FAILURE;
    }

    printf("[!] WARNING: AF_ALG socket created successfully! Container is exposed.\n");

    // 2. Bind to the vulnerable 'aead' module
    struct sockaddr_alg salg = {
        .salg_family = AF_ALG,
        .salg_type = "aead",
        .salg_name = "gcm(aes)" // Typical target cipher
    };

    printf("[*] Attempting to bind to vulnerable algif_aead module...\n");
    if (bind(alg_fd, (struct sockaddr *)&salg, sizeof(salg)) < 0) {
        perror("[-] bind() failed");
        close(alg_fd);
        return EXIT_FAILURE;
    }

    printf("[!] CRITICAL: Bound to 'aead' module successfully.\n");
    printf("[!] The container is structurally vulnerable to CVE-2026-31431 page cache corruption!\n");
    
    close(alg_fd);
    return EXIT_SUCCESS;
}
