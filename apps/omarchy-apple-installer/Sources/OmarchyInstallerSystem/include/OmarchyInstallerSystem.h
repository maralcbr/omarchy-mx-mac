#ifndef OMARCHY_INSTALLER_SYSTEM_H
#define OMARCHY_INSTALLER_SYSTEM_H

#include <sys/types.h>
#include <stdint.h>

int omarchy_installer_flock(int descriptor, int operation);

int omarchy_installer_spawn(pid_t *pid, const char *executable,
                            char *const argv[], char *const envp[],
                            const char *directory, int input, int output, int error, pid_t group);
int omarchy_installer_wait(pid_t pid, int *exit_status);

int omarchy_installer_group_has_children(int *present);

uint64_t omarchy_installer_process_start(pid_t pid);

#endif
