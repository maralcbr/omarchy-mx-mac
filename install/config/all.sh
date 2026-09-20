run_logged "$OMARCHY_INSTALL/config/locale.sh"
run_logged "$OMARCHY_INSTALL/config/theme-system.sh"
run_logged "$OMARCHY_INSTALL/config/browser-policy.sh"
run_logged "$OMARCHY_INSTALL/config/increase-lockout-limit.sh"
run_logged "$OMARCHY_INSTALL/config/lockscreen-pam.sh"
run_logged "$OMARCHY_INSTALL/config/fix-powerprofilesctl-shebang.sh"
run_logged "$OMARCHY_INSTALL/config/ssh-command-path.sh"
run_logged "$OMARCHY_INSTALL/config/ssh-keepalive.sh"
run_logged "$OMARCHY_INSTALL/config/docker.sh"
if [[ ${OMARCHY_MAC_IMAGE_BUILD:-} != 1 ]] && ! omarchy-hw-apple-silicon; then
  run_logged "$OMARCHY_INSTALL/config/snapper.sh"
fi
run_logged "$OMARCHY_INSTALL/config/enable-services.sh"
run_logged "$OMARCHY_INSTALL/config/firewall.sh"
