#define _POSIX_C_SOURCE 200112L
#define _GNU_SOURCE

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
#define PORT "18888"

int handle_request(struct queue* sdq, char* raw_req, size_t size)
{
  assert(sdq != NULL);
  assert(raw_req != NULL);
  if (size == 0) {
    log_error("handle_request: raw request size is zero");
    return 1;
  }

  // Split and handle requests here
  bool mal = false;
  int r = is_prime_request_builder(sdq, raw_req, size, &mal);
  if (r <= 0) {
    log_warn("recv_and_handle: is_prime_request_builder returned '%d'", r);
    return -1;
  }

  return (mal ? 0 : 1);
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

  char *data, *sddata, *complete_req;
  int n, fd, res, size, sdsize, rs, result;
  struct epoll_ctl_info epci = {epollfd, 0, 0};
  struct queue *rcqu = NULL, *sdqu = NULL;
  queue_init(&rcqu, QUEUE_CAPACITY);
  queue_init(&sdqu, QUEUE_CAPACITY);

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

      // Receive all the data into the queue
      res = recv_request(fd, rcqu);
      log_trace(
          "main epoll loop: handling POLLIN event on fd '%d' with res: '%d'",
          fd,
          res);

      // Handle error case while recv data
      if (res < -1) {
        log_error("main epoll loop: error while receiving data");
        if (fd_poll_del_and_close(&epci) == -1) {
          perror("epoll_ctl: recv 0");
          exit(EXIT_FAILURE);
        }

        continue;
      }

      // Peek at the data to check if we have at least one complete request
      complete_req = NULL;
      size = queue_peek(rcqu, &data);
      if (size > 0) {
        complete_req = (char*)memrchr(data, PRIME_REQUEST_DELIMITERS[0], size);
        log_trace("main epoll loop: complete_req = '%d'",
                  (complete_req == NULL ? 0 : 1));
      }

      // If we do, process it
      if (complete_req != NULL) {
        size = queue_pop_no_copy(rcqu, &data);
        log_trace(
            "main epoll loop: raw request: fd: '%d', size: '%d', data: '%s'",
            fd,
            size,
            data);
        rs = 0;
        result = handle_request(sdqu, data, (size_t)size);
        sdsize = queue_pop_no_copy(sdqu, &sddata);
        if (sdsize > 0)
          rs = sendall(fd, sddata, &sdsize);

        if ((result <= 0) || (rs != 0)) {
          if (result == 0)
            log_info(
                "main epoll loop: there was a malformed respoonse. need to "
                "close socket");
          else if (result < 0)
            log_info(
                "main epoll loop: there was an error handling the request. "
                "need to close socket");
          else if (rs != 0)
            log_error("main epoll loop:: failed during sendall function");
          if (fd_poll_del_and_close(&epci) == -1) {
            perror("epoll_ctl: recv 0");
            exit(EXIT_FAILURE);
          }
          continue;
        }
      }

      // Handle socket still open
      if (res == -1)
        continue;

      // Handle closing request received
      log_info("main epoll loop:: closing connection");
      if (fd_poll_del_and_close(&epci) == -1) {
        perror("epoll_ctl: recv 0");
        exit(EXIT_FAILURE);
      }
    }
  }
  printf("Hello world\n");
}
