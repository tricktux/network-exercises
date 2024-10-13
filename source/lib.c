#include "lib.h"

#include <assert.h>
#include <hedley.h>
#include <json-c/json_object.h>
#include <json-c/json_tokener.h>
#include <stdlib.h>
#include <string.h>

static char const json[] = "{\"name\":\"network-exercises\"}";

struct library create_library(void)
{
  struct library lib = {NULL};
  char* name = NULL;

  struct json_tokener* tokener = json_tokener_new();
  if (tokener == NULL) {
    goto exit;
  }

  struct json_object* object =
      json_tokener_parse_ex(tokener, json, sizeof(json));
  if (object == NULL) {
    goto cleanup_tokener;
  }

  struct json_object* name_object = NULL;
  if (json_object_object_get_ex(object, "name", &name_object) == 0) {
    goto cleanup_object;
  }

  char const* json_name = json_object_get_string(name_object);
  if (json_name == NULL) {
    goto cleanup_object;
  }

  int name_size = json_object_get_string_len(name_object);
  name = malloc((size_t)name_size + 1);
  if (name == NULL) {
    goto cleanup_object;
  }

  (void)memcpy(name, json_name, name_size);
  name[name_size] = '\0';
  lib.name = name;

cleanup_object:
  if (json_object_put(object) != 1) {
    assert(0);
  }

cleanup_tokener:
  json_tokener_free(tokener);

exit:
  return lib;
}

void destroy_library(struct library* lib)
{
  free(HEDLEY_CONST_CAST(void*, lib->name));
}
