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

#include "prime-time/is-prime-request.h"

#define DELIMETERS "\n"

/// Return the number of requests processed
int is_prime_request_builder(struct is_prime_request** request,
                             char* raw_request,
                             size_t req_size)
{
  assert(raw_request != NULL);
  assert(req_size > 0);

  bool prime;
  int j = 1, number;
  char *str1 = raw_request, *token, *saveptr1;
  struct is_prime_request *prev;

  // tokenizer on the split delimiters
  for (; ; j++, str1 = NULL) {
    token = strtok_r(str1, DELIMETERS, &saveptr1);
    if (token == NULL)
      break;
    number = is_prime_request_malformed(token);
    prime = is_prime(number);

    // The very first request pointer should be the one passed 
    // as argument to the function
    struct is_prime_request *curr;
    is_prime_init(&curr, number, prime);
    if (j == 1)
      *request = curr;

    is_prime_beget_response(curr);
    // Stop handling requests for this socket as soon as we
    // find a malformed request
    if (number < 0) {
      // Regardless this is a handled request
      j++;
      break;
    }

    // Singly linked list logic
    if (j > 1)
      prev->next = curr;
    prev = curr;
  }

  return j - 1;
}

void is_prime_init(struct is_prime_request** request, int number, bool prime)
{
  *request = malloc(sizeof(struct is_prime_request));
  (*request)->next = NULL;
  (*request)->is_prime = prime;
  (*request)->number = number;
}

int is_prime_request_malformed(char *req) 
{
  assert(req != NULL);

  log_trace("is_prime_request_malformed: parsing request: '%s'", req);

  // Is json?
  json_object *root = json_tokener_parse(req);
  if (!root) {
    log_warn("is_prime_request_malformed: json_tokener_parse failed");
    return -1;
  }

  json_object *method = json_object_object_get(root, PRIME_RESPONSE_METHOD_KEY);
  if (!method) {
    json_object_put(root);
    log_warn("is_prime_request_malformed: json_object_object_get failed for 'method'");
    return -2;
  }

  const char *method_value = json_object_get_string(method);
  if (!method_value) {
    json_object_put(root);
    log_warn("is_prime_request_malformed: json_object_get_string failed for 'method'");
    return -3;
  }

  if (strncmp(PRIME_RESPONSE_METHOD_VALUE, method_value, PRIME_RESPONSE_METHOD_VALUE_LEN) != 0) {
    json_object_put(root);
    log_warn("is_prime_request_malformed: method value did not match '%s'", method_value);
    return -4;
  }

  json_object *number = json_object_object_get(root, PRIME_REQUEST_NUMBER_KEY);
  if (!method) {
    json_object_put(root);
    log_warn("is_prime_request_malformed: json_object_object_get failed for 'number'");
    return -5;
  }

  errno = 0;
  int number_value = json_object_get_int(number);
  if (errno != 0) {
    json_object_put(root);
    log_warn("is_prime_request_malformed: json_object_get_int64 failed for '%s'", number);
    return -7;
  }

  json_object_put(root);
  return number_value;
}

bool is_prime(int number) 
{
  if (number <= 1)
    return false; // less than 2 are not prime numbers
  for (int i = 2; i * i <= number; i++) {
    if (number % i == 0)
      return false;
  }
  return true;
}

void is_prime_beget_response(struct is_prime_request* request)
{
  assert(request != NULL);

  if (request->number < 0) {
    sprintf(request->response, PRIME_RESPONSE_FORMAT, "\"ill-formed-request!!!\"");
    return;
  }
  sprintf(request->response, PRIME_RESPONSE_FORMAT, (request->is_prime ? "true" : "false"));
}

void is_prime_free(struct is_prime_request** request)
{
  assert(*request != NULL);
  struct is_prime_request *curr = *request, *next = NULL;
  do {
    next = curr->next;
    free(curr);
    curr = next;
  } while (curr != NULL);
}
