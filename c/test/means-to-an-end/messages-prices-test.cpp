
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
#include "means-to-an-end/client-session.h"
#include "utils/queue.h"

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


// Helper function to create a list with multiple clients
void create_test_list(struct clients_session **pca, int num_clients) {
  for (int i = 1; i <= num_clients; ++i) {
    clients_session_add(pca, i);
  }
}

TEST_CASE("clients_session operations", "[clients_session]") {
  struct clients_session *ca = nullptr;

  SECTION("Initialization and addition") {
    REQUIRE(ca == nullptr);

    clients_session_init(&ca, 1);
    REQUIRE(ca != nullptr);

    clients_session_add(&ca, 2);
    clients_session_add(&ca, 3);

    // Check if we can find all added clients
    REQUIRE(clients_session_find(&ca, 1));
    REQUIRE(clients_session_find(&ca, 2));
    REQUIRE(clients_session_find(&ca, 3));

    clients_session_free_all(&ca);
  }

  SECTION("Queue Initialization") {
    REQUIRE(ca == nullptr);

    clients_session_init(&ca, 1);
    REQUIRE(ca != nullptr);

    clients_session_add(&ca, 2);
    clients_session_add(&ca, 3);

    // Check if we can find all added clients
    REQUIRE(ca->recv_qu != NULL);
    REQUIRE(ca->recv_qu->capacity == 512);
    REQUIRE(ca->recv_qu->size == 0);

    clients_session_free_all(&ca);
  }

  SECTION("Finding clients") {
    create_test_list(&ca, 5);

    REQUIRE(clients_session_find(&ca, 1));
    REQUIRE(clients_session_find(&ca, 3));
    REQUIRE(clients_session_find(&ca, 5));
    REQUIRE_FALSE(clients_session_find(&ca, 6));
    REQUIRE_FALSE(clients_session_find(&ca, 88));

    clients_session_free_all(&ca);
  }

  SECTION("Removing clients") {
    create_test_list(&ca, 5);

    REQUIRE(clients_session_remove(&ca, 3));
    REQUIRE_FALSE(clients_session_find(&ca, 3));

    REQUIRE(clients_session_remove(&ca, 1));
    REQUIRE_FALSE(clients_session_find(&ca, 1));

    REQUIRE(clients_session_remove(&ca, 5));
    REQUIRE_FALSE(clients_session_find(&ca, 5));

    REQUIRE_FALSE(clients_session_remove(&ca, 6));

    clients_session_free_all(&ca);
  }

  SECTION("Get beginning and end") {
    create_test_list(&ca, 5);

    clients_session_get_end(&ca);
    REQUIRE(clients_session_find(&ca, 5));

    clients_session_get_beg(&ca);
    REQUIRE(clients_session_find(&ca, 1));

    clients_session_free_all(&ca);
  }

  SECTION("Free individual client") {
    create_test_list(&ca, 3);

    struct clients_session *temp = ca;
    clients_session_find(&temp, 2);
    clients_session_free(&temp);

    REQUIRE_FALSE(clients_session_find(&ca, 2));
    REQUIRE(clients_session_find(&ca, 1));
    REQUIRE(clients_session_find(&ca, 3));

    clients_session_free_all(&ca);
  }

  SECTION("Free all clients") {
    create_test_list(&ca, 5);

    clients_session_free_all(&ca);
    REQUIRE(ca == nullptr);

    // Ensure we can create a new list after freeing all
    create_test_list(&ca, 3);
    REQUIRE(clients_session_find(&ca, 1));
    REQUIRE(clients_session_find(&ca, 2));
    REQUIRE(clients_session_find(&ca, 3));

    clients_session_free_all(&ca);
  }
}
