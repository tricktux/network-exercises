
#include <stddef.h>
#include <stdint.h>
#include <arpa/inet.h>

#include "utils/queue.h"
#include "means-to-an-end/asset-prices.h"
#include "means-to-an-end/messages.h"

void message_parse(struct queue* sdqu, char* data, size_t dsize)
{
  // TODO: create and allocate struct prices
  char* pd = data;
  int k;
  int num_msgs = dsize / MESSAGE_SIZE;
  for (k = 0; k < num_msgs; pd += MESSAGE_SIZE) {
    char type = *pd;
    uint32_t* first_word = (uint32_t*)(pd + MESSAGE_FIRST_WORD_OFFSET);
    uint32_t* second_word = (uint32_t*)(pd + MESSAGE_SECOND_WORD_OFFSET);

    switch (type) {
      case MESSAGE_QUERY: {
        struct asset_price_query qry;
        qry.mintime = ntohl(*first_word);
        qry.maxtime = ntohl(*second_word);
        // Process query...
        break;
      }
      case MESSAGE_INSERT: {
        struct asset_price prc;
        prc.timestamp = ntohl(*first_word);
        prc.price = ntohl(*second_word);
        // Insert price directly into vector without additional memcpy
        /*if (p->size == p->capacity) {*/
        // Resize logic here
        /*}*/
        /*p->data[p->size++] = prc;*/
        break;
      }
      default:
        // Handle unknown message type
        break;
    }
  }
}
