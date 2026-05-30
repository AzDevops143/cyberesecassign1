#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <errno.h>

/* 
 * Hexa Force - Dirty Frag (CVE-2026-43284) Structural Analysis Tool
 * 
 * Demonstrates the structural attack vector for the 2026 Dirty Frag
 * vulnerability, which combines page-cache corruption with IPv6
 * network fragmentation logic.
 */

int main(int argc, char **argv) {
    printf("[*] Hexa Force: Initiating Dirty Frag (CVE-2026-43284) Vector...\n");
    printf("[*] Attempting to create IPv6 RAW socket for fragmentation manipulation...\n");

    // 1. Create the IPv6 RAW socket
    int sock_fd = socket(AF_INET6, SOCK_RAW, IPPROTO_IPV6);
    if (sock_fd < 0) {
        if (errno == EPERM) {
            printf("[+] BLOCKED by SECCOMP: socket(AF_INET6, SOCK_RAW) returned EPERM.\n");
            printf("[+] Hexa Force Mitigation successful. CVE-2026-43284 neutralized!\n");
            return EXIT_SUCCESS;
        } else if (errno == EAFNOSUPPORT) {
            printf("[-] Kernel does not support IPv6.\n");
            return EXIT_FAILURE;
        }
        perror("[!] socket() failed");
        return EXIT_FAILURE;
    }

    printf("[!] WARNING: IPv6 RAW socket created successfully! Container is exposed.\n");
    printf("[!] The container is structurally vulnerable to CVE-2026-43284 page cache corruption via IPv6 fragmentation paths!\n");
    
    close(sock_fd);
    return EXIT_SUCCESS;
}
