/*
 * Copyright (c) 2020 rxi
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */

#include <stdio.h>
#include <stdarg.h>
#include <stdbool.h>
#include <time.h>
#include <sys/time.h>
#include <string.h>

#include "log.h"

#define MAX_CALLBACKS 32

typedef struct {
  log_LogFn fn;
  void* udata;
  int level;
} Callback;

static struct {
  void* udata;
  log_LockFn lock;
  int level;
  bool quiet;
  Callback callbacks[MAX_CALLBACKS];
} L;

static const char* level_strings[] = {
    "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"};

#ifdef LOG_USE_COLOR
static const char* level_colors[] = {
    "\x1b[94m", "\x1b[36m", "\x1b[32m", "\x1b[33m", "\x1b[31m", "\x1b[35m"};
#endif

inline static void format_timestamp(char* buf, size_t buf_size)
{
  struct timeval tv;
  struct tm tm_info;  // Avoid the indirection cost of using a pointer

  gettimeofday(&tv, NULL);
  localtime_r(&tv.tv_sec, &tm_info);  // Use `localtime_r` for reentrant and
                                      // potentially faster behavior

  size_t date_len = strftime(buf, buf_size, "%Y-%m-%d %H:%M:%S", &tm_info);
  // If strftime failed to format string, return early.
  if (date_len == 0)
    return;

  // snprintf is likely fine in one go if checked correctly
  if (date_len < buf_size) {
    snprintf(buf + date_len, buf_size - date_len, ".%06ld", tv.tv_usec);
  }
}

static void stdout_callback(log_Event* ev)
{
  char buf[32];  // Increased buffer size for higher resolution timestamp
  format_timestamp(buf, sizeof(buf));

  const char* filename = strrchr(ev->file, '/');
  filename = filename ? filename + 1 : ev->file;

#ifdef LOG_USE_COLOR
  fprintf(ev->udata,
          "%s %s%-5s\x1b[0m \x1b[90m%s:%d:\x1b[0m ",
          buf,
          level_colors[ev->level],
          level_strings[ev->level],
          filename,
          ev->line);
#else
  fprintf(ev->udata,
          "%s %-5s %s:%d: ",
          buf,
          level_strings[ev->level],
          filename,
          ev->line);
#endif
  vfprintf(ev->udata, ev->fmt, ev->ap);
  fprintf(ev->udata, "\n");
  fflush(ev->udata);
}

static void file_callback(log_Event* ev)
{
  char buf[64];  // Increased buffer size for higher resolution timestamp
  format_timestamp(buf, sizeof(buf));

  const char* filename = strrchr(ev->file, '/');
  filename = filename ? filename + 1 : ev->file;

  fprintf(ev->udata,
          "%s %-5s %s:%d: ",
          buf,
          level_strings[ev->level],
          filename,
          ev->line);
  vfprintf(ev->udata, ev->fmt, ev->ap);
  fprintf(ev->udata, "\n");
  fflush(ev->udata);
}

static void lock(void)
{
  if (L.lock) {
    L.lock(true, L.udata);
  }
}

static void unlock(void)
{
  if (L.lock) {
    L.lock(false, L.udata);
  }
}

const char* log_level_string(int level)
{
  return level_strings[level];
}

void log_set_lock(log_LockFn fn, void* udata)
{
  L.lock = fn;
  L.udata = udata;
}

void log_set_level(int level)
{
  L.level = level;
}

void log_set_quiet(bool enable)
{
  L.quiet = enable;
}

int log_add_callback(log_LogFn fn, void* udata, int level)
{
  for (int i = 0; i < MAX_CALLBACKS; i++) {
    if (!L.callbacks[i].fn) {
      L.callbacks[i] = (Callback) {fn, udata, level};
      return 0;
    }
  }
  return -1;
}

int log_add_fp(FILE* fp, int level)
{
  return log_add_callback(file_callback, fp, level);
}

static void init_event(log_Event* ev, void* udata)
{
  if (!ev->time) {
    time_t t = time(NULL);
    ev->time = localtime(&t);
  }
  ev->udata = udata;
}

void log_log(int level, const char* file, int line, const char* fmt, ...)
{
  log_Event ev = {
      .fmt = fmt,
      .file = file,
      .line = line,
      .level = level,
  };

  lock();

  if (!L.quiet && level >= L.level) {
    init_event(&ev, stderr);
    va_start(ev.ap, fmt);
    stdout_callback(&ev);
    va_end(ev.ap);
  }

  for (int i = 0; i < MAX_CALLBACKS && L.callbacks[i].fn; i++) {
    Callback* cb = &L.callbacks[i];
    if (level >= cb->level) {
      init_event(&ev, cb->udata);
      va_start(ev.ap, fmt);
      cb->fn(&ev);
      va_end(ev.ap);
    }
  }

  unlock();
}
