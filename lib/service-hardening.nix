# Defaults for application services. Callers must allow their state directories
# and explicitly override device/namespace restrictions when needed (GPU, TUN).
# JIT runtimes and subprocesses are supported: no blanket syscall or W^X filter.
{lib}:
lib.mapAttrs (_: lib.mkDefault) {
  AmbientCapabilities = "";
  CapabilityBoundingSet = "";
  LockPersonality = true;
  NoNewPrivileges = true;
  PrivateDevices = true;
  PrivateTmp = true;
  ProtectClock = true;
  ProtectControlGroups = true;
  ProtectHome = true;
  ProtectHostname = true;
  ProtectKernelLogs = true;
  ProtectKernelModules = true;
  ProtectKernelTunables = true;
  ProtectProc = "invisible";
  ProtectSystem = "strict";
  RestrictNamespaces = true;
  RestrictRealtime = true;
  RestrictSUIDSGID = true;
  UMask = "0077";
}
