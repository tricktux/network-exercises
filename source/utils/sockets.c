
#define _POSIX_C_SOURCE 200112L

#include <assert.h>
#include <errno.h>
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

int sendall(int sfd, char* buf, int* len)
{
  assert(sfd != 0);
  assert(buf != NULL);
  assert(*len > 0);

  long nbytes_sent = 0;
  int total_to_send = *len, total_sent = 0;

  for (; nbytes_sent < total_to_send;) {
    nbytes_sent = send(sfd, buf, (size_t)total_to_send, 0);
    if (nbytes_sent == -1) {
      int err = errno;
      *len = total_sent;
      log_error("sendall: send failed, '%d'", err);
      return err;
    }

    total_to_send -= (int)nbytes_sent;
    buf += nbytes_sent;
    total_sent += (int)nbytes_sent;
    log_trace(
        "sendall: in the loop nbytes_sent: '%d', total_to_send: '%u', "
        "total_sent: '%u'",
        nbytes_sent,
        total_to_send,
        total_sent);
  }

  *len = total_sent;
  log_trace("sendall: done: len = '%u'", *len);
  return 0;
}

int create_server(const char* port, int* listen_fd)
{
  assert(port != NULL);
  assert(listen_fd != NULL);

  struct addrinfo hints;
  struct addrinfo* result = NULL;
  // getaddrinfo
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC; /* Allow IPv4 or IPv6 */
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_PASSIVE; /* For wildcard IP address */
  hints.ai_protocol = 0; /* Any protocol */
  hints.ai_canonname = NULL;
  hints.ai_addr = NULL;
  hints.ai_next = NULL;

  int s = getaddrinfo(NULL, port, &hints, &result);
  if (s != 0) {
    fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(s));
    return -1;
  }

  int fd;
  struct addrinfo* rp;
  log_trace("main: passed getaddrinfo");
  for (rp = result; rp != NULL; rp = rp->ai_next) {
    fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
    if (fd == -1)
      continue;

    if (bind(fd, rp->ai_addr, rp->ai_addrlen) == 0) {
      log_info("main results loop: we binded to port '%s' baby!!!", port);
      break; /* Success */
    }

    close(fd);
  }

  freeaddrinfo(result); /* No longer needed */
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
