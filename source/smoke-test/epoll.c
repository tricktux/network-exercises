
#include <stdio.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <unistd.h>

#include "epoll.h"

int fd_poll_del_and_close(int epollfd, int fd, struct epoll_event* event) {
  if (epoll_ctl(epollfd, EPOLL_CTL_DEL, fd, event) == -1) {
    return -1;
  }
  close(fd);
  return 0;
}


