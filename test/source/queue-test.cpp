#define CATCH_CONFIG_MAIN

#include <bits/types/struct_iovec.h>
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include <stdbool.h>
#include <stdarg.h>
#include <time.h>
#include <sys/time.h>

#include <catch2/catch.hpp>
#include "utils/queue.h"
#include <cstring>

struct queue* instantiate_and_fill(size_t capacity, const char* data) {
  struct queue* qu = nullptr;
  queue_init(qu, capacity);
  if (data != nullptr) {
    queue_push(qu, const_cast<char*>(data), strlen(data));
  }
  return qu;
}

TEST_CASE("Queue Initialization") {
  struct queue* qu = nullptr;
  queue_init(qu, 10);

  REQUIRE(qu != nullptr);
  REQUIRE(qu->capacity == 10);
  REQUIRE(qu->size == 0);
  REQUIRE(qu->free_capacity == 10);
  REQUIRE(qu->head == qu->data);

  queue_free(qu);
}

TEST_CASE("Queue Free") {
  struct queue* qu = instantiate_and_fill(10, "hello");

  queue_free(qu);

  REQUIRE(qu == nullptr); // Memory should be freed, null check after is good practice.
}

TEST_CASE("Queue Push and Pop") {
  const char* data = "hello";
  size_t data_size = strlen(data);

  struct queue* qu = instantiate_and_fill(10, nullptr);

  SECTION("Push") {
    queue_push(qu, const_cast<char*>(data), data_size);

    REQUIRE(qu->size == data_size);
    REQUIRE(qu->free_capacity == qu->capacity - data_size);
  }

  SECTION("Pop") {
    char* buffer = new char[data_size];
    queue_pop(qu, buffer, &data_size);

    REQUIRE(std::strcmp(buffer, data) == 0);
    REQUIRE(qu->size == 0);
    REQUIRE(qu->free_capacity == qu->capacity);
    delete[] buffer;
  }

  queue_free(qu);
}

TEST_CASE("Queue Edge Cases") {
  struct queue* qu = instantiate_and_fill(5, "1234");

  SECTION("Push Over Capacity") {
    queue_push(qu, const_cast<char*>("world"), 5);

    // As it should over push the capacity, size should remain the same.
    REQUIRE(qu->size == 4);
    REQUIRE(qu->free_capacity == 1);
  }

  SECTION("Pop Empty Queue") {
    queue_pop(qu, const_cast<char*>(""), nullptr);

    REQUIRE(qu->size == 0);
    REQUIRE(qu->free_capacity == qu->capacity);
  }

  queue_free(qu);
}