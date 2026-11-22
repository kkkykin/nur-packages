# nur-packages-template

**A template for [NUR](https://github.com/nix-community/NUR) repositories**

## Setup

1. Click on [Use this template](https://github.com/nix-community/nur-packages-template/generate) to start a repo based on this template. (Do _not_ fork it.)
2. Add your packages to the [pkgs](./pkgs) directory and to
   [default.nix](./default.nix)
   * Remember to mark the broken packages as `broken = true;` in the `meta`
     attribute, or travis (and consequently caching) will fail!
   * Library functions, modules and overlays go in the respective directories
3. Choose your CI: Depending on your preference you can use github actions (recommended) or [Travis ci](https://travis-ci.com).
   - Github actions: Change your NUR repo name and optionally add a cachix name in [.github/workflows/build.yml](./.github/workflows/build.yml) and change the cron timer
     to a random value as described in the file
   - Travis ci: Change your NUR repo name and optionally your cachix repo name in
   [.travis.yml](./.travis.yml). Than enable travis in your repo. You can add a cron job in the repository settings on travis to keep your cachix cache fresh
5. Change your travis and cachix names on the README template section and delete
   the rest
6. [Add yourself to NUR](https://github.com/nix-community/NUR#how-to-add-your-own-repository)

## README template

# nur-packages

**My personal [NUR](https://github.com/nix-community/NUR) repository**

<!-- Remove this if you don't use github actions -->
![Build and populate cache](https://github.com/kkkykin/nur-packages/workflows/Build%20and%20populate%20cache/badge.svg)

<!--
Uncomment this if you use travis:

[![Build Status](https://travis-ci.com/<YOUR_TRAVIS_USERNAME>/nur-packages.svg?branch=master)](https://travis-ci.com/<YOUR_TRAVIS_USERNAME>/nur-packages)
-->
[![Cachix Cache](https://img.shields.io/badge/cachix-<YOUR_CACHIX_CACHE_NAME>-blue.svg)](https://<YOUR_CACHIX_CACHE_NAME>.cachix.org)

## Service hardening

Application modules use `lib/service-hardening.nix` for overridable systemd
defaults: no privilege escalation or capabilities, a read-only filesystem,
private temporary files, and restricted access to homes, devices and kernel
settings. Each module allows its own writable state directories. Custom mounts
and shared data must be declared through `systemd.services.<name>.serviceConfig`;
normal option definitions override the hardening defaults. JIT memory and
syscall filters are intentionally left to individual services.

For consumers of `default.nix`, the same defaults are available as
`pkgs.kkkykin.lib.serviceHardening`. OpenList keeps group-writable state for shared
file access and supports a custom `dataDir`; hubproxy's `serviceConfig` option can
override its defaults.

Published NapCat and matrix-pylon ports default to `127.0.0.1`. Use
`services.napcat.webuiListenAddress`, `services.napcat.onebotListenAddress`, or
`services.matrix-pylon.listenAddress` to allow remote clients explicitly.
Containers drop unnecessary capabilities, enable no-new-privileges and limit
process counts. NapCat retains `SYS_PTRACE` and unconfined seccomp because QQ
instrumentation requires them.

Module interface and generated-unit regressions can be evaluated without
building the application packages:

```sh
nix eval --impure --json --expr 'import ./tests/service-hardening.nix {
  nixpkgs = (builtins.getFlake (toString ./.)).inputs.nixpkgs.outPath;
}'
```
