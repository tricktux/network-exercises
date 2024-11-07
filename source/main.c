#define _POSIX_C_SOURCE 200112L

#include <fcntl.h>
#include <netdb.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/epoll.h>
#include <unistd.h>

#define MAX_NUM_CON 10
#define MAX_EVENTS 10
#define BUF_SIZE 1024
#define PORT "7"

int main(int argc, char const* argv[])
{
  int listen_fd, s;
  struct addrinfo hints;
  struct addrinfo *result, *rp;

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

  for (rp = result; rp != NULL; rp = rp->ai_next) {
    listen_fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
    if (listen_fd == -1)
      continue;

    if (bind(listen_fd, rp->ai_addr, rp->ai_addrlen) == 0)
      break; /* Success */

    close(listen_fd);
  }

  freeaddrinfo(result); /* No longer needed */

  if (rp == NULL) { /* No address succeeded */
    fprintf(stderr, "Could not bind\n");
    exit(EXIT_FAILURE);
  }

  if (listen(listen_fd, MAX_NUM_CON) == -1) {
    fprintf(stderr, "listen failed\n");
    exit(EXIT_FAILURE);
  }

  struct epoll_event ev, events[MAX_EVENTS];
  int listen_sock, conn_sock, nfds, epollfd;

  epollfd = epoll_create1(0);
  if (epollfd == -1) {
    fprintf(stderr, "epoll_create1 failed\n");
    exit(EXIT_FAILURE);
  }

  ev.events = EPOLLIN;
  ev.data.fd = listen_fd;
  if (epoll_ctl(epollfd, EPOLL_CTL_ADD, listen_fd, &ev) == -1) {
    fprintf(stderr, "epoll_ctl: listen_sock\n");
    exit(EXIT_FAILURE);
  }


  int n;
  socklen_t addrlen;
  struct sockaddr_storage addr;

  for (;;) {
    nfds = epoll_wait(epollfd, events, MAX_EVENTS, -1);
    if (nfds == -1) {
      fprintf(stderr, "epoll_wait\n");
      exit(EXIT_FAILURE);
    }

    for (n = 0; n < nfds; ++n) {
      if (events[n].data.fd == listen_sock) {
        conn_sock = accept(listen_sock,
                           (struct sockaddr *) &addr, &addrlen);
        if (conn_sock == -1) {
          fprintf(stderr, "accept\n");
          exit(EXIT_FAILURE);
        }
        fcntl(conn_sock, F_SETFL, O_NONBLOCK);
        /*setnonblocking(conn_sock);*/
        ev.events = EPOLLIN;
        ev.data.fd = conn_sock;
        if (epoll_ctl(epollfd, EPOLL_CTL_ADD, conn_sock,
                      &ev) == -1) {
          perror("epoll_ctl: conn_sock");
          exit(EXIT_FAILURE);
        }
      } else {
        /*do_use_fd(events[n].data.fd);*/
      }
    }
  }
  printf("Hello world\n");
}
