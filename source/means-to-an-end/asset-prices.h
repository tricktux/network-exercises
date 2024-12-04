#ifndef INCLUDE_PRICES_H_
#define INCLUDE_PRICES_H_

#ifdef __cplusplus
extern "C" {
#endif

struct asset_price {
  int32_t timestamp;  // In epoch
  int32_t price;
};

struct asset_price_query {
  int32_t mintime;  // In epoch
  int32_t maxtime;
};

// Array structure
struct asset_prices {
  struct asset_price* data;
  size_t size;  // Number of struct price we are holding
  size_t capacity;  // Not bytes, but number struct price we can hold
};

void prices_init(struct asset_prices** pps, size_t capacity);
void prices_init_data(struct asset_prices* ps, size_t capacity);
void prices_free(struct asset_prices** pps);
// TODO: On push
//   - Check prices with the same timestamp
//     - Don't add new prices on timestamp conflict
//   - After push, sort, to keep the array sorted
void prices_push(struct asset_prices* ps, struct asset_price* data);
bool prices_duplicate_timestamp_check(struct asset_prices* ps, int32_t timestamp);
/*If there are no samples within the requested period, or if mintime comes after
 * maxtime, the value returned must be 0.*/
int32_t prices_query(struct asset_prices* ps, struct asset_price_query* pq);

#ifdef __cplusplus
}
#endif

#endif  // INCLUDE_PRICES_H_
