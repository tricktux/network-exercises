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
#include "utils/epoll.h"
#include "utils/utils.h"
#include "prime-time/is-prime-request.h"

#define LOG_FILE "/tmp/network-exercises-prime-time.log"
#define LOG_FILE_MODE "w"
#define LOG_LEVEL 0  // TRACE

#define MAX_NUM_CON 10
#define MAX_EVENTS 10
#define PORT "18898"

void handle_request(char* raw_req, size_t size)
{
  assert(raw_req != NULL);
  assert(size > 0);

  // Split and handle requests here
  struct is_prime_request *req, *it;
  int r = is_prime_request_builder(&req, raw_req, size);
  if (r < 0) {
    log_warn("recv_and_handle: is_prime_request_builder returned '%d'", r);
    return;
  }
  for (it = req; it != NULL; it = it->next) {
    r = is_prime_request_malformed(it);
    if (r < 0) {
      log_warn("recv_and_handle: is_prime_request_malformed returned '%d'", r);
      // TODO: what else to do here
    }
    if (r == 0) {
      r = is_prime(it);
      if (r < 0) {
        log_warn("recv_and_handle: is_prime returned '%d'", r);
        // TODO: what else to do here
      }
    }
    r = is_prime_beget_response(it);
    if (r < 0) {
      log_warn("recv_and_handle: is_prime returned '%d'", r);
      // TODO: what else to do here
    }
  }
}

void recv_and_handle(struct epoll_ctl_info* ctx)
{
  assert(ctx != NULL);

  char buf[8192];
  ssize_t nbytes, tot_size = 0, capacity = 8192;

  for (;;) {
    nbytes = recv(ctx->new_fd, buf, sizeof buf, 0);
    if (nbytes == 0) {
      log_warn("recv_and_handle: handling close while reading on fd '%d'",
               ctx->new_fd);
      if (fd_poll_del_and_close(ctx) == -1) {
        perror("epoll_ctl: recv 0");
        exit(EXIT_FAILURE);
      }
      break;
    }

    if (nbytes == -1) {
      if ((errno == EAGAIN) || (errno == EWOULDBLOCK)) {
        handle_request(buf, nbytes);
        break;  // We are done reading from this socket
      }

      log_trace("recv_and_handle: handling error while recv on fd '%d'",
                ctx->new_fd);
      if (fd_poll_del_and_close(ctx) == -1) {
        perror("epoll_ctl: read(fd)");
      }
      break;
    }
    log_trace(
        "recv_and_handle: read '%d' bytes from fd '%d'", nbytes, ctx->new_fd);
    tot_size += nbytes;
  }
}

int main()
{
  FILE* log_fd = NULL;
  int listen_fd, s;
  struct addrinfo hints;
  struct addrinfo *result, *rp;

  if ((log_fd = fopen(LOG_FILE, LOG_FILE_MODE)) == NULL) {
    printf("Cannot open log file\n");
    exit(EXIT_FAILURE);
  }

  if (init_logs(log_fd, LOG_LEVEL) != 0)
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

  int n, fd;
  struct epoll_ctl_info epci = {epollfd, 0, 0};

  for (;;) {
    log_trace("main epoll loop: epoll listening...");
    nfds = epoll_wait(epollfd, events, MAX_EVENTS, -1);
    if (nfds == -1) {
      perror("epoll_wait\n");
      exit(EXIT_FAILURE);
    }

    log_trace("main epoll loop: epoll got '%d' events", nfds);
    for (n = 0; n < nfds; ++n) {
      epci.new_fd = events[n].data.fd;
      fd = events[n].data.fd;
      epci.event = &events[n];

      // Handle a new listen connection
      if (events[n].data.fd == listen_fd) {
        fd_accept_and_epoll_add(&epci);
        continue;
      }

      // Echo data now then while there is any
      log_trace("main epoll loop: handling POLLIN event on fd '%d'", fd);
      recv_and_handle(&epci);
    }
  }
  printf("Hello world\n");
}
