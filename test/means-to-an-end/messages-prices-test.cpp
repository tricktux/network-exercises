
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
#include "means-to-an-end/prices.h"

TEST_CASE("prices_init initializes prices structure correctly", "[prices]") {
    struct prices *ps = nullptr;
    size_t capacity = 10;

    prices_init(&ps, capacity);

    REQUIRE(ps != nullptr);
    REQUIRE(ps->capacity == capacity);
    REQUIRE(ps->size == 0);
    REQUIRE(ps->data != nullptr);

    prices_free(&ps);
    REQUIRE(ps == nullptr);
}

TEST_CASE("prices_init_data increases capacity", "[prices]") {
    struct prices *ps = nullptr;
    size_t initial_capacity = 10;
    size_t new_capacity = 20;

    prices_init(&ps, initial_capacity);
    REQUIRE(ps->capacity == initial_capacity);

    prices_init_data(ps, new_capacity);
    REQUIRE(ps->capacity == new_capacity);

    prices_free(&ps);
}

TEST_CASE("prices_push adds data correctly", "[prices]") {
    struct prices *ps = nullptr;
    size_t capacity = 2;
    prices_init(&ps, capacity);

    struct price p1 = {1, 100};
    struct price p2 = {2, 200};
    struct price p3 = {3, 300};

    SECTION("Push within capacity") {
        prices_push(ps, &p1);
        REQUIRE(ps->size == 1);
        REQUIRE(ps->data[0].timestamp == 1);
        REQUIRE(ps->data[0].price == 100);

        prices_push(ps, &p2);
        REQUIRE(ps->size == 2);
        REQUIRE(ps->data[1].timestamp == 2);
        REQUIRE(ps->data[1].price == 200);
    }

    SECTION("Push beyond capacity triggers resize") {
        prices_push(ps, &p1);
        prices_push(ps, &p2);
        prices_push(ps, &p3);

        REQUIRE(ps->size == 3);
        REQUIRE(ps->capacity == 4);  // Double the original capacity
        REQUIRE(ps->data[2].timestamp == 3);
        REQUIRE(ps->data[2].price == 300);
    }

    prices_free(&ps);
}

TEST_CASE("prices_free deallocates memory correctly", "[prices]") {
    struct prices *ps = nullptr;
    prices_init(&ps, 10);

    REQUIRE(ps != nullptr);
    REQUIRE(ps->data != nullptr);

    prices_free(&ps);

    REQUIRE(ps == nullptr);
}