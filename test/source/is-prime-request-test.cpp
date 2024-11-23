
#define CATCH_CONFIG_MAIN
#include <catch2/catch.hpp>
#include "prime-time/is-prime-request.h"

// You might need to adjust the include path based on your project structure

TEST_CASE("is_prime_request_builder handles valid requests", "[request]") {
  struct is_prime_request* request = NULL;

  SECTION("Valid request with prime number") {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":17}\n";
    REQUIRE(is_prime_request_builder(&request, raw_request, strlen(raw_request)) == 0);
    REQUIRE(request != NULL);
    /*REQUIRE(request->method == std::string("isPrime"));*/
    /*REQUIRE(request->number == 17);*/
  }

  SECTION("Valid request with non-prime number") {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":24}\n";
    REQUIRE(is_prime_request_builder(&request, raw_request, strlen(raw_request)) == 0);
    REQUIRE(request != NULL);
    /*REQUIRE(request->method == std::string("isPrime"));*/
    /*REQUIRE(request->number == 24);*/
  }

  SECTION("Valid request with floating-point number") {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":17.5}\n";
    REQUIRE(is_prime_request_builder(&request, raw_request, strlen(raw_request)) == 0);
    REQUIRE(request != NULL);
    /*REQUIRE(request->method == std::string("isPrime"));*/
    /*REQUIRE(request->number == 17.5);*/
  }

  if (request) is_prime_free(request);
}

TEST_CASE("is_prime_request_builder handles malformed requests", "[request]") {
  struct is_prime_request* request = NULL;

  SECTION("Malformed JSON") {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":17\n";
    REQUIRE(is_prime_request_builder(&request, raw_request, strlen(raw_request)) != 0);
  }

  SECTION("Missing required field") {
    char raw_request[] = "{\"method\":\"isPrime\"}\n";
    REQUIRE(is_prime_request_builder(&request, raw_request, strlen(raw_request)) != 0);
  }

  SECTION("Incorrect method name") {
    char raw_request[] = "{\"method\":\"notIsPrime\",\"number\":17}\n";
    REQUIRE(is_prime_request_builder(&request, raw_request, strlen(raw_request)) != 0);
  }

  SECTION("Number is not a number") {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":\"seventeen\"}\n";
    REQUIRE(is_prime_request_builder(&request, raw_request, strlen(raw_request)) != 0);
  }

  if (request) is_prime_free(request);
}

TEST_CASE("is_prime_request_malformed correctly identifies malformed requests", "[request]") {
  struct is_prime_request* request = (struct is_prime_request*)malloc(sizeof(struct is_prime_request));

  SECTION("Well-formed request") {
    /*request->method = strdup("isPrime");*/
    /*request->number = 17;*/
    REQUIRE_FALSE(is_prime_request_malformed(request));
  }

  SECTION("Incorrect method name") {
    /*request->method = strdup("notIsPrime");*/
    /*request->number = 17;*/
    REQUIRE(is_prime_request_malformed(request));
  }

  is_prime_free(request);
}

TEST_CASE("is_prime correctly identifies prime numbers", "[prime]") {
  struct is_prime_request* request = (struct is_prime_request*)malloc(sizeof(struct is_prime_request));
  /*request->method = strdup("isPrime");*/

  SECTION("Prime numbers") {
    int primes[] = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29};
    for (int prime : primes) {
      request->number = prime;
      REQUIRE(is_prime(request));
    }
  }

  SECTION("Non-prime numbers") {
    int non_primes[] = {1, 4, 6, 8, 9, 10, 12, 14, 15, 16};
    for (int non_prime : non_primes) {
      request->number = non_prime;
      REQUIRE_FALSE(is_prime(request));
    }
  }

  SECTION("Floating-point numbers") {
    request->number = 17.5;
    REQUIRE_FALSE(is_prime(request));
  }

  is_prime_free(request);
}

TEST_CASE("is_prime_beget_response generates correct responses", "[response]") {
  struct is_prime_request* request = (struct is_prime_request*)malloc(sizeof(struct is_prime_request));
  /*request->method = strdup("isPrime");*/

  SECTION("Prime number") {
    request->number = 17;
    char* response = is_prime_beget_response(request);
    REQUIRE(std::string(response) == "{\"method\":\"isPrime\",\"prime\":true}\n");
    free(response);
  }

  SECTION("Non-prime number") {
    request->number = 24;
    char* response = is_prime_beget_response(request);
    REQUIRE(std::string(response) == "{\"method\":\"isPrime\",\"prime\":false}\n");
    free(response);
  }

  SECTION("Floating-point number") {
    request->number = 17.5;
    char* response = is_prime_beget_response(request);
    REQUIRE(std::string(response) == "{\"method\":\"isPrime\",\"prime\":false}\n");
    free(response);
  }

  is_prime_free(request);
}
