
#ifndef INCLUDE_MESSAGES_H_
#define INCLUDE_MESSAGES_H_

#define MESSAGE_SIZE 9
#define MESSAGE_INSERT 'I'
#define MESSAGE_QUERY 'Q'
#define MESSAGE_FIRST_WORD_OFFSET 1  // These are in network byte order
#define MESSAGE_SECOND_WORD_OFFSET 5  // These are in network byte order

struct __attribute__((packed)) message {
  char type;
  uint32_t first_word;
  uint32_t second_word;
};

void message_parse(struct asset_prices* ps,
                   struct queue* sdqu,
                   char* data,
                   size_t dsize);

#endif  // INCLUDE_MESSAGES_H_
