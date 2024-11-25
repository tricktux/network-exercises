
#ifndef EPOLL_H
#define EPOLL_H

struct epoll_ctl_info {
  int efd;
  int new_fd;
  struct epoll_event* event;
};

int fd_poll_del_and_close(void* context);

void fd_accept_and_epoll_add(void* context);

#endif  // !EPOLL_H
