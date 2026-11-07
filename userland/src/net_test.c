/*
 * net_test: is there internet, without Safari? A name looked up (getaddrinfo: mDNSResponder, the DNS
 * configd was given), a TCP connection to port 80, one HTTP request, the first line of the answer.
 * Each step says how long it took. Run through sweetd: /usr/local/bin/net_test [HOST [PATH]].
 * (Wi-Fi step 3, 2026-11-07: Safari froze while the Wi-Fi link carried data.)
 */
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static double
now(void)
{
	struct timeval tv;

	gettimeofday(&tv, NULL);
	return tv.tv_sec + tv.tv_usec / 1e6;
}

int
main(int argc, char **argv)
{
	const char *host = argc > 1 ? argv[1] : "captive.apple.com";
	const char *path = argc > 2 ? argv[2] : "/hotspot-detect.html";
	struct addrinfo hints, *res = NULL, *ai;
	struct timeval tmo = { 10, 0 };
	char request[512], answer[512], addr[64];
	double t0 = now();
	int e, s = -1;
	ssize_t n;

	memset(&hints, 0, sizeof(hints));
	hints.ai_family = AF_INET;
	hints.ai_socktype = SOCK_STREAM;
	e = getaddrinfo(host, "80", &hints, &res);
	if (e != 0) {
		printf("net_test: lookup of %s: FAILED (%s) after %.2f s\n", host, gai_strerror(e), now() - t0);
		return 1;
	}
	printf("net_test: lookup of %s: ok after %.2f s\n", host, now() - t0);
	for (ai = res; ai != NULL; ai = ai->ai_next) {
		double t1 = now();

		inet_ntop(AF_INET, &((struct sockaddr_in *)ai->ai_addr)->sin_addr, addr, sizeof(addr));
		s = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
		if (s < 0) {
			continue;
		}
		setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tmo, sizeof(tmo));
		setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tmo, sizeof(tmo));
		if (connect(s, ai->ai_addr, ai->ai_addrlen) == 0) {
			printf("net_test: TCP to %s port 80: connected after %.2f s\n", addr, now() - t1);
			break;
		}
		printf("net_test: TCP to %s port 80: FAILED (%s) after %.2f s\n", addr, strerror(errno), now() - t1);
		close(s);
		s = -1;
	}
	freeaddrinfo(res);
	if (s < 0) {
		return 2;
	}
	snprintf(request, sizeof(request), "GET %s HTTP/1.0\r\nHost: %s\r\nUser-Agent: net_test\r\n\r\n", path, host);
	if (write(s, request, strlen(request)) < 0) {
		printf("net_test: request: FAILED\n");
		return 3;
	}
	n = read(s, answer, sizeof(answer) - 1);
	if (n <= 0) {
		printf("net_test: answer: none (%zd) after %.2f s in all\n", n, now() - t0);
		return 4;
	}
	answer[n] = 0;
	answer[strcspn(answer, "\r\n")] = 0;
	printf("net_test: answer: \"%s\" (%zd bytes first) after %.2f s in all\n", answer, n, now() - t0);
	close(s);
	return 0;
}
