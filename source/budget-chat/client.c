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
  assert(*pc != NULL);
  assert((*pc)->recv_qu != NULL);

  // Adjust prev and next values now that middle is gone
  struct client* prev = NULL;
  struct client* next = NULL;
  struct client* curr = *pc;
  prev = curr->prev;
  next = curr->next;
  if (prev != NULL)
    prev->next = next;
  if (next != NULL)
    next->prev = prev;

  queue_free(&(curr->recv_qu));
  curr->recv_qu = NULL;
  free(curr);
  curr = NULL;

  // Adjust argument pointer
  if (prev != NULL) {
    *pc = prev;
    return;
  }

  if (next != NULL) {
    *pc = next;
    return;
  }

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

bool client_validate_username(struct client* c, struct client_name_request* req)
{
  assert(c != NULL);
  assert(req != NULL);

  // TODO: change from bool to int
  // Create error codes for all the possible errors
  // To give the user meaningful error messages
  char* name = NULL;
  size_t size;
  req->valid = false;
  size = queue_pop_no_copy(c->recv_qu, &name);
  size--;  // Loose the /r
  if (size < 1) {
    strcpy(req->invalid_name_response, "Empty username provided");
    return false;
  }
  if (size >= CLIENT_MAX_NAME) {
    sprintf(req->invalid_name_response,
            "Name provided exceeds limit for number of characters: %d",
            CLIENT_MAX_NAME);
    return false;
  }

  for (size_t k = 0; k < size; k++) {
    if (!isalnum(name[k])) {
      strcpy(req->invalid_name_response, "Username must only contain alphanumeric characters");
      return false;
    }
  }

  req->name = name;
  req->size = size;
  if (!client_name_exists(c, req)) {
    strcpy(req->invalid_name_response, "Username is already taken");
    return false;
  }

  memcpy(c->name, name, size);
  c->name[size + 1] = 0;
  return true;
}

int client_handle_newclient(struct client* c)
{
  assert(c != NULL);

  struct client_name_request req;
  if (!client_validate_username(c, &req)) {
    // sendall(req.invalid_name_response)
    return -1;
  }

  // Collect list of all names in chat
  // client broadcast message from
  // client_send(c, WELCOME_MESSAGE)
  return 1;
}

int client_handle_request(struct client* c)
{
  // tokenize the messages
  // TODO: what to do with more than one message
  if (c->name[0] == 0) {
    return client_handle_newclient(c);
  }

  char* msg;
  size_t size;
  size = queue_pop_no_copy(c->recv_qu, &msg);
}

/*void client_on_valid_username(struct client* c)*/
/*{*/
/*  // To *c*/
/*  // - The room contains: etc..*/
/*  // To everybody else:*/
/*  // - *c has entered the room*/
/*}*/

void client_on_exit(struct client* c)
{
  // To everybody else:
  // - *c has entered the room
}

void client_collect_list_of_names_other_names(struct client* c)
{
  assert(*c != NULL);

  //
}

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

bool client_name_exists(struct client* c, struct client_name_request* name_req)
{
  assert(c != NULL);
  assert(name_req != NULL);

  // Does this username exists?
  // for each client
  //   if (client->id == c->id) continue;
  //   if (strcmp(client->name, c->name) == 0) return false;
  struct client* me = c;
  client_first(&c);
  struct client* next = c->next;
  struct client* last = c;
  do {
    if ((last->id != me->id)
        && (strncmp(last->name, name_req->name, name_req->size) == 0))
    {
      name_req->valid = false;
      return false;
    }

    last = next;
    next = next->next;
  } while (next != NULL);

  return true;
}

void client_send_welcome_prompt(struct client* c)
{
  int l = CLIENT_WELCOME_PROMPT_SIZE;
  int res = sendall(c->id, CLIENT_WELCOME_PROMPT, &l);
  assert(res == 0);
  assert(l == CLIENT_WELCOME_PROMPT_SIZE);
}
