#define _GNU_SOURCE

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <assert.h>

#include "means-to-an-end/asset-prices.h"

void asset_prices_init_data(struct asset_prices* ps, size_t capacity)
{
  assert(ps != NULL);
  assert(capacity > 0);
  assert(capacity > ps->capacity);

  struct asset_price* new_data = NULL;
  new_data = reallocarray(ps->data, capacity, sizeof(struct asset_price));
  assert(new_data != NULL);

  ps->data = new_data;
  ps->capacity = capacity;
}

void asset_prices_init(struct asset_prices** pps, size_t capacity)
{
  assert(capacity > 0);

  *pps = malloc(sizeof(struct asset_prices));
  assert(*pps != NULL);

  (*pps)->capacity = 0;
  (*pps)->data = NULL;
  asset_prices_init_data(*pps, capacity);
  (*pps)->size = 0;
}

void asset_prices_free(struct asset_prices** pps)
{
  assert(*pps != NULL);
  assert((*pps)->data != NULL);

  free((*pps)->data);
  free(*pps);
  *pps = NULL;
}

// TODO: On push
//   - Check prices with the same timestamp
//     - Don't add new prices on timestamp conflict
//   - After push, sort, to keep the array sorted
void asset_prices_push(struct asset_prices* ps, struct asset_price* data)
{
  assert(ps != NULL);
  assert(ps->data != NULL);
  assert(data != NULL);

  if ((ps->size + 1) >= ps->capacity) {
    asset_prices_init_data(ps, ps->capacity * 2);
  }

  ps->data[ps->size++] = *data;
}

bool asset_prices_duplicate_timestamp_check(struct asset_prices* ps, int32_t timestamp)
{
  assert(ps != NULL);
  assert(ps->data != NULL);

  size_t k = 0;
  for (; k < ps->size; k++) {
    if (ps->data[k].timestamp == timestamp)
      return true;
  }

  return false;
}

/*If there are no samples within the requested period, or if mintime comes after
 * maxtime, the value returned must be 0.*/
int32_t asset_prices_query(struct asset_prices* ps, struct asset_price_query* pq)
{
  assert(ps != NULL);
  assert(ps->data != NULL);
  assert(pq != NULL);

  if (ps->size == 0)
    return 0;

  size_t k = 0;
  int64_t mean = 0;
  int32_t num_prices = 0;
  int32_t curr_ts = 0;
  for (; k < ps->size; k++) {
    curr_ts = ps->data[k].timestamp;
    if ((pq->mintime <= curr_ts) && (curr_ts <= pq->maxtime)) {
      mean += ps->data[k].price;
      num_prices++;
    }
  }

  return num_prices == 0 ? 0 : mean / num_prices;
}
