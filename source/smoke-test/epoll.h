
#ifndef EPOLL_H

extern atomic_int res;

struct epoll_ctl_info {
  int efd;
  int new_fd;
  struct epoll_event* event;
};

int fd_poll_del_and_close(struct epoll_ctl_info *info);

void fd_accept_and_epoll_add(struct epoll_ctl_info *info);

void fd_recv_and_send(struct epoll_ctl_info *info);

#endif // !EPOLL_H
