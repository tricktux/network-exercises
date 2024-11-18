
#include <stdio.h>
#include <stdarg.h>
#include <stdbool.h>
#include <time.h>
#include <sys/time.h>
#include <string.h>

#include "log/log.h"
#include "utils/utils.h"

int init_logs(FILE* fd, int log_level)
{
  if (log_add_fp(fd, log_level) == -1) {
    printf("Failed to initialize log file\n");
    return -2;
  }

  log_set_level(log_level);

  return 0;
}
