#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
  char executable[PATH_MAX];
  uint32_t size = sizeof(executable);

  if (_NSGetExecutablePath(executable, &size) != 0) {
    fprintf(stderr, "Executable path buffer too small.\n");
    return 1;
  }

  char *macos_dir = strrchr(executable, '/');
  if (!macos_dir) {
    fprintf(stderr, "Could not locate app executable directory.\n");
    return 1;
  }
  *macos_dir = '\0';

  char script[PATH_MAX];
  snprintf(script, sizeof(script), "%s/../Resources/launch.zsh", executable);

  char *args[] = {"/bin/zsh", script, NULL};
  execv("/bin/zsh", args);
  perror("execv");
  return 1;
}
