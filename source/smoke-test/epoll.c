#include <arpa/inet.h>
#include <assert.h>
#include <fcntl.h>
#include <netdb.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "log.h"
#include "epoll.h"

// TODO: fix
// get sockaddr, IPv4 or IPv6:
void* get_in_addr(struct sockaddr* sa)
{
  if (sa->sa_family == AF_INET) {
    return &(((struct sockaddr_in*)sa)->sin_addr);
  }

  return &(((struct sockaddr_in6*)sa)->sin6_addr);
}

int fd_poll_del_and_close(struct epoll_ctl_info *info)
{
  assert(info != NULL);
  assert(info->event != NULL);

  if (epoll_ctl(info->efd, EPOLL_CTL_DEL, info->new_fd, info->event) == -1) {
    return -1;
  }
  close(info->new_fd);
  return 0;
}

void fd_accept_and_epoll_add(struct epoll_ctl_info *info)
{
  assert(info != NULL);

  socklen_t addrlen;
  struct epoll_event ev;
  struct sockaddr_storage addr;

  int conn_sock = accept(info->new_fd, (struct sockaddr*)&addr, &addrlen);
  if (conn_sock == -1) {
    perror("accept\n");
    exit(EXIT_FAILURE);
  }

  log_info("fd_accept_and_epoll_add: new connection on socket '%d'", conn_sock);
  fcntl(conn_sock, F_SETFL, O_NONBLOCK);
  // Doing edge-level trigger
  // We take care of handling all reads and send below
  ev.events = EPOLLIN | EPOLLET;
  ev.data.fd = conn_sock;
  if (epoll_ctl(info->efd, EPOLL_CTL_ADD, conn_sock, &ev) == -1) {
    perror("fd_accept_and_epoll_add: epoll_ctl: conn_sock");
    exit(EXIT_FAILURE);
  }
}
