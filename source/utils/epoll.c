#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <stdarg.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdatomic.h>

#include "log/log.h"
#include "utils/epoll.h"

int fd_poll_del_and_close(void* context)
{
  struct epoll_ctl_info* info = context;
  assert(info != NULL);
  assert(info->event != NULL);

  if (epoll_ctl(info->efd, EPOLL_CTL_DEL, info->new_fd, info->event) == -1) {
    return -1;
  }
  close(info->new_fd);
  return 0;
}

int fd_accept_and_epoll_add(void* context)
{
  struct epoll_ctl_info* info = context;
  assert(info != NULL);

  socklen_t addrlen = sizeof(struct sockaddr_storage);
  struct sockaddr_storage addr;

  int conn_sock = accept(info->new_fd, (struct sockaddr*)&addr, &addrlen);
  if (conn_sock == -1) {
    log_error("accept failed: %s (errno: %d)", strerror(errno), errno);
    perror("fd_accept_and_epoll_add: accept: ");
    exit(EXIT_FAILURE);
  }

  log_info("fd_accept_and_epoll_add: new connection on socket '%d'", conn_sock);
  fcntl(conn_sock, F_SETFL, O_NONBLOCK);

  // Doing edge-level trigger
  struct epoll_event ev;
  ev.events = EPOLLIN | EPOLLET;
  ev.data.fd = conn_sock;
  if (epoll_ctl(info->efd, EPOLL_CTL_ADD, conn_sock, &ev) == -1) {
    perror("fd_accept_and_epoll_add: epoll_ctl: conn_sock");
    exit(EXIT_FAILURE);
  }

  return conn_sock;
}
