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
  new_data = reallocarray(ps->data, sizeof(struct asset_price), capacity);
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
  int32_t mean = 0;
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


void clients_asset_init(struct clients_asset **pca, int client_id)
{
  assert(*pca == NULL);
  assert(client_id > 0);

  *pca = malloc(sizeof(struct clients_asset));
  assert(*pca != NULL);

  asset_prices_init(&(*pca)->asset, 64);
  assert((*pca)->asset != NULL);

  (*pca)->next = NULL;
  (*pca)->prev = NULL;
  (*pca)->client_id = client_id;
}

void clients_asset_get_beg(struct clients_asset **pca) {
  // Ensure we start from the beginning of the list
  struct clients_asset *prev = (*pca)->prev;
  struct clients_asset *first = *pca;
  while (prev != NULL) {
    first = prev;
    prev = prev->prev;
  }

  *pca = first;
}

void clients_asset_free(struct clients_asset **pca)
{
  assert(*pca != NULL);
  assert((*pca)->asset != NULL);

  // Adjust prev and next values now that middle is gone
  struct clients_asset *prev = NULL;
  struct clients_asset *next = NULL;
  struct clients_asset *curr = *pca;
  prev = curr->prev;
  next = curr->next;
  if (prev != NULL)
    prev->next = next;
  if (next != NULL)
    next->prev = prev;

  asset_prices_free(&(curr->asset));
  free(curr);
  curr = NULL;

  // Adjust argument pointer
  if (prev != NULL) {
    *pca = prev;
    return;
  }

  if (next != NULL) {
    *pca = next;
    return;
  }

  *pca = NULL;
}

void clients_asset_free_all(struct clients_asset **pca)
{
  assert(*pca != NULL);
  assert((*pca)->asset != NULL);

  clients_asset_get_beg(pca);

  struct clients_asset *next = NULL;
  struct clients_asset *curr = *pca;
  do {
    next = curr->next;
    asset_prices_free(&(curr->asset));
    free(curr);
    curr = NULL;
    curr = next;
  } while (curr != NULL);

  *pca = NULL;
}

void clients_asset_get_end(struct clients_asset **pca) {
  // Ensure we are at the end of the list
  struct clients_asset *next = (*pca)->next;
  struct clients_asset *last = *pca;
  while (next != NULL) {
    last = next;
    next = next->next;
  }

  *pca = last;
}

void clients_asset_add(struct clients_asset **pca, int id)
{
  assert(id > 0);

  if (*pca == NULL) {
    clients_asset_init(pca, id);
    return;
  }

  clients_asset_get_end(pca);

  clients_asset_init(&((*pca)->next), id);
  struct clients_asset *next = (*pca)->next;
  next->prev = *pca;
}

bool clients_asset_remove(struct clients_asset **pca, int id)
{
  assert(*pca != NULL);
  assert(id > 0);

  bool found = clients_asset_find(pca, id);
  if (found) {
    clients_asset_free(pca);
    return true;
  }

  return false;
}

bool clients_asset_find(struct clients_asset **pca, int id)
{
  if (*pca == NULL)
    return false;
  assert(id > 0);

  clients_asset_get_beg(pca);

  struct clients_asset *next = NULL;
  struct clients_asset *curr = *pca;
  do {
    if (curr->client_id == id) {
      *pca = curr;
      return true;
    }
    next = curr->next;
    curr = next;
  } while (curr != NULL);

  return false;
}
