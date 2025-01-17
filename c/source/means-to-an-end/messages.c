
#include <stddef.h>
#include <stdint.h>
#include <assert.h>
#include <arpa/inet.h>

#include "utils/queue.h"
#include "means-to-an-end/asset-prices.h"
#include "means-to-an-end/messages.h"

void message_parse(struct asset_prices* ps,
                   struct queue* sdqu,
                   char* data,
                   size_t dsize)
{
  assert(ps != NULL);
  assert(sdqu != NULL);
  assert(data != NULL);
  assert(dsize > 0);

  char* pd = data;
  int k;
  int num_msgs = dsize / MESSAGE_SIZE;
  int32_t mean_p;
  struct asset_price_query qry;
  struct asset_price prc;
  struct message* msg;

  for (k = 0; k < num_msgs; k++, pd += MESSAGE_SIZE) {
    msg = (struct message*)pd;

    switch (msg->type) {
      case MESSAGE_QUERY: {
        qry.mintime = ntohl(msg->first_word);
        qry.maxtime = ntohl(msg->second_word);
        mean_p = htonl(asset_prices_query(ps, &qry));
        queue_push(sdqu, (char*)&mean_p, sizeof(int32_t));
        break;
      }
      case MESSAGE_INSERT: {
        prc.timestamp = ntohl(msg->first_word);
        prc.price = ntohl(msg->second_word);
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
