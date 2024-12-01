
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

#include "utils/queue.h"

#define PRIME_TRUE "{\"method\":\"isPrime\",\"prime\":true}\n"
#define PRIME_FALSE "{\"method\":\"isPrime\",\"prime\":false}\n"
#define PRIME_MALFORMED \
  "{\"method\":\"isPrime\",\"prime\":\"ill-formed-request!!!\"}\n"

TEST_CASE("is_prime_request_builder handles valid requests", "[request]")
{
  int size;
  char *data;
  bool malformed;
  struct queue *sdqu = NULL;
  queue_init(&sdqu, 1024);


  SECTION("Valid request with prime number")
  {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":17}\n";
    REQUIRE(is_prime_request_builder(sdqu, raw_request, strlen(raw_request), &malformed)
            == 1);
    REQUIRE(malformed == false);
    size = queue_pop_no_copy(sdqu, &data);
    REQUIRE(strncmp(data, PRIME_TRUE, size) == 0);
  }

  SECTION("Valid request with non-prime number")
  {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":24}\n";
    REQUIRE(is_prime_request_builder(sdqu, raw_request, strlen(raw_request), &malformed)
            == 1);
    REQUIRE(malformed == false);
    size = queue_pop_no_copy(sdqu, &data);
    REQUIRE(strncmp(data, PRIME_FALSE, size) == 0);
  }

  SECTION("Valid request with floating-point number")
  {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":17.5}\n";
    REQUIRE(is_prime_request_builder(sdqu, raw_request, strlen(raw_request), &malformed)
            == 1);
    REQUIRE(malformed == true);
    size = queue_pop_no_copy(sdqu, &data);
    REQUIRE(strncmp(data, PRIME_RESPONSE_ILL_RESPONSE, size) == 0);
  }

  SECTION(
      "Valid composite request with prime number; followed by non prime "
      "request")
  {
    char response[1024];
    char raw_request[] =
        "{\"method\":\"isPrime\",\"number\":17}\n{\"method\":\"isPrime\","
        "\"number\":24}\n";
    REQUIRE(is_prime_request_builder(sdqu, raw_request, strlen(raw_request), &malformed)
            == 2);
    REQUIRE(malformed == false);

    sprintf(response, "%s%s", PRIME_TRUE, PRIME_FALSE);
    size = queue_pop_no_copy(sdqu, &data);
    REQUIRE(strncmp(data, response, size) == 0);
  }

  if (sdqu)
    queue_free(&sdqu);
}

TEST_CASE("is_prime_request_builder handles invalid requests", "[request]")
{
  int size;
  char *data;
  bool malformed;
  struct is_prime_request* request = NULL;
  struct queue *sdqu = NULL;
  queue_init(&sdqu, 1024);
  char response[1024];

  SECTION("Valid request with prime number")
  {
    char raw_request[] = "{\"method\":\"isPrime\",\"number\":\"foo\"}\n";
    REQUIRE(is_prime_request_builder(sdqu, raw_request, strlen(raw_request), &malformed)
            == 1);
    REQUIRE(malformed == true);
    size = queue_pop_no_copy(sdqu, &data);
    REQUIRE(strncmp(data, PRIME_RESPONSE_ILL_RESPONSE, size) == 0);
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
    REQUIRE(is_prime_request_builder(sdqu, raw_request, strlen(raw_request), &malformed)
            == 4);

    REQUIRE(malformed == true);
    sprintf(response, "%s%s%s%s", PRIME_TRUE, PRIME_FALSE, PRIME_TRUE, PRIME_RESPONSE_ILL_RESPONSE);
    size = queue_pop_no_copy(sdqu, &data);
    REQUIRE(strncmp(data, response, size) == 0);
  }

  if (sdqu)
    queue_free(&sdqu);
}
