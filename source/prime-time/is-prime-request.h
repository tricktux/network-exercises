#ifndef INCLUDE_PRIME_TIME_IS_PRIME_REQUEST_H_
#define INCLUDE_PRIME_TIME_IS_PRIME_REQUEST_H_

#define PRIME_REQUEST_METHOD_KEY "method"
#define PRIME_REQUEST_METHOD_VALUE "isPrime"
#define PRIME_REQUEST_NUMBER_KEY "number"
#define PRIME_RESPONSE_METHOD_KEY "method"
#define PRIME_RESPONSE_METHOD_VALUE "isPrime"
#define PRIME_RESPONSE_METHOD_VALUE_LEN 7
#define PRIME_RESPONSE_NUMBER_KEY "prime"
#define PRIME_RESPONSE_FORMAT "{\"method\":\"isPrime\",\"prime\":%s}\n"
#define PRIME_RESPONSE_ILL_RESPONSE "\"ill-formed-request!!!\""

#ifdef __cplusplus
extern "C" {
#endif

struct is_prime_request {
  bool is_prime;
  bool is_malformed;
  int number;
  struct is_prime_request* next;
};

int is_prime_request_builder(struct queue *sdq,
                             char* raw_request,
                             size_t req_size, bool *malformed);
bool is_prime_request_malformed(struct is_prime_request *request, char* req);
void is_prime_request_f(struct is_prime_request *request);
void is_prime_beget_response(struct is_prime_request* request, char *response, int *size);
void is_prime_init(struct is_prime_request** request);
void is_prime_free(struct is_prime_request** request);

#ifdef __cplusplus
}
#endif
#endif  // INCLUDE_PRIME_TIME_IS_PRIME_REQUEST_H_
