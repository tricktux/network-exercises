#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include <stdbool.h>
#include <stdarg.h>
#include <time.h>
#include <sys/time.h>

#include "utils/queue.h"
#include "utils/sockets.h"
#include "budget-chat/client.h"

void client_first(struct client** pc)
{
  assert(*pc != NULL);

  // Ensure we start from the beginning of the list
  struct client* prev = (*pc)->prev;
  struct client* first = *pc;
  while (prev != NULL) {
    first = prev;
    prev = prev->prev;
  }

  *pc = first;
}

void clients_last(struct client** pc)
{
  assert(*pc != NULL);

  // Ensure we are at the end of the list
  struct client* next = (*pc)->next;
  struct client* last = *pc;
  while (next != NULL) {
    last = next;
    next = next->next;
  }

  *pc = last;
}

void client_open(struct client** pc, int fd)
{
  *pc = malloc(sizeof(struct client));
  (*pc)->name[0] = 0;
  (*pc)->id = fd;
  queue_init(&(*pc)->recv_qu, CLIENT_RECV_QUEUE_SIZE);
  (*pc)->next = NULL;
  (*pc)->prev = NULL;
}

void client_close(struct client** pc)
{
  queue_free(&((*pc)->recv_qu));
  free(*pc);
  *pc = NULL;
}

bool client_find(struct client** pc, int id)
{
  if (*pc == NULL)
    return false;
  assert(id > 0);

  client_first(pc);

  struct client* next = NULL;
  struct client* curr = *pc;
  do {
    if (curr->id == id) {
      *pc = curr;
      return true;
    }
    next = curr->next;
    curr = next;
  } while (curr != NULL);

  return false;
}

int client_handle_request(struct client* c)
{
  // tokenize the messages
  // TODO: what to do with more than one message
  if (c->name[0] == 0) {
    if (!client_set_name(c))
      return -1;

    // client broadcast message from
    // client_send(c, WELCOME_MESSAGE)
  }

  char *msg;
  size_t size;
  size = queue_pop_no_copy(c->recv_qu, &msg);
}

void client_collect_list_of_names_other_names(struct client* c) {}

void client_broadcast_message_to_all(struct client* c, char* msg, size_t size)
{
  // foreach client
  // sendall(msg, size);
}

void client_broadcast_message_from(struct client* c, char* msg, size_t size)
{
  // foreach client except c->id
  // sendall(msg, size);
}

void client_name_exists(struct client* c, struct client_name_request* name_req)
{
}

void client_send_welcome_prompt(struct client* c)
{
  int l = CLIENT_WELCOME_PROMPT_SIZE;
  int res = sendall(c->id, CLIENT_WELCOME_PROMPT, &l);
  assert(res == 0);
  assert(l == CLIENT_WELCOME_PROMPT_SIZE);
}

bool client_set_name(struct client* c)
{
  char* name;
  size_t size;
  size = queue_pop_no_copy(c->recv_qu, &name);
  if (size < 1)
    return false;
  if (size > CLIENT_MAX_NAME)
    return false;

  for (size_t k = 0; k < size; k++) {
    if (!isalnum(name[k])
      return false;
  }
  memcpy(c->name, name, size);
  c->name[size + 1] = 0;
  return true;
}

// Linked list of client
struct clients {
  struct client* curr;
};

void clients_add(struct clients** cs, int fd)
{
  assert(*cs == NULL);
  assert(fd > 0);

  *cs = malloc(sizeof(struct clients));
  assert(*ca != NULL);
}
