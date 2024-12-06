#ifndef INCLUDE_CLIENT_SESSION_H_
#define INCLUDE_CLIENT_SESSION_H_

#ifdef __cplusplus
extern "C" {
#endif

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

#endif  // INCLUDE_CLIENT-SESSION_H_
