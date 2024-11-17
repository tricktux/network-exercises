


int fd_poll_del_and_close(int epollfd, int fd, struct epoll_event* event);

void fd_accept_and_epoll_add(int listen_fd, int epollfd);
