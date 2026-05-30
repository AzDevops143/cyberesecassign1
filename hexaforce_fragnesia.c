#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <string.h>
#include <errno.h>

/* 
 * Hexa Force - Fragnesia (CVE-2026-46300) Structural Analysis Tool
 * 
 * Demonstrates the structural attack vector for the 2026 Fragnesia
 * vulnerability, which exploits the ESP-in-TCP subsystem to corrupt
 * the page cache.
 */

#ifndef TCP_ULP
#define TCP_ULP 31
#endif

int main(int argc, char **argv) {
    printf("[*] Hexa Force: Initiating Fragnesia (CVE-2026-46300) Vector...\n");
    printf("[*] Attempting to create TCP socket and attach 'esp' ULP...\n");

    // 1. Create the TCP socket
    int sock_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (sock_fd < 0) {
        perror("[!] socket() failed");
        return EXIT_FAILURE;
    }

    // 2. Attempt to attach the ESP Upper Layer Protocol (ULP)
    const char *ulp_name = "esp";
    printf("[*] Calling setsockopt(TCP_ULP, 'esp')...\n");
    if (setsockopt(sock_fd, IPPROTO_TCP, TCP_ULP, ulp_name, strlen(ulp_name)) < 0) {
        if (errno == EPERM) {
            printf("[+] BLOCKED by SECCOMP: setsockopt(TCP_ULP) returned EPERM.\n");
            printf("[+] Hexa Force Mitigation successful. CVE-2026-46300 neutralized!\n");
            close(sock_fd);
            return EXIT_SUCCESS;
        } else if (errno == ENOENT || errno == EOPNOTSUPP) {
            printf("[-] Kernel does not have the 'esp' ULP module loaded (Expected on some hosts).\n");
            close(sock_fd);
            return EXIT_FAILURE;
        }
        perror("[!] setsockopt() failed");
        close(sock_fd);
        return EXIT_FAILURE;
    }

    printf("[!] WARNING: TCP_ULP 'esp' attached successfully! Container is exposed.\n");
    printf("[!] The container is structurally vulnerable to CVE-2026-46300 ESP-in-TCP page cache corruption!\n");
    
    close(sock_fd);
    return EXIT_SUCCESS;
}
