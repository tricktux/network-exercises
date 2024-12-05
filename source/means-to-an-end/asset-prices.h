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

void asset_prices_init(struct asset_prices** pps, size_t capacity);
void asset_prices_init_data(struct asset_prices* ps, size_t capacity);
void asset_prices_free(struct asset_prices** pps);
// TODO: On push
//   - Check prices with the same timestamp
//     - Don't add new prices on timestamp conflict
//   - After push, sort, to keep the array sorted
void asset_prices_push(struct asset_prices* ps, struct asset_price* data);
bool asset_prices_duplicate_timestamp_check(struct asset_prices* ps, int32_t timestamp);
/*If there are no samples within the requested period, or if mintime comes after
 * maxtime, the value returned must be 0.*/
int32_t asset_prices_query(struct asset_prices* ps, struct asset_price_query* pq);


struct clients_asset {
  int client_id;   // Client's file descriptor
  struct asset_prices *asset;
  struct client_asset *next;
  struct client_asset *prev;
};

void clients_asset_init(struct clients_asset **pca, int client_id);
void clients_asset_free_all(struct clients_asset **pca);
void clients_asset_add(struct clients_asset **pca, int id);
bool clients_asset_remove(struct clients_asset **pca, int id);
bool clients_asset_find(struct clients_asset **pca, int id);
void clients_asset_get_end(struct clients_asset **pca);
void clients_asset_get_beg(struct clients_asset **pca);
void clients_asset_free(struct clients_asset **pca);

#ifdef __cplusplus
}
#endif

#endif  // INCLUDE_PRICES_H_
