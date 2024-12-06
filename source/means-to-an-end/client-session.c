
#define _GNU_SOURCE

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <assert.h>

#include "means-to-an-end/asset-prices.h"
#include "means-to-an-end/client-session.h"

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
