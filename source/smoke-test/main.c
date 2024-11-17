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

#include "log.h"
#include "epoll.h"

#define LOG_FILE "/tmp/network-exercises-smoke-test.log"
#define LOG_FILE_MODE "w"
#define LOG_LEVEL 0  // TRACE

#define MAX_NUM_CON 10
#define MAX_EVENTS 10
#define BUF_SIZE 1024
#define PORT "18888"

int init_logs(FILE* fd)
{
  if ((fd = fopen(LOG_FILE, LOG_FILE_MODE)) == NULL) {
    printf("Cannot open log file\n");
    exit(EXIT_FAILURE);
  }

  if (log_add_fp(fd, LOG_LEVEL) == -1) {
    printf("Failed to initialize log file\n");
    return -2;
  }

  log_set_level(LOG_LEVEL);

  return 0;
}

int sendall(int sfd, char* buf, ssize_t* len)
{
  assert(sfd != 0);
  assert(buf != NULL);
  assert(*len > 0);

  ssize_t nbytes_sent = 0;
  ssize_t total_to_send = *len, total_sent = 0;

  for (; nbytes_sent < total_to_send;) {
    nbytes_sent = send(sfd, buf, (size_t)total_to_send, 0);
    if (nbytes_sent == -1) {
      int err = errno;
      *len = total_sent;
      log_error("sendall: send failed, '%d'", err);
      return err;
    }

    total_to_send -= nbytes_sent;
    buf += nbytes_sent;
    total_sent += nbytes_sent;
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

int main()
{
  FILE* log_fd = NULL;
  int listen_fd, s;
  struct addrinfo hints;
  struct addrinfo *result, *rp;

  if (init_logs(log_fd) != 0)
    exit(EXIT_FAILURE);

  // getaddrinfo
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC; /* Allow IPv4 or IPv6 */
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_PASSIVE; /* For wildcard IP address */
  hints.ai_protocol = 0; /* Any protocol */
  hints.ai_canonname = NULL;
  hints.ai_addr = NULL;
  hints.ai_next = NULL;

  s = getaddrinfo(NULL, PORT, &hints, &result);
  if (s != 0) {
    fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(s));
    exit(EXIT_FAILURE);
  }

  log_trace("main: passed getaddrinfo");
  for (rp = result; rp != NULL; rp = rp->ai_next) {
    log_trace("main results loop: trying with addrinfo '%d'", rp - result);

    listen_fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
    if (listen_fd == -1)
      continue;

    if (bind(listen_fd, rp->ai_addr, rp->ai_addrlen) == 0) {
      log_info("main results loop: we binded to port '%s' baby!!!", PORT);
      break; /* Success */
    }

    close(listen_fd);
  }

  freeaddrinfo(result); /* No longer needed */
  log_trace("main: freeaddrinfo");

  if (rp == NULL) { /* No address succeeded */
    fprintf(stderr, "Could not bind\n");
    exit(EXIT_FAILURE);
  }

  if (listen(listen_fd, MAX_NUM_CON) == -1) {
    perror("listen failed\n");
    exit(EXIT_FAILURE);
  }
  log_trace("main: listening...");

  struct epoll_event ev, events[MAX_EVENTS];
  int nfds, epollfd;

  epollfd = epoll_create1(0);
  if (epollfd == -1) {
    perror("epoll_create1 failed\n");
    exit(EXIT_FAILURE);
  }
  log_trace("main: epoll created...");

  ev.events = EPOLLIN | EPOLLRDHUP;
  ev.data.fd = listen_fd;
  if (epoll_ctl(epollfd, EPOLL_CTL_ADD, listen_fd, &ev) == -1) {
    perror("epoll_ctl: listen_fd\n");
    exit(EXIT_FAILURE);
  }

  int n;
  char buf[4096];

  for (;;) {
    log_trace("main epoll loop: epoll listening...");
    nfds = epoll_wait(epollfd, events, MAX_EVENTS, -1);
    if (nfds == -1) {
      perror("epoll_wait\n");
      exit(EXIT_FAILURE);
    }

    log_trace("main epoll loop: epoll got '%d' events", nfds);
    for (n = 0; n < nfds; ++n) {
      if (events[n].data.fd == listen_fd) {
        fd_accept_and_epoll_add(listen_fd, epollfd);
        continue;
      }

      int fd = events[n].data.fd;
      if ((events[n].events & EPOLLIN) == 0) {
        log_warn("main: handling close event on fd '%d'", fd);
        if (fd_poll_del_and_close(epollfd, fd, &events[n]) == -1) {
          perror("epoll_ctl: fd");
          exit(EXIT_FAILURE);
        }
        continue;
      }
      log_trace("main epoll loop: handling POLLIN event on fd '%d'", fd);
      // read while there's data here
      // maybe not, we'll get notified again
      ssize_t nbytes;
      for (;;) {
        nbytes = recv(fd, buf, sizeof buf, 0);
        if (nbytes == 0) {
          log_warn("main: handling close while reading on fd '%d'", fd);
          if (fd_poll_del_and_close(epollfd, fd, &events[n]) == -1) {
            perror("epoll_ctl: recv 0");
            exit(EXIT_FAILURE);
          }
          break;
        }

        if (nbytes == -1) {
          if ((errno == EAGAIN) || (errno == EWOULDBLOCK)) {
            break;  // We are done reading from this socket
          }

          log_trace("main: handling error while recv on fd '%d'", fd);
          if (fd_poll_del_and_close(epollfd, fd, &events[n]) == -1) {
            perror("epoll_ctl: read(fd)");
            exit(EXIT_FAILURE);
          }
          break;
        }
        log_trace("main epoll loop: read '%d' bytes from fd '%d'", nbytes, fd);

        if (sendall(fd, buf, &nbytes) != 0) {
          log_error("main: failed to sendall on fd '%d'", fd);
          if (fd_poll_del_and_close(epollfd, fd, &events[n]) == -1) {
            perror("epoll_ctl: sendall(fd)");
            exit(EXIT_FAILURE);
          }
        }
      }
    }
  }
  printf("Hello world\n");
}
