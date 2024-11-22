

#include <bits/types/struct_iovec.h>
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include <stdbool.h>
#include <stdarg.h>
#include <time.h>
#include <sys/time.h>

#include "utils/queue.h"
#include "log/log.h"

void queue_init(struct queue **qu, size_t capacity)
{
  if (*qu != NULL) {
    log_error("queue_init: queue was previously allocated");
    return;
  }

  assert(capacity > 0);

  *qu = malloc(sizeof(struct queue));
  assert(qu != NULL);

  (*qu)->data = malloc(capacity);
  assert((*qu)->data != NULL);

  (*qu)->capacity = capacity;
  (*qu)->free_capacity = capacity;
  (*qu)->size = 0;
  (*qu)->head = (*qu)->data;
}

void queue_free(struct queue **qu)
{
  if (*qu == NULL) {
    log_error("queue_free: queue was previously de-allocated");
    return;
  }

  free((*qu)->data);
  free((*qu));
  *qu = NULL;
}

void queue_push(struct queue *qu, char* data, size_t size)
{
  assert(qu != NULL);
  assert(data != NULL);

  if (size == 0) {
    log_warn("queue_push: size is zero... noop");
    return;
  }

  if (qu->size + size >= qu->capacity) {
    log_error("queue_push: pushing over queue capacity... noop");
    return;
  }

  memcpy(qu->head, data, size);
  qu->head += size;
  qu->size += size;
  qu->free_capacity = qu->capacity - qu->size;
}

void queue_push_ex(struct queue *qu, size_t size)
{
  assert(qu != NULL);

  if (size == 0) {
    log_warn("queue_push: size is zero... noop");
    return;
  }

  if (qu->size + size >= qu->capacity) {
    log_error("queue_push: pushing over queue capacity... noop");
    return;
  }

  qu->head += size;
  qu->size += size;
  qu->free_capacity = qu->capacity - qu->size;
}

void queue_pop(struct queue *qu, char* data, size_t *size)
{
  assert(qu != NULL);
  assert(data != NULL);
  assert(size != NULL);

  if (qu->size == 0) {
    log_warn("queue_pop: queue is empty... noop");
    return;
  }

  if (qu->size > *size) {
    log_warn("queue_pop: not enough room in storage for queue... noop");
    return;
  }

  *size = qu->size;

  memcpy(data, qu->data, qu->size);
  qu->size = 0;
  qu->head = qu->data;
  qu->free_capacity = qu->capacity;
}
