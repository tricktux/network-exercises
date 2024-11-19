
struct ring_buffer {
  char *data;
  size_t capacity;
  size_t size;
  char *tail;
  char *head;
};

void ring_buffer_init(struct ring_buffer *rb, size_t capacity, size_t size);
void ring_buffer_write(struct ring_buffer *rb, char* data, size_t size);
void ring_buffer_read(struct ring_buffer *rb, char* data, size_t size);
void ring_buffer_free(struct ring_buffer *rb);
