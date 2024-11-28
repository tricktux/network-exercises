#ifndef INCLUDE_UTILS_QUEUE_H_
#define INCLUDE_UTILS_QUEUE_H_

#ifdef __cplusplus
extern "C" {
#endif

struct queue {
  char* data;
  size_t capacity;
  size_t size;
  size_t free_capacity;
  char* head;
};

void queue_init(struct queue** qu, size_t capacity);
void queue_push(struct queue* qu, char* data, size_t size);
void queue_push_ex(struct queue* qu, size_t size);
void queue_pop(struct queue* qu, char* data, size_t* size);
void queue_free(struct queue** qu);
void queue_reset(struct queue* qu);
int queue_pop_no_copy(struct queue* qu, char** data);

#ifdef __cplusplus
}
#endif

#endif  // INCLUDE_UTILS_QUEUE_H_
