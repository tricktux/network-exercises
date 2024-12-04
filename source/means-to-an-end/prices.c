#define _GNU_SOURCE

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <assert.h>

#include "means-to-an-end/prices.h"

void prices_init_data(struct prices* ps, size_t capacity)
{
  assert(ps != NULL);
  assert(capacity > 0);
  assert(capacity > ps->capacity);

  struct price* new_data = NULL;
  new_data = reallocarray(ps->data, sizeof(struct price), capacity);
  assert(new_data != NULL);

  ps->data = new_data;
  ps->capacity = capacity;
}

void prices_init(struct prices** pps, size_t capacity)
{
  assert(capacity > 0);

  *pps = malloc(sizeof(struct prices));
  assert(*pps != NULL);

  (*pps)->capacity = 0;
  (*pps)->data = NULL;
  prices_init_data(*pps, capacity);
  (*pps)->size = 0;
}

void prices_free(struct prices** pps)
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
void prices_push(struct prices* ps, struct price* data)
{
  assert(ps != NULL);
  assert(ps->data != NULL);
  assert(data != NULL);

  if ((ps->size + 1) >= ps->capacity) {
    prices_init_data(ps, ps->capacity * 2);
  }

  ps->data[ps->size++] = *data;
}

bool prices_duplicate_timestamp_check(struct prices* ps, int32_t timestamp)
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

void prices_binary_sort(struct prices* ps)
{
  assert(ps != NULL);
  assert(ps->data != NULL);

  if (ps->size == 0)
    return;

  for (size_t i = 1; i < ps->size; i++) {
    struct price key = ps->data[i];
    int left = 0;
    int right = i - 1;

    // Find the position to insert using binary search
    while (left <= right) {
      int mid = left + (right - left) / 2;
      if (ps->data[mid].timestamp <= key.timestamp)
        left = mid + 1;
      else
        right = mid - 1;
    }

    // Shift elements to make room for the key
    for (int j = i - 1; j >= left; j--)
      ps->data[j + 1] = ps->data[j];

    // Insert the key at the correct position
    ps->data[left] = key;
  }
}

/*If there are no samples within the requested period, or if mintime comes after
 * maxtime, the value returned must be 0.*/
int32_t prices_query(struct prices* ps, struct price_query* pq) {}
