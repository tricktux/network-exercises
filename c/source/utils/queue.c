

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

void queue_init_data(struct queue* qu, size_t capacity)
{
  assert(qu != NULL);

  if (capacity == 0)
    return;

  if (qu->capacity > capacity)
    return;

  char* new_data = NULL;
  new_data = realloc(qu->data, capacity);
  assert(new_data != NULL);

  qu->data = new_data;
  qu->capacity = capacity;
  qu->free_capacity = capacity - qu->size;
  qu->head = qu->data + qu->size;
}

void queue_expand_capacity(struct queue* qu, size_t size)
{
  assert(qu != NULL);
  if (size == 0)
    return;

  if (qu->size + size
      < ((size_t)((double)qu->free_capacity * QUEUE_FREE_CAP_BUFFER)))
    return;

  size_t new_cap = qu->capacity * 2, new_free_cap = new_cap - qu->size;
  while (qu->size + size
         >= (size_t)((double)new_free_cap * QUEUE_FREE_CAP_BUFFER))
  {
    new_cap *= 2;
    new_free_cap = new_cap - qu->size;
  }
  queue_init_data(qu, new_cap);
}

/**
 * @brief Initializes a queue with the specified capacity.
 *
 * This function allocates memory for a queue structure and initializes it
 * with given capacity. If the queue is already allocated, an error is logged.
 *
 * @param qu A pointer to a pointer to the queue to be initialized.
 * @param capacity The maximum number of bytes the queue can hold. Must be
 * greater than 0.
 */
void queue_init(struct queue** qu, size_t capacity)
{
  if (*qu != NULL) {
    log_error("queue_init: queue was previously allocated");
    return;
  }

  assert(capacity > 0);

  *qu = malloc(sizeof(struct queue));
  assert(qu != NULL);

  (*qu)->capacity = 0;
  (*qu)->size = 0;
  (*qu)->data = NULL;
  queue_init_data(*qu, capacity);
}

/**
 * @brief Frees the memory allocated for the queue.
 *
 * This function deallocates the memory for the queue structure and its data.
 * If the queue is already freed, an error is logged.
 *
 * @param qu A pointer to a pointer to the queue to be deallocated.
 */
void queue_free(struct queue** qu)
{
  if (*qu == NULL) {
    log_error("queue_free: queue was previously de-allocated");
    return;
  }

  free((*qu)->data);
  free((*qu));
  *qu = NULL;
}

/**
 * @brief Pushes data onto the queue.
 *
 * This function adds a specified amount of data to the queue if there is
 * enough capacity. If the queue is full or the data size is zero, it logs
 * an appropriate warning or error.
 *
 * @param qu A pointer to the queue where the data will be added.
 * @param data A pointer to the data to be pushed onto the queue.
 * @param size The size of the data to be pushed onto the queue.
 */
void queue_push(struct queue* qu, char* data, size_t size)
{
  assert(qu != NULL);
  assert(data != NULL);

  if (size == 0) {
    log_trace("queue_push: size is zero... noop");
    return;
  }

  if (qu->size + size
      >= (size_t)((double)qu->free_capacity * QUEUE_FREE_CAP_BUFFER))
  {
    queue_expand_capacity(qu, size);
    log_info("queue_push: expanding current capacity to %d\n", qu->capacity);
  }

  memcpy(qu->head, data, size);
  qu->head += size;
  qu->size += size;
  qu->free_capacity = qu->capacity - qu->size;
}

/**
 * @brief Pushes an empty space of a specified size onto the queue.
 *
 * This function reserves space in the queue without copying data. It should
 * increase the size of the queue by the specified size, provided that there
 * is enough capacity.
 *
 * @param qu A pointer to the queue where the space will be reserved.
 * @param size The size of the space to be reserved.
 */
void queue_push_ex(struct queue* qu, size_t size)
{
  assert(qu != NULL);

  if (size == 0) {
    log_warn("queue_push: size is zero... noop");
    return;
  }

  if (qu->size + size
      >= (size_t)((double)qu->free_capacity * QUEUE_FREE_CAP_BUFFER))
  {
    queue_expand_capacity(qu, size);
    log_info("queue_push(%p): expanding capacity to %d", qu, qu->capacity);
  }

  qu->head += size;
  qu->size += size;
  qu->free_capacity = qu->capacity - qu->size;
}

/**
 * @brief Pops data from the queue into the provided buffer.
 *
 * This function copies the current data from the queue into the provided
 * buffer. It resets the queue's size to zero afterward. If there is
 * insufficient space or the queue is empty, it logs warnings.
 *
 * @param qu A pointer to the queue from which data will be popped.
 * @param data A pointer to the buffer where popped data will be stored.
 * @param size A pointer to a size variable that will be updated with
 *             the size of the data popped from the queue.
 */
void queue_pop(struct queue* qu, char* data, size_t* size)
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

/**
 * @brief Resets the queue to its initial state.
 *
 * This function sets the size of the queue to zero and resets the head
 * pointer to the data pointer.
 *
 * @param qu A pointer to the queue to be reset.
 */
void queue_reset(struct queue* qu)
{
  assert(qu != NULL);

  qu->size = 0;
  qu->head = qu->data;
  qu->free_capacity = qu->capacity;
}

/**
 * @brief Pops data from the queue without copying.
 *
 * This function retrieves a pointer to the queue data without copying
 * it to another buffer. After calling this function, the queue is reset
 * to zero size. If the queue is empty, it logs a warning.
 *
 * @param qu A pointer to the queue from which data will be popped.
 * @param data A pointer to a pointer where the address of the queue data
 *             will be stored.
 * @return The size of the data in the queue (0 if empty).
 */
int queue_pop_no_copy(struct queue* qu, char** data)
{
  assert(qu != NULL);
  assert(data != NULL);

  if (qu->size == 0) {
    log_warn("queue_pop: queue is empty... noop");
    return 0;
  }

  *data = qu->data;
  int s = (int)qu->size;

  qu->size = 0;
  qu->head = qu->data;
  qu->free_capacity = qu->capacity;

  return s;
}

int queue_peek(struct queue* qu, char** data)
{
  assert(qu != NULL);
  assert(data != NULL);

  if (qu->size == 0) {
    log_warn("queue_pop: queue is empty... noop");
    return 0;
  }

  *data = qu->data;
  return (int)qu->size;
}

bool queue_empty(struct queue *qu)
{
  assert(qu != NULL);

  return (qu->size > 0);
}
