
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
    REQUIRE(request->next == NULL);
  }

  SECTION("Valid request with non-prime number")
  {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":24}\n";
    REQUIRE(is_prime_request_builder(&request, raw_request, strlen(raw_request))
            == 1);
    REQUIRE(request != NULL);
    REQUIRE(request->number == 24);
    REQUIRE(request->is_prime == false);
    REQUIRE(request->next == NULL);
  }

  SECTION("Valid request with floating-point number")
  {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":17.5}\n";
    REQUIRE(
        is_prime_request_builder(&request, raw_request, strlen(raw_request))
        == 1);
    REQUIRE(request != NULL);
    REQUIRE(request->number == 17);
    REQUIRE(request->is_prime == true);
    REQUIRE(request->next == NULL);
  }

  SECTION("Valid request with prime number; followed by invalid request")
  {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":17}\n{\"method\":\"isPrime\",\"number\":24}\n";
    REQUIRE(is_prime_request_builder(&request, raw_request, strlen(raw_request))
            == 2);
    REQUIRE(request != NULL);
    REQUIRE(request->number == 17);
    REQUIRE(request->is_prime == true);
    REQUIRE(request->next != NULL);
    struct is_prime_request *next = request->next;
    REQUIRE(next->number == 24);
    REQUIRE(next->is_prime == false);
    REQUIRE(next->next == NULL);
  }

  if (request)
    is_prime_free(&request);
}
