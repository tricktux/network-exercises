
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

#include <catch2/catch.hpp>
#include "means-to-an-end/asset-prices.h"

TEST_CASE("prices_init initializes prices structure correctly", "[prices]")
{
  struct asset_prices* ps = nullptr;
  size_t capacity = 10;

  asset_prices_init(&ps, capacity);

  REQUIRE(ps != nullptr);
  REQUIRE(ps->capacity == capacity);
  REQUIRE(ps->size == 0);
  REQUIRE(ps->data != nullptr);

  asset_prices_free(&ps);
  REQUIRE(ps == nullptr);
}

TEST_CASE("prices_init_data increases capacity", "[prices]")
{
  struct asset_prices* ps = nullptr;
  size_t initial_capacity = 10;
  size_t new_capacity = 20;

  asset_prices_init(&ps, initial_capacity);
  REQUIRE(ps->capacity == initial_capacity);

  asset_prices_init_data(ps, new_capacity);
  REQUIRE(ps->capacity == new_capacity);

  asset_prices_free(&ps);
}

TEST_CASE("prices_push adds data correctly", "[prices]")
{
  struct asset_prices* ps = nullptr;
  size_t capacity = 2;
  asset_prices_init(&ps, capacity);

  struct asset_price p1 = {1, 100};
  struct asset_price p2 = {2, 200};
  struct asset_price p3 = {3, 300};

  SECTION("Push within capacity")
  {
    asset_prices_push(ps, &p1);
    REQUIRE(ps->size == 1);
    REQUIRE(ps->data[0].timestamp == 1);
    REQUIRE(ps->data[0].price == 100);

    asset_prices_push(ps, &p2);
    REQUIRE(ps->size == 2);
    REQUIRE(ps->data[1].timestamp == 2);
    REQUIRE(ps->data[1].price == 200);
  }

  SECTION("Push beyond capacity triggers resize")
  {
    asset_prices_push(ps, &p1);
    asset_prices_push(ps, &p2);
    asset_prices_push(ps, &p3);

    REQUIRE(ps->size == 3);
    REQUIRE(ps->capacity == 4);  // Double the original capacity
    REQUIRE(ps->data[2].timestamp == 3);
    REQUIRE(ps->data[2].price == 300);
  }

  asset_prices_free(&ps);
}

TEST_CASE("prices_free deallocates memory correctly", "[prices]")
{
  struct asset_prices* ps = nullptr;
  asset_prices_init(&ps, 10);

  REQUIRE(ps != nullptr);
  REQUIRE(ps->data != nullptr);

  asset_prices_free(&ps);

  REQUIRE(ps == nullptr);
}

TEST_CASE("detecting duplicate timestamps", "[prices]")
{
  struct asset_prices* ps = nullptr;
  asset_prices_init(&ps, 10);

  REQUIRE(ps != nullptr);
  REQUIRE(ps->data != nullptr);

  struct asset_price p1 = {3, 300};
  struct asset_price p2 = {2, 200};
  struct asset_price p3 = {3, 301};
  struct asset_price p4 = {1, 100};
  struct asset_price p5 = {2, 201};

  asset_prices_push(ps, &p1);
  asset_prices_push(ps, &p2);

  REQUIRE(asset_prices_duplicate_timestamp_check(ps, p3.timestamp) == true);
  REQUIRE(asset_prices_duplicate_timestamp_check(ps, p4.timestamp) == false);
  REQUIRE(asset_prices_duplicate_timestamp_check(ps, p5.timestamp) == true);

  asset_prices_free(&ps);

  REQUIRE(ps == nullptr);
}

TEST_CASE("price query tests", "[prices]")
{
  struct asset_prices* ps = nullptr;
  asset_prices_init(&ps, 10);

  REQUIRE(ps != nullptr);
  REQUIRE(ps->data != nullptr);

  struct asset_price p1 = {4, 300};
  struct asset_price p2 = {5, 200};
  struct asset_price p3 = {3, 301};
  struct asset_price p4 = {1, 100};
  struct asset_price p5 = {2, 201};

  struct asset_price_query q1 = {1, 5};
  const auto q1avg = 220;
  struct asset_price_query q2 = {2, 4};
  const auto q2avg = 267;

  asset_prices_push(ps, &p1);
  asset_prices_push(ps, &p2);
  asset_prices_push(ps, &p3);
  asset_prices_push(ps, &p4);
  asset_prices_push(ps, &p5);

  REQUIRE(asset_prices_query(ps, &q1) == q1avg);
  REQUIRE(asset_prices_query(ps, &q2) == q2avg);

  asset_prices_free(&ps);

  REQUIRE(ps == nullptr);
}
