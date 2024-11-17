
#ifndef EPOLL_H

extern atomic_int res;

struct epoll_ctl_info {
  int efd;
  int new_fd;
  struct epoll_event* event;
};

int fd_poll_del_and_close(void *context);

void fd_accept_and_epoll_add(void *context);

void fd_recv_and_send(void *context);

#endif // !EPOLL_H
