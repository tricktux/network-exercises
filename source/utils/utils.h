#ifndef INCLUDE_UTILS_UTILS_H_
#define INCLUDE_UTILS_UTILS_H_

int init_logs(FILE* fd, int log_level);

int recv_request(int fd, struct queue* qu);

#endif  // INCLUDE_UTILS_UTILS_H_

