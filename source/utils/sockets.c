
#define _POSIX_C_SOURCE 200112L

#include <assert.h>
#include <fcntl.h>
#include <netdb.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdatomic.h>

#include "log/log.h"

#define MAX_NUM_CON 10
#define MAX_EVENTS 10

int create_server(struct addrinfo hints, const char *port, struct addrinfo **result, int *listen_fd) {
  assert(port != NULL);
  assert(result != NULL);
  assert(listen_fd != NULL);

  int s = getaddrinfo(NULL, port, &hints, result);
  if (s != 0) {
    fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(s));
    return -1;
  }

  int fd;
  struct addrinfo *rp;
  log_trace("main: passed getaddrinfo");
  for (rp = *result; rp != NULL; rp = rp->ai_next) {
    fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
    if (fd == -1)
      continue;

    if (bind(fd, rp->ai_addr, rp->ai_addrlen) == 0) {
      log_info("main results loop: we binded to port '%s' baby!!!", port);
      break; /* Success */
    }

    close(fd);
  }

  freeaddrinfo(*result); /* No longer needed */
  log_trace("main: freeaddrinfo");

  if (rp == NULL) { /* No address succeeded */
    fprintf(stderr, "Could not bind\n");
    return -1;
  }

  if (listen(fd, MAX_NUM_CON) == -1) {
    perror("listen failed\n");
    return -2;
  }

  *listen_fd = fd;
  return 0;
}

