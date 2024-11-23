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
#include "utils/queue.h"
#include "utils/sockets.h"
#include "prime-time/is-prime-request.h"
#include "utils/utils.h"

#define LOG_FILE "/tmp/network-exercises-prime-time.log"
#define LOG_FILE_MODE "w"
#define LOG_LEVEL 0  // TRACE

#define QUEUE_CAPACITY 65536  //  1024 * 64
#define MAX_NUM_CON 10
#define MAX_EVENTS 10
#define PORT "18898"

void handle_request(struct queue* qu)
{
  assert(qu != NULL);
  // TODO: queue_is_empty

  size_t size = qu->size;
  char raw_req[size];
  queue_pop(qu, raw_req, &size);

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

int main()
{
  FILE* log_fd = NULL;
  int listen_fd;

  if ((log_fd = fopen(LOG_FILE, LOG_FILE_MODE)) == NULL) {
    printf("Cannot open log file\n");
    exit(EXIT_FAILURE);
  }

  if (init_logs(log_fd, LOG_LEVEL) != 0)
    exit(EXIT_FAILURE);

  if (create_server(PORT, &listen_fd) != 0) {
    fprintf(stderr, "failed to create server\n");
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

  char* data;
  int n, fd, res, size;
  struct epoll_ctl_info epci = {epollfd, 0, 0};
  struct queue* qu = nullptr;
  queue_init(&qu, QUEUE_CAPACITY);

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
      res = recv_request(fd, qu);
      size = queue_pop_no_copy(qu, &data);

      // Handle error case while recv data
      if (res < -1) {
        if (fd_poll_del_and_close(&epci) == -1) {
          perror("epoll_ctl: recv 0");
          exit(EXIT_FAILURE);
        }

        continue;
      }

      // Handle there's data to echo back
      if (size > 0) {
        int nbytes = size;
        if (sendall(fd, data, &size) != 0) {
          log_error("recv_echo: sending data on fd '%d'", fd);
          continue;
        }
        if (nbytes != size) {
          log_error("recv_echo: Expected to send: '%u'. Actually sent: '%u'",
                    nbytes,
                    size);
        }
      }

      // Handle socket still open
      if (res == -1)
        continue;

      // Handle closing request received
      if (fd_poll_del_and_close(&epci) == -1) {
        perror("epoll_ctl: recv 0");
        exit(EXIT_FAILURE);
      }
    }
  }
  printf("Hello world\n");
}
