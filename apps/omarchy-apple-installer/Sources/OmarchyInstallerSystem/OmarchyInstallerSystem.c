#include "OmarchyInstallerSystem.h"

#include <sys/file.h>

int omarchy_installer_flock(int descriptor, int operation) {
  return flock(descriptor, operation);
}
