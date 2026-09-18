#include "OmarchyInstallerSystem.h"

#include <sys/file.h>

int omarchy_installer_flock(int descriptor, int operation) {
  return flock(descriptor, operation);
}

#include <spawn.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>

// Foundation.Process may create a separate process group. Mutating children
// must stay in the worker's group so its durable execution lease covers them.
int omarchy_installer_spawn(pid_t *pid, const char *executable,
                            char *const argv[], char *const envp[],
                            const char *directory, int input, int output, int error, pid_t group) {
  posix_spawn_file_actions_t actions;
  posix_spawnattr_t attributes;
  int result = posix_spawn_file_actions_init(&actions);
  if (result) return result;
  result = posix_spawnattr_init(&attributes);
  if (result) { posix_spawn_file_actions_destroy(&actions); return result; }
#define ACTION(call) do { result = (call); if (result) goto done; } while (0)
  // FileHandle.nullDevice is a Foundation sentinel, not an open descriptor.
  if (input < 0) { ACTION(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)); }
  else { ACTION(posix_spawn_file_actions_adddup2(&actions, input, STDIN_FILENO)); }
  if (output < 0) { ACTION(posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)); }
  else { ACTION(posix_spawn_file_actions_adddup2(&actions, output, STDOUT_FILENO)); }
  if (error < 0) { ACTION(posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)); }
  else { ACTION(posix_spawn_file_actions_adddup2(&actions, error, STDERR_FILENO)); }
  ACTION(posix_spawn_file_actions_addchdir_np(&actions, directory));
  // Only the three explicit standard descriptors cross the exec boundary.
  ACTION(posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP));
  ACTION(posix_spawnattr_setpgroup(&attributes, group));
  result = posix_spawn(pid, executable, &actions, &attributes, argv, envp);
done:
  posix_spawnattr_destroy(&attributes);
  posix_spawn_file_actions_destroy(&actions);
  return result;
#undef ACTION
}

int omarchy_installer_wait(pid_t pid, int *exit_status) {
  int status;
  pid_t result;
  do { result = waitpid(pid, &status, 0); } while (result < 0 && errno == EINTR);
  if (result < 0) return errno;
  *exit_status = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
  return 0;
}

#include <libproc.h>

int omarchy_installer_group_has_children(int *present) {
  pid_t members[4096];
  int bytes = proc_listpids(PROC_PGRP_ONLY, (uint32_t)getpgrp(), members, sizeof(members));
  if (bytes <= 0 || bytes >= (int)sizeof(members) || bytes % sizeof(pid_t)) return EIO;
  int found_self = 0;
  *present = 0;
  for (int i = 0; i < bytes / (int)sizeof(pid_t); i++) {
    if (members[i] == getpid()) found_self = 1;
    else if (members[i] > 0) *present = 1;
  }
  return found_self ? 0 : EIO;
}

uint64_t omarchy_installer_process_start(pid_t pid) {
  struct proc_bsdinfo info;
  if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info)) return 0;
  return info.pbi_start_tvsec * 1000000ULL + info.pbi_start_tvusec;
}
