#ifndef INCLUDE_H_
#define INCLUDE_H_

#ifdef __cplusplus
extern "C" {
#endif

#define MESSAGE_DELIMETER "\n"
#define CLIENT_MAX_NAME 32
#define CLIENT_MAX_MESSAGE_SIZE 1024
#define CLIENT_MAX_COMPOSED_MESSAGE_SIZE CLIENT_MAX_MESSAGE_SIZE + CLIENT_MAX_NAME + 2
#define CLIENT_WELCOME_PROMPT "Welcome to budgetchat! What shall I call you?"
#define CLIENT_MEMBERS "* The room contains: "
#define CLIENT_MEMBERS_SIZE 21
#define CLIENT_WELCOME_PROMPT_SIZE 45
#define CLIENT_RECV_QUEUE_SIZE 1024
#define CLIENT_INVALID_NAME_RESPONSE_SIZE 128

struct client_name_request {
  char *name;
  size_t size;
  bool valid;
  char invalid_name_response[CLIENT_INVALID_NAME_RESPONSE_SIZE];
};

struct client {
  int id;   // fd
  char name[CLIENT_MAX_NAME + 1];
  size_t name_size;
  struct queue* recv_qu;
  struct client *next;
  struct client *prev;
};


void client_open(struct client **pc, int fd);
void client_close(struct client **pc);
bool client_find(struct client **pc, int id);
int client_handle_request(struct client *c);

#ifdef __cplusplus
}
#endif

#endif  // INCLUDE_CLIENT_H_
