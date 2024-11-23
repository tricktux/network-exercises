
#ifndef EPOLL_H

struct epoll_ctl_info {
  int efd;
  int new_fd;
  struct epoll_event* event;
};

int fd_poll_del_and_close(void* context);

void fd_accept_and_epoll_add(void* context);

int sendall(int sfd, char* buf, int* len);

#endif  // !EPOLL_H
