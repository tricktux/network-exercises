
#include <stddef.h>
#include <stdint.h>

#include "means-to-an-end/prices.h"

void prices_init(struct prices **v, size_t capacity) {

}
void prices_free(struct prices **v) {

}
// TODO: On push
//   - Check prices with the same timestamp
//     - Don't add new prices on timestamp conflict
//   - After push, sort, to keep the array sorted
void prices_push(struct prices *v, struct price* data) {

}
// Get pointer to the data
/*size_t vector_peek(struct vector **v, void** data);*/
void prices_sort(struct prices *p) {

}
/*If there are no samples within the requested period, or if mintime comes after maxtime, the value returned must be 0.*/
int32_t prices_query(struct prices *p, struct price_query *q) {

}
