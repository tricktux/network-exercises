#ifndef INCLUDE_UTILS_SOCKETS_H_
#define INCLUDE_UTILS_SOCKETS_H_

int sendall(int sfd, char* buf, int* len);

int create_server(const char* port, int* listen_fd);

#endif  // INCLUDE_UTILS_SOCKETS_H_

