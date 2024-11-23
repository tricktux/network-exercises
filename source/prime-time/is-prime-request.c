#define _POSIX_C_SOURCE 1

#include <bits/types/struct_iovec.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdatomic.h>

#include "log/log.h"

#include "prime-time/is-prime-request.h"

#define DELIMETERS "\n"

int is_prime_request_builder(struct is_prime_request** request,
                             char* raw_request,
                             size_t req_size)
{
  assert(*request != NULL);
  assert(raw_request != NULL);
  assert(req_size > 0);

  char *str1, *token;
  char *saveptr1;
  int j;
  // tokenizer on the split delimiters
  for (j = 1, str1 = raw_request; ; j++, str1 = NULL) {
    token = strtok_r(str1, DELIMETERS, &saveptr1);
    if (token == NULL)
      break;
    log_trace("%d: %s", j, token);

  }

  return 0;
}

int is_prime_request_malformed(struct is_prime_request* request) {}
int is_prime(struct is_prime_request* request) {}
char* is_prime_beget_response(struct is_prime_request* request) {}
int is_prime_free(struct is_prime_request* request) {}
