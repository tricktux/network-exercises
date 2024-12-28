
#define MESSAGE_DELIMETER "\n"
#define CLIENT_MAX_NAME 32
#define CLIENT_WELCOME_PROMPT "Welcome to budgetchat! What shall I call you?"
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
  struct queue* recv_qu;
  struct client *next;
  struct client *prev;
};


void client_open(struct client **pc, int fd);
void client_close(struct client **pc);
bool client_find(struct client **pc, int fd);
int client_handle_request(struct client *c);
void client_collect_list_of_names_other_names(struct client *c);
void client_broadcast_message_to_all(struct client *c, char *msg, size_t size);
void client_broadcast_message_from(struct client *c, char *msg, size_t size);
void client_name_exists(struct client *c, struct client_name_request *name_req);
void client_send_welcome_prompt(struct client *c);
bool client_set_name(struct client *c);
