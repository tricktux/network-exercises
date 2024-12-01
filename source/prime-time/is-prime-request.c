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

#include <json-c/json.h>
#include <json-c/json_tokener.h>

#include "log/log.h"
#include "utils/queue.h"

#include "prime-time/is-prime-request.h"

#define DELIMITERS "\n"

/// Return the number of requests processed
int is_prime_request_builder(struct queue *sdq,
                             char* raw_request,
                             size_t req_size, bool *malformed)
{
  assert(sdq != NULL);
  assert(malformed != NULL);
  assert(raw_request != NULL);
  assert(req_size > 0);

  int j = 1, size;
  char *str1 = raw_request, *token, *saveptr1;
  struct is_prime_request curr;

  // tokenizer on the split delimiters
  for (;; j++, str1 = NULL) {
    token = strtok_r(str1, DELIMITERS, &saveptr1);
    if (token == NULL)
      break;
    // We have exceeded the request size
    if ((token - raw_request) >= (long) req_size)
      break;


    *malformed = is_prime_request_malformed(&curr, token);
    curr.is_prime = is_prime_f(curr.number);
    is_prime_beget_response(&curr, sdq->head, &size);
    queue_push_ex(sdq, (size_t) size);

    // Stop handling requests for this socket as soon as we
    // find a malformed request
    if (*malformed) {
      // Regardless this is a handled request
      j++;
      break;
    }
  }

  return j - 1;
}

void is_prime_init(struct is_prime_request** request)
{
  *request = malloc(sizeof(struct is_prime_request));
  (*request)->is_prime = false;
  (*request)->number = 0;
}

bool is_prime_request_malformed(struct is_prime_request *request, char* req)
{
  assert(request != NULL);
  assert(req != NULL);

  log_trace("is_prime_request_malformed: parsing request: '%s'", req);

  {
    // If there's a period it probably means a double and that's is a non-prime
    char* r = NULL;
    r = strchr(req, '.');
    if (r != NULL) {
      request->is_malformed = true;
      return true;
    }
  }

  // Is json?
  json_object* root = json_tokener_parse(req);
  if (!root) {
    log_warn("is_prime_request_malformed: json_tokener_parse failed");
    request->is_malformed = true;
    return true;
  }

  json_object* method = json_object_object_get(root, PRIME_RESPONSE_METHOD_KEY);
  if (!method) {
    json_object_put(root);
    log_warn(
        "is_prime_request_malformed: json_object_object_get failed for "
        "'method'");
    request->is_malformed = true;
    return true;
  }

  const char* method_value = json_object_get_string(method);
  if (!method_value) {
    json_object_put(root);
    log_warn(
        "is_prime_request_malformed: json_object_get_string failed for "
        "'method'");
    request->is_malformed = true;
    return true;
  }

  if (strncmp(PRIME_RESPONSE_METHOD_VALUE,
              method_value,
              PRIME_RESPONSE_METHOD_VALUE_LEN)
      != 0)
  {
    json_object_put(root);
    log_warn("is_prime_request_malformed: method value did not match '%s'",
             method_value);
    request->is_malformed = true;
    return true;
  }

  json_object* number = json_object_object_get(root, PRIME_REQUEST_NUMBER_KEY);
  if (!method) {
    json_object_put(root);
    log_warn(
        "is_prime_request_malformed: json_object_object_get failed for "
        "'number'");
    request->is_malformed = true;
    return true;
  }

  errno = 0;
  int number_value = json_object_get_int(number);
  if (errno != 0) {
    json_object_put(root);
    log_warn(
        "is_prime_request_malformed: json_object_get_int failed for '%s'",
        number);
    request->is_malformed = true;
    return true;
  }

  json_object_put(root);
  request->is_malformed = false;
  request->number = number_value;
  return false;
}

bool is_prime_f(int number)
{
  if (number <= 1) {
    return false;  // less than 2 are not prime numbers
  }
  for (int i = 2; i * i <= number; i++) {
    if (number % i == 0) {
      return false;
    }
  }
  return true;
}

void is_prime_beget_response(struct is_prime_request* request, char *response, int *size)
{
  assert(request != NULL);
  assert(response != NULL);
  assert(size != NULL);

  if (request->is_malformed) {
    *size = PRIME_RESPONSE_ILL_RESPONSE_SIZE;
    memcpy(response, PRIME_RESPONSE_ILL_RESPONSE, (size_t) *size);
    log_trace("is_prime_beget_response: '%s'", response);
    return;
  }
  *size = sprintf(response,
          PRIME_RESPONSE_FORMAT,
          (request->is_prime ? "true" : "false"));
  log_trace("is_prime_beget_response: '%s'", response);
}

void is_prime_free(struct is_prime_request** request)
{
  assert(*request != NULL);

  free(*request);
  *request = NULL;
}
