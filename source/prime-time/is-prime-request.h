#ifndef INCLUDE_PRIME_TIME_IS_PRIME_REQUEST_H_
#define INCLUDE_PRIME_TIME_IS_PRIME_REQUEST_H_

#define PRIME_MAX_REQUEST_SIZE 256
#define PRIME_MAX_RESPONSE_SIZE PRIME_MAX_REQUEST_SIZE
#define PRIME_REQUEST_METHOD_KEY "method"
#define PRIME_REQUEST_METHOD_VALUE "isPrime"
#define PRIME_REQUEST_NUMBER_KEY "number"
#define PRIME_RESPONSE_METHOD_KEY "method"
#define PRIME_RESPONSE_METHOD_VALUE "isPrime"
#define PRIME_RESPONSE_METHOD_VALUE_LEN 7
#define PRIME_RESPONSE_NUMBER_KEY "prime"
#define PRIME_RESPONSE_FORMAT \
  "{\"method\":\"isPrime\",\"prime\":%s}"

#ifdef __cplusplus
extern "C" {
#endif

struct is_prime_request {
  char response[PRIME_MAX_RESPONSE_SIZE];
  bool is_prime;
  int number;
  struct is_prime_request* next;
};

int is_prime_request_builder(struct is_prime_request** request,
                             char* raw_request,
                             size_t req_size);
int is_prime_request_malformed(char *req);
bool is_prime(int number);
void is_prime_beget_response(struct is_prime_request* request);
void is_prime_init(struct is_prime_request** request, int number, bool prime);
void is_prime_free(struct is_prime_request** request);


#ifdef __cplusplus
}
#endif
#endif  // INCLUDE_PRIME_TIME_IS_PRIME_REQUEST_H_
