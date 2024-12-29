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

  // Send welcome message
  int l = CLIENT_WELCOME_PROMPT_SIZE;
  int res = sendall((*pc)->id, CLIENT_WELCOME_PROMPT, &l);
  assert(res == 0);
  assert(l == CLIENT_WELCOME_PROMPT_SIZE);
}

void client_broadcast_message_from(struct client* c, char* msg, size_t size)
{
  assert(c != NULL);

  int r, l;
  struct client* me = c;
  client_first(&c);
  struct client* next = c->next;
  struct client* last = c;
  do {
    if ((last->id != me->id) && (last->name[0] != 0)) {
      l = (int) size;
      r = sendall(c->id, msg, &l);
      assert(r == 0);
    }

    last = next;
    next = next->next;
  } while (next != NULL);
}

void client_close(struct client** pc)
{
  assert(*pc != NULL);
  assert((*pc)->recv_qu != NULL);

  // Tell everybody that this person left the chat
  char newuser[128];
  int size = sprintf(newuser, "* '%s' has left the chat", (*pc)->name);
  client_broadcast_message_from(*pc, newuser, (size_t) size);

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
    if ((last->id != me->id) && (last->name[0] != 0)
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
  size = (size_t) queue_pop_no_copy(c->recv_qu, &name);
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
  c->name_size = size;
  return true;
}

void client_collect_list_of_names_other_names(struct client* c)
{
  assert(c != NULL);
  assert(queue_empty(c->recv_qu));

  struct client* me = c;
  client_first(&c);
  struct client* next = c->next;
  struct client* last = c;
  bool first = false;
  queue_push(me->recv_qu,  CLIENT_MEMBERS, CLIENT_MEMBERS_SIZE);
  do {
    if ((last->id != me->id) && (last->name[0] != 0)) {
      if (!first)
        queue_push(me->recv_qu, ", ", 2);
      queue_push(me->recv_qu, last->name, last->name_size);
    }

    last = next;
    next = next->next;
  } while (next != NULL);
}

void client_broadcast_message_to_all(struct client* c, char* msg, size_t size)
{
  assert(c != NULL);

  int r, l;
  client_first(&c);
  struct client* next = c->next;
  struct client* last = c;
  do {
    if (last->name[0] != 0) {
      l = (int) size;
      r = sendall(c->id, msg, &l);
      assert(r == 0);
    }

    last = next;
    next = next->next;
  } while (next != NULL);
}

void client_send_welcome_prompt(struct client* c)
{
  int l = CLIENT_WELCOME_PROMPT_SIZE;
  int res = sendall(c->id, CLIENT_WELCOME_PROMPT, &l);
  assert(res == 0);
  assert(l == CLIENT_WELCOME_PROMPT_SIZE);
}

int client_handle_newclient(struct client* c)
{
  assert(c != NULL);

  struct client_name_request req;
  if (!client_validate_username(c, &req)) {
    int l = strlen(req.invalid_name_response);
    int r = sendall(c->id, req.invalid_name_response, &l);
    assert(r == 0);
    return -1;
  }

  // Send new client list of all names in chat
  client_collect_list_of_names_other_names(c);
  char* msg;
  size_t size = queue_pop_no_copy(c->recv_qu, &msg);
  int r = sendall(c->id, msg, &size);
  assert(r == 0);

  // Send all users name of the new user
  char newuser[128];
  size = sprintf(newuser, "* '%s' has joined the chat", c->name);
  client_broadcast_message_from(c, newuser, size);
  return 1;
}

int client_handle_request(struct client* c)
{
  // tokenize the messages
  // TODO: what to do with more than one message
  if (c->name[0] == 0) {
    return client_handle_newclient(c);
  }

  // TODO: 
  char* msg;
  size_t size = queue_pop_no_copy(c->recv_qu, &msg);
  size--;  // Loose the /r
  // Ignoring emtpy and messages that exceed
  if (size == 0)
    return 0;
  if (size > CLIENT_MAX_MESSAGE_SIZE)
    return 0;

  char mesg[CLIENT_MAX_COMPOSED_MESSAGE_SIZE];
  size = snprintf(mesg, CLIENT_MAX_COMPOSED_MESSAGE_SIZE, "[%s] %s", c->name, msg);
  client_broadcast_message_from(c, mesg, size);
}
