
#define _GNU_SOURCE

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <assert.h>

#include "utils/queue.h"
#include "means-to-an-end/asset-prices.h"
#include "means-to-an-end/client-session.h"

void clients_session_init(struct clients_session **pca, int client_id)
{
  assert(*pca == NULL);
  assert(client_id > 0);

  *pca = malloc(sizeof(struct clients_session));
  assert(*pca != NULL);

  asset_prices_init(&(*pca)->asset, 16);
  assert((*pca)->asset != NULL);

  (*pca)->recv_qu = NULL;
  queue_init(&(*pca)->recv_qu, 512);
  assert((*pca)->recv_qu != NULL);

  (*pca)->next = NULL;
  (*pca)->prev = NULL;
  (*pca)->client_id = client_id;
}

void clients_session_get_beg(struct clients_session **pca) {
  assert(*pca != NULL);

  // Ensure we start from the beginning of the list
  struct clients_session *prev = (*pca)->prev;
  struct clients_session *first = *pca;
  while (prev != NULL) {
    first = prev;
    prev = prev->prev;
  }

  *pca = first;
}

void clients_session_free(struct clients_session **pca)
{
  assert(*pca != NULL);
  assert((*pca)->asset != NULL);

  // Adjust prev and next values now that middle is gone
  struct clients_session *prev = NULL;
  struct clients_session *next = NULL;
  struct clients_session *curr = *pca;
  prev = curr->prev;
  next = curr->next;
  if (prev != NULL)
    prev->next = next;
  if (next != NULL)
    next->prev = prev;

  asset_prices_free(&(curr->asset));
  curr->asset = NULL;
  queue_free(&(curr->recv_qu));
  curr->recv_qu = NULL;
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

void clients_session_free_all(struct clients_session **pca)
{
  assert(*pca != NULL);
  assert((*pca)->asset != NULL);

  clients_session_get_beg(pca);
  while (*pca != NULL)
    clients_session_free(pca);
}

void clients_session_get_end(struct clients_session **pca) {
  assert(*pca != NULL);

  // Ensure we are at the end of the list
  struct clients_session *next = (*pca)->next;
  struct clients_session *last = *pca;
  while (next != NULL) {
    last = next;
    next = next->next;
  }

  *pca = last;
}

void clients_session_add(struct clients_session **pca, int id)
{
  assert(id > 0);

  if (*pca == NULL) {
    clients_session_init(pca, id);
    return;
  }

  clients_session_get_end(pca);

  clients_session_init(&((*pca)->next), id);
  struct clients_session *next = (*pca)->next;
  next->prev = *pca;
}

bool clients_session_remove(struct clients_session **pca, int id)
{
  assert(*pca != NULL);
  assert(id > 0);

  bool found = clients_session_find(pca, id);
  if (found) {
    clients_session_free(pca);
    return true;
  }

  return false;
}

bool clients_session_find(struct clients_session **pca, int id)
{
  if (*pca == NULL)
    return false;
  assert(id > 0);

  clients_session_get_beg(pca);

  struct clients_session *next = NULL;
  struct clients_session *curr = *pca;
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
