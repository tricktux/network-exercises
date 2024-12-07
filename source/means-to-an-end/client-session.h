#ifndef INCLUDE_CLIENT_SESSION_H_
#define INCLUDE_CLIENT_SESSION_H_

#ifdef __cplusplus
extern "C" {
#endif

struct clients_session {
  int client_id;   // Client's file descriptor
  struct asset_prices *asset;
  struct queue *recv_qu;
  struct clients_session *next;
  struct clients_session *prev;
};

void clients_session_init(struct clients_session **pca, int client_id);
void clients_session_free_all(struct clients_session **pca);
void clients_session_add(struct clients_session **pca, int id);
bool clients_session_remove(struct clients_session **pca, int id);
bool clients_session_find(struct clients_session **pca, int id);
void clients_session_get_end(struct clients_session **pca);
void clients_session_get_beg(struct clients_session **pca);
void clients_session_free(struct clients_session **pca);

#ifdef __cplusplus
}
#endif

#endif  // INCLUDE_CLIENT-SESSION_H_
