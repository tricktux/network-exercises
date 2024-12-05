
#include <stddef.h>
#include <stdint.h>
#include <assert.h>
#include <arpa/inet.h>

#include "utils/queue.h"
#include "means-to-an-end/asset-prices.h"
#include "means-to-an-end/messages.h"

void message_parse(struct asset_price *ps, struct queue* sdqu, char* data, size_t dsize)
{
  assert(ps != NULL);
  assert(sdqu != NULL);
  assert(data != NULL);
  assert(dsize > 0);

  char* pd = data;
  int k;
  int num_msgs = dsize / MESSAGE_SIZE;
  for (k = 0; k < num_msgs; k++, pd += MESSAGE_SIZE) {
    char type = pd[0];
    uint32_t* first_word = (uint32_t*)(pd + MESSAGE_FIRST_WORD_OFFSET);
    uint32_t* second_word = (uint32_t*)(pd + MESSAGE_SECOND_WORD_OFFSET);

    switch (type) {
      case MESSAGE_QUERY: {
        struct asset_price_query qry;
        qry.mintime = ntohl(*first_word);
        qry.maxtime = ntohl(*second_word);
        int32_t mean_p = htonl(asset_prices_query(ps, &qry));
        queue_push(sdqu, (char *) &mean_p, sizeof(int32_t));
        break;
      }
      case MESSAGE_INSERT: {
        struct asset_price prc;
        prc.timestamp = ntohl(*first_word);
        prc.price = ntohl(*second_word);
        if (!asset_prices_duplicate_timestamp_check(ps, prc.timestamp))
          asset_prices_push(ps, &prc);
        break;
      }
      default:
        // Handle unknown message type
        break;
    }
  }
}
