
#include <stdio.h>
#include <stdarg.h>
#include <stdbool.h>
#include <time.h>
#include <sys/time.h>
#include <string.h>
#include <assert.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <stddef.h>
#include <stdlib.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdatomic.h>

#include "log/log.h"
#include "utils/queue.h"

#include "utils/utils.h"

int init_logs(FILE* fd, int log_level)
{
  if (log_add_fp(fd, log_level) == -1) {
    printf("Failed to initialize log file\n");
    return -2;
  }

  log_set_level(log_level);

  return 0;
}

/**
 * @brief Receive from socket fd while there isn't an event
 *
 * @param ctx Pointer to structure to hold context
 * @param qu Pointer to queue to store all the received data
 * @return 
 *    0 if close event received
 *    -1 if EWOULDBLOCK received
 *    -2 for any other kind of error
 */
int recv_request(int fd, struct queue *qu)
{
  assert(fd > 0);
  assert(qu != NULL);

  ssize_t nbytes;

  for (;;) {
    // TODO: code smell here. Do not manipulate queue this way
    nbytes = recv(fd, qu->head, qu->free_capacity, 0);
    if (nbytes == 0) {
      log_warn("recv_request: handling close while reading on fd '%d'", fd);
      return 0;
    }

    if (nbytes == -1) {
      if ((errno == EAGAIN) || (errno == EWOULDBLOCK)) {
        return -1;
      }

      perror("recv_request: recv(): ");
      log_trace("recv_request: handling error while recv on fd '%d'", fd);
      return -2;
    }
    log_trace("recv_request: read '%d' bytes from fd '%d'", nbytes, fd);
    queue_push_ex(qu, (size_t) nbytes);
  }
}

