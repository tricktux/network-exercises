
#ifdef __cplusplus
extern "C" {
#endif

struct queue {
  char *data;
  size_t capacity;
  size_t size;
  size_t free_capacity;
  char *head;
};

void queue_init(struct queue *qu, size_t capacity);
void queue_push(struct queue *qu, char* data, size_t size);
void queue_push_ex(struct queue *qu, size_t size);
void queue_pop(struct queue *qu, char* data, size_t *size);
void queue_free(struct queue *qu);

#ifdef __cplusplus
}
#endif
