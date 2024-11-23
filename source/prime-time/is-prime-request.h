
#define PRIME_MAX_REQUEST_SIZE 8192
#define PRIME_MAX_RESPONSE_SIZE 8192
#define PRIME_REQUEST_METHOD_KEY "method"
#define PRIME_REQUEST_METHOD_VALUE "isPrime"
#define PRIME_REQUEST_NUMBER_KEY "number"
#define PRIME_RESPONSE_METHOD_KEY "method"
#define PRIME_RESPONSE_METHOD_VALUE "isPrime"
#define PRIME_RESPONSE_NUMBER_KEY "prime"
#define PRIME_RESPONSE_ILLFORMED \
  "{\"method\":\"isPrime\",\"prime\":ill-formed-request!}"

struct is_prime_request {
  char raw_request[PRIME_MAX_REQUEST_SIZE];
  int is_malformed;  // 0 or 1
  char response[PRIME_MAX_RESPONSE_SIZE];
  int is_prime;  // 0 or 1
  struct is_prime_request* next;
};

int is_prime_request_builder(struct is_prime_request** request,
                             const char* raw_request,
                             size_t req_size);
int is_prime_request_malformed(struct is_prime_request* request);
int is_prime(struct is_prime_request* request);
int is_prime_beget_response(struct is_prime_request* request);
int is_prime_free(struct is_prime_request* request);
