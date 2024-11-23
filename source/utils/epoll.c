#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
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
#include <stdatomic.h>

#include "log/log.h"
#include "utils/epoll.h"

int sendall(int sfd, char* buf, int* len)
{
  assert(sfd != 0);
  assert(buf != NULL);
  assert(*len > 0);

  long nbytes_sent = 0;
  int total_to_send = *len, total_sent = 0;

  for (; nbytes_sent < total_to_send;) {
    nbytes_sent = send(sfd, buf, (size_t)total_to_send, 0);
    if (nbytes_sent == -1) {
      int err = errno;
      *len = total_sent;
      log_error("sendall: send failed, '%d'", err);
      return err;
    }

    total_to_send -= (int)nbytes_sent;
    buf += nbytes_sent;
    total_sent += (int)nbytes_sent;
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

void fd_accept_and_epoll_add(void* context)
{
  struct epoll_ctl_info* info = context;
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
  ev.events = EPOLLIN | EPOLLET;
  ev.data.fd = conn_sock;
  if (epoll_ctl(info->efd, EPOLL_CTL_ADD, conn_sock, &ev) == -1) {
    perror("fd_accept_and_epoll_add: epoll_ctl: conn_sock");
    exit(EXIT_FAILURE);
  }
}
