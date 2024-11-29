
#define CATCH_CONFIG_MAIN
#include <bits/types/struct_iovec.h>
#include <assert.h>
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

#include <json-c/json.h>
#include <json-c/json_tokener.h>

#include <catch2/catch.hpp>
#include "prime-time/is-prime-request.h"

#define PRIME_TRUE "{\"method\":\"isPrime\",\"prime\":true}\n"
#define PRIME_FALSE "{\"method\":\"isPrime\",\"prime\":false}\n"
#define PRIME_MALFORMED \
  "{\"method\":\"isPrime\",\"prime\":\"ill-formed-request!!!\"}\n"

TEST_CASE("is_prime_request_builder handles valid requests", "[request]")
{
  struct is_prime_request* request = NULL;

  SECTION("Valid request with prime number")
  {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":17}\n";
    REQUIRE(is_prime_request_builder(&request, raw_request, strlen(raw_request))
            == 1);
    REQUIRE(request != NULL);
    REQUIRE(request->number == 17);
    REQUIRE(request->is_prime == true);
    REQUIRE(request->is_malformed == false);
    REQUIRE(request->next == NULL);
    REQUIRE(strcmp(request->response, PRIME_TRUE) == 0);
  }

  SECTION("Valid request with non-prime number")
  {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":24}\n";
    REQUIRE(is_prime_request_builder(&request, raw_request, strlen(raw_request))
            == 1);
    REQUIRE(request != NULL);
    REQUIRE(request->number == 24);
    REQUIRE(request->is_prime == false);
    REQUIRE(request->is_malformed == false);
    REQUIRE(request->next == NULL);
    REQUIRE(strcmp(request->response, PRIME_FALSE) == 0);
  }

  SECTION("Valid request with floating-point number")
  {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":17.5}\n";
    REQUIRE(is_prime_request_builder(&request, raw_request, strlen(raw_request))
            == 1);
    REQUIRE(request != NULL);
    REQUIRE(request->is_prime == false);
    REQUIRE(request->is_malformed == true);
    REQUIRE(request->next == NULL);
    REQUIRE(strcmp(request->response, PRIME_MALFORMED) == 0);
  }

  SECTION(
      "Valid composite request with prime number; followed by non prime "
      "request")
  {
    char raw_request[] =
        "{\"method\":\"isPrime\",\"number\":17}\n{\"method\":\"isPrime\","
        "\"number\":24}\n";
    REQUIRE(is_prime_request_builder(&request, raw_request, strlen(raw_request))
            == 2);
    REQUIRE(request != NULL);
    REQUIRE(request->number == 17);
    REQUIRE(request->is_prime == true);
    REQUIRE(request->is_malformed == false);
    REQUIRE(request->next != NULL);
    REQUIRE(strcmp(request->response, PRIME_TRUE) == 0);
    struct is_prime_request* next = request->next;
    REQUIRE(next->number == 24);
    REQUIRE(next->is_prime == false);
    REQUIRE(request->is_malformed == false);
    REQUIRE(next->next == NULL);
    REQUIRE(strcmp(next->response, PRIME_FALSE) == 0);
  }

  if (request)
    is_prime_free(&request);
}

TEST_CASE("is_prime_request_builder handles invalid requests", "[request]")
{
  struct is_prime_request* request = NULL;

  SECTION("Valid request with prime number")
  {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":\"foo\"}\n";
    REQUIRE(is_prime_request_builder(&request, raw_request, strlen(raw_request))
            == 1);
    REQUIRE(request != NULL);
    REQUIRE(request->is_prime == false);
    REQUIRE(request->is_malformed == true);
    REQUIRE(request->next == NULL);
    REQUIRE(strcmp(request->response, PRIME_MALFORMED) == 0);
  }

  SECTION(
      "Invalid composite request with prime number; followed by non prime "
      "request")
  {
    char raw_request[] =
        "{\"method\":\"isPrime\",\"number\":72727}\n"
        "{\"method\":\"isPrime\",\"number\":24}\n"
        "{\"method\":\"isPrime\",\"number\":13}\n"
        "{\"method\":\"isPrime\",\"number\":\"hola\"}\n"
        "{\"method\":\"isPrime\",\"number\":23}\n";
    REQUIRE(is_prime_request_builder(&request, raw_request, strlen(raw_request))
            == 4);
    REQUIRE(request != NULL);
    REQUIRE(request->number == 72727);
    REQUIRE(request->is_prime == true);
    REQUIRE(request->is_malformed == false);
    REQUIRE(request->next != NULL);
    REQUIRE(strcmp(request->response, PRIME_TRUE) == 0);

    struct is_prime_request* next = request->next;
    REQUIRE(next->number == 24);
    REQUIRE(next->is_prime == false);
    REQUIRE(request->is_malformed == false);
    REQUIRE(next->next != NULL);
    REQUIRE(strcmp(next->response, PRIME_FALSE) == 0);

    next = next->next;
    REQUIRE(next->number == 13);
    REQUIRE(next->is_prime == true);
    REQUIRE(request->is_malformed == false);
    REQUIRE(next->next != NULL);
    REQUIRE(strcmp(next->response, PRIME_TRUE) == 0);

    next = next->next;
    REQUIRE(next->is_prime == false);
    REQUIRE(request->is_malformed == true);
    REQUIRE(next->next == NULL);
    REQUIRE(strcmp(next->response, PRIME_MALFORMED) == 0);
  }

  if (request)
    is_prime_free(&request);
}
