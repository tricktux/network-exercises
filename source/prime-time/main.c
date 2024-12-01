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

int handle_request(struct queue *sdq, int fd, char* raw_req, size_t size)
{
  assert(fd > 0);
  assert(sdq != NULL);
  assert(raw_req != NULL);
  if (size == 0) {
    log_error("handle_request: raw request size is zero");
    return 1;
  }

  // Split and handle requests here
  struct is_prime_request *req = NULL;
  int r = is_prime_request_builder(sdq, &req, raw_req, size);
  if (r <= 0) {
    log_warn("recv_and_handle: is_prime_request_builder returned '%d'", r);
    return -1;
  }

  /*int l = 0, sl = 0, res = 0, mal = 0;*/
  /*for (it = req; it != NULL; it = it->next) {*/
  /*  l = (int)strlen(it->response);*/
  /*  sl = l;*/
  /*  res = sendall(fd, it->response, &l);*/
  /*  if (res != 0) {*/
  /*    log_error("handle_request: failed during sendall function");*/
  /*    if (req != NULL)*/
  /*      is_prime_free(&req);*/
  /*    return -2;*/
  /*  }*/
  /*  if (sl != l) {*/
  /*    log_error("handle_request: failed to sendall the data");*/
  /*    if (req != NULL)*/
  /*      is_prime_free(&req);*/
  /*    return -3;*/
  /*  }*/
  /**/
  /*  if (it->is_malformed) {*/
  /*    mal = 1;*/
  /*    break;*/
  /*  }*/
  /*}*/

  if (req != NULL)
    is_prime_free(&req);
  return 1;
  /*return (mal == 1 ? 0 : 1);*/
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
  struct queue* rcqu = NULL, *sdqu = NULL;
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

      // Echo data now then while there is any
      log_trace("main epoll loop: handling POLLIN event on fd '%d'", fd);
      res = recv_request(fd, rcqu);
      size = queue_pop_no_copy(rcqu, &data);

      // Handle error case while recv data
      if (res < -1) {
        if (fd_poll_del_and_close(&epci) == -1) {
          perror("epoll_ctl: recv 0");
          exit(EXIT_FAILURE);
        }

        continue;
      }

      // Handle there's data to process
      if (size > 0) {
        log_trace("main epoll loop: raw request(%d): '%s'", fd, data);
        int result = handle_request(sdqu, fd, data, (size_t)size);
        if (result <= 0) {
          if (result == 0)
            log_info("main epoll loop: there was a malformed respoonse. need to close socket");
          else
            log_info("main epoll loop: there was an error sending a response. need to close socket");
          if (fd_poll_del_and_close(&epci) == -1) {
            perror("epoll_ctl: recv 0");
            exit(EXIT_FAILURE);
          }
          continue;
        }
        size = queue_pop_no_copy(sdqu, &data);
        res = sendall(fd, data, &size);
        if (res != 0) {
          log_error("handle_request: failed during sendall function");
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
