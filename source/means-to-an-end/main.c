#define _POSIX_C_SOURCE 200112L
#define _GNU_SOURCE

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
#include "utils/epoll.h"
#include "utils/queue.h"
#include "utils/sockets.h"
#include "utils/utils.h"

#include "means-to-an-end/client-session.h"
#include "means-to-an-end/messages.h"

#define EPOLL_WAIT_TIMEOUT 15 * 1000

#define LOG_FILE "/tmp/network-exercises-means-to-an-end.log"
#define LOG_FILE_MODE "w"
#define LOG_LEVEL 0  // TRACE


#define QUEUE_CAPACITY 65536  //  1024 * 64
#define MAX_NUM_CON 10
#define MAX_EVENTS 10
#define PORT "18888"

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

  bool complete_req = false, client_found = false;
  char *data, *sddata;
  int n, fd, res, size, sdsize, rs;
  struct epoll_ctl_info epci = {epollfd, 0, 0};
  struct queue *sdqu = NULL;
  struct clients_session *ca = NULL;
  queue_init(&sdqu, QUEUE_CAPACITY);

  for (;;) {
    log_trace("main epoll loop: epoll listening...");
    nfds = epoll_wait(epollfd, events, MAX_EVENTS, EPOLL_WAIT_TIMEOUT);
    if (nfds == -1) {
      perror("epoll_wait\n");
      exit(EXIT_FAILURE);
    }

    if (nfds == 0) {
      log_error("main epoll loop: timeout hit. cleanup time...");
      close(epollfd);
      close(listen_fd);
      queue_free(&sdqu);
      if (ca != NULL)
        clients_session_free_all(&ca);
      exit(EXIT_SUCCESS);
    }

    log_trace("main epoll loop: epoll got '%d' events", nfds);
    for (n = 0; n < nfds; ++n) {
      epci.new_fd = events[n].data.fd;
      fd = events[n].data.fd;
      epci.event = &events[n];

      // Handle a new listen connection
      if (events[n].data.fd == listen_fd) {
        int new_fd = fd_accept_and_epoll_add(&epci);
        clients_session_add(&ca, new_fd);
        continue;
      }

      // Receive all the data into the queue
      client_found = clients_session_find(&ca, fd);
      assert(client_found);
      res = recv_request(fd, ca->recv_qu);
      log_trace(
          "main epoll loop: handling POLLIN event on fd '%d' with res: '%d'",
          fd,
          res);

      // Handle error case while recv data
      if (res < -1) {
        log_error("main epoll loop: error while receiving data");
        clients_session_remove(&ca, fd);
        if (fd_poll_del_and_close(&epci) == -1) {
          perror("epoll_ctl: recv 0");
          exit(EXIT_FAILURE);
        }

        continue;
      }

      // Peek at the data to check if we have at least one complete request
      complete_req = false;
      size = queue_peek(ca->recv_qu, &data);
      if ((size > 0) && (size % MESSAGE_SIZE == 0)) {
        complete_req = true;
        log_trace("main epoll loop: complete_req = '%d'",
                  (complete_req ? 1 : 0));
      }

      // If we do, process itl
      if (complete_req) {
        size = queue_pop_no_copy(ca->recv_qu, &data);
        log_trace(
            "main epoll loop: raw request: fd: '%d', size: '%d'",
            fd,
            size);

        message_parse(ca->asset, sdqu, data, (size_t) size);
        sdsize = queue_pop_no_copy(sdqu, &sddata);
        if (sdsize > 0) {
          rs = sendall(fd, sddata, &sdsize);
          if (rs != 0) {
            log_error("main epoll loop:: failed during sendall function");
            clients_session_remove(&ca, fd);
            if (fd_poll_del_and_close(&epci) == -1) {
              perror("epoll_ctl: recv 0");
              exit(EXIT_FAILURE);
            }
            continue;
          }
        }
      }

      // Handle socket still open
      if (res == -1)
        continue;

      // Handle closing request received
      log_info("main epoll loop:: closing connection");
      clients_session_remove(&ca, fd);
      if (fd_poll_del_and_close(&epci) == -1) {
        perror("epoll_ctl: recv 0");
        exit(EXIT_FAILURE);
      }
    }
  }
  printf("Hello world\n");
}
