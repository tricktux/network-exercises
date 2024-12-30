
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
#include "utils/queue.h"
#include "budget-chat/client.h"


TEST_CASE("client_open creates a new client", "[client]") {
    struct client* c = nullptr;
    int fd = 10;

    client_open(&c, fd);

    REQUIRE(c != nullptr);
    REQUIRE(c->id == fd);
    REQUIRE(c->name[0] == 0);
    REQUIRE(c->recv_qu != nullptr);
    REQUIRE(c->next == nullptr);
    REQUIRE(c->prev == nullptr);

    // Clean up
    queue_free(&(c->recv_qu));
    free(c);
}

TEST_CASE("client_close removes a client", "[client]") {
    struct client* c = nullptr;
    int fd = 10;

    client_open(&c, fd);
    REQUIRE(c != nullptr);

    client_close(&c);
    REQUIRE(c == nullptr);
}

TEST_CASE("client_find locates a client by id", "[client]") {
    struct client* c = nullptr;
    int fd1 = 10, fd2 = 20, fd3 = 30;

    client_open(&c, fd1);
    client_open(&(c->next), fd2);
    client_open(&(c->next->next), fd3);

    SECTION("Finding existing clients") {
        struct client* found = c;
        REQUIRE(client_find(&found, fd1));
        REQUIRE(found->id == fd1);

        found = c;
        REQUIRE(client_find(&found, fd2));
        REQUIRE(found->id == fd2);

        found = c;
        REQUIRE(client_find(&found, fd3));
        REQUIRE(found->id == fd3);
    }

    SECTION("Finding non-existent client") {
        struct client* found = c;
        REQUIRE_FALSE(client_find(&found, 40));
    }

    // Clean up
    while (c != nullptr) {
        struct client* next = c->next;
        queue_free(&(c->recv_qu));
        free(c);
        c = next;
    }
}

TEST_CASE("client_handle_request processes client requests", "[client]") {
    struct client* c = nullptr;
    int fd = 10;

    client_open(&c, fd);

    SECTION("New client without name") {
        char* test_name = "TestUser\r";
        queue_push(c->recv_qu, test_name, strlen(test_name));

        int result = client_handle_request(c);
        REQUIRE(result == 1);
        REQUIRE(strcmp(c->name, "TestUser") == 0);
    }

    SECTION("Existing client with message") {
        strcpy(c->name, "ExistingUser");
        char* test_message = "Hello, World!\r";
        queue_push(c->recv_qu, test_message, strlen(test_message));

        int result = client_handle_request(c);
        REQUIRE(result == 1);
    }

    // Clean up
    queue_free(&(c->recv_qu));
    free(c);
}

TEST_CASE("client_handle_request processes new client requests", "[client]") {
  struct client* c1 = nullptr;
  struct client* c2 = nullptr;
  int fd1 = 10, fd2 = 20;

  client_open(&c1, fd1);
  client_open(&c2, fd2);
  c1->next = c2;
  c2->prev = c1;

  SECTION("New client with unique name") {
    char* test_name = "UniqueUser\r";
    queue_push(c1->recv_qu, test_name, strlen(test_name));

    int result = client_handle_request(c1);
    REQUIRE(result == 1);
    REQUIRE(strcmp(c1->name, "UniqueUser") == 0);
  }

  SECTION("New client with existing name") {
    strcpy(c2->name, "ExistingUser");
    c2->name_size = strlen("ExistingUser");

    char* test_name = "ExistingUser\r";
    queue_push(c1->recv_qu, test_name, strlen(test_name));

    int result = client_handle_request(c1);
    REQUIRE(result == -1);
    REQUIRE(c1->name[0] == 0);  // Name should not be set
  }

  SECTION("New client with empty name") {
    char* test_name = "\r";
    queue_push(c1->recv_qu, test_name, strlen(test_name));

    int result = client_handle_request(c1);
    REQUIRE(result == -1);
    REQUIRE(c1->name[0] == 0);
  }

  SECTION("New client with too long name") {
    char long_name[CLIENT_MAX_NAME + 10];
    memset(long_name, 'a', CLIENT_MAX_NAME + 9);
    long_name[CLIENT_MAX_NAME + 9] = '\r';

    queue_push(c1->recv_qu, long_name, CLIENT_MAX_NAME + 10);

    int result = client_handle_request(c1);
    REQUIRE(result == -1);
    REQUIRE(c1->name[0] == 0);
  }

  SECTION("New client with non-alphanumeric characters") {
    char* test_name = "Invalid!User@123\r";
    queue_push(c1->recv_qu, test_name, strlen(test_name));

    int result = client_handle_request(c1);
    REQUIRE(result == -1);
    REQUIRE(c1->name[0] == 0);
  }

  // Clean up
  queue_free(&(c1->recv_qu));
  queue_free(&(c2->recv_qu));
  free(c1);
  free(c2);
}
