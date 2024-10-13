#include <stddef.h>
#include <stdio.h>

#include "lib.h"

int main(int argc, char const* argv[])
{
  struct library lib = create_library();
  int result = 0;

  (void)argc;
  (void)argv;

  if (lib.name == NULL) {
    if (puts("Hello from unknown! (JSON parsing failed in library)") == EOF) {
      result = 1;
    }
  } else {
    if (printf("Hello from %s!", lib.name) < 0) {
      result = 1;
    }
  }

  destroy_library(&lib);
  return result;
}
