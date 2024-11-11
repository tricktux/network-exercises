#define _POSIX_C_SOURCE 200112L

#include <fcntl.h>
#include <stdarg.h>
#include <netdb.h>
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

#define LOG_FILE "/tmp/network-exercises-smoke-test.log"
#define LOG_FILE_MODE "w"
#define LOG_LEVEL 0  // TRACE

#define MAX_NUM_CON 10
#define MAX_EVENTS 10
#define BUF_SIZE 1024
#define PORT "7"

int init_logs(FILE* fd)
{
  if ((fd = fopen(LOG_FILE, LOG_FILE_MODE)) == NULL) {
    printf("Cannot open log file\n");
    exit(EXIT_FAILURE);
  }

  if (log_add_fp(fd, LOG_LEVEL) == -1) {
    printf("Failed to initalize log file\n");
    return -2;
  }

  log_set_level(LOG_LEVEL);

  return 0;
}

// Create accept function
// Create read and send back function
// How do I know the client finished sending back the data

int main(int argc, char const* argv[])
{
  FILE* log_fd;
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

  log_trace("main (%d): passed getaddrinfo", __LINE__);
  for (rp = result; rp != NULL; rp = rp->ai_next) {

    log_trace("main results loop(%d): trying with addrinfo '%d'", __LINE__, rp - result);

    listen_fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
    if (listen_fd == -1)
      continue;

    if (bind(listen_fd, rp->ai_addr, rp->ai_addrlen) == 0) {
      log_trace("main results loop(%d): we binded baby!!!", __LINE__);
      break; /* Success */
    }

    close(listen_fd);
  }

  freeaddrinfo(result); /* No longer needed */
  log_trace("main (%d): freeaddrinfo", __LINE__);

  if (rp == NULL) { /* No address succeeded */
    fprintf(stderr, "Could not bind\n");
    exit(EXIT_FAILURE);
  }

  if (listen(listen_fd, MAX_NUM_CON) == -1) {
    fprintf(stderr, "listen failed\n");
    exit(EXIT_FAILURE);
  }
  log_trace("main (%d): listening...", __LINE__);

  struct epoll_event ev, events[MAX_EVENTS];
  int conn_sock, nfds, epollfd;

  epollfd = epoll_create1(0);
  if (epollfd == -1) {
    fprintf(stderr, "epoll_create1 failed\n");
    exit(EXIT_FAILURE);
  }
  log_trace("main (%d): epoll created...", __LINE__);

  ev.events = EPOLLIN;
  ev.data.fd = listen_fd;
  if (epoll_ctl(epollfd, EPOLL_CTL_ADD, listen_fd, &ev) == -1) {
    fprintf(stderr, "epoll_ctl: listen_fd\n");
    exit(EXIT_FAILURE);
  }
  log_trace("main (%d): epoll listening...", __LINE__);

  int n;
  socklen_t addrlen;
  struct sockaddr_storage addr;

  for (;;) {
    log_trace("main (%d): epoll listening...", __LINE__);
    nfds = epoll_wait(epollfd, events, MAX_EVENTS, -1);
    if (nfds == -1) {
      fprintf(stderr, "epoll_wait\n");
      exit(EXIT_FAILURE);
    }

    log_trace("main (%d): epoll got '%d' POLLIN events", __LINE__, nfds);
    for (n = 0; n < nfds; ++n) {
      if (events[n].data.fd == listen_fd) {
        log_trace("main (%d): epoll got a 'listen' event", __LINE__);
        conn_sock = accept(listen_fd, (struct sockaddr*)&addr, &addrlen);
        if (conn_sock == -1) {
          fprintf(stderr, "accept\n");
          exit(EXIT_FAILURE);
        }
        fcntl(conn_sock, F_SETFL, O_NONBLOCK);
        ev.events = EPOLLIN;
        ev.data.fd = conn_sock;
        if (epoll_ctl(epollfd, EPOLL_CTL_ADD, conn_sock, &ev) == -1) {
          perror("epoll_ctl: conn_sock");
          exit(EXIT_FAILURE);
        }
        continue;
      }

      log_trace("main (%d): handling listen event on fd '%d'", __LINE__, events[n].data.fd);
      // There's data to read
      // Read and send back
      /*do_use_fd(events[n].data.fd);*/
    }
  }
  printf("Hello world\n");
}
