/*
  Runner for packages declaring `passthru.updateScript`, modeled after
  xddxdd/nur-packages helpers/update.nix and nixpkgs maintainers/scripts/update.nix.

  Usage:
      nix-shell helpers/update.nix --argstr packages "cpa-manager-plus resin"
      nix-shell helpers/update.nix --argstr packages ""
      ./tools/update-package --all
      ./tools/update-package cpa-manager-plus
*/
{
  pkgs ? import <nixpkgs> { },
  packages ? "",
  path ? null,
  predicate ? null,
  excludes ? [ ],
}:
let
  inherit (pkgs) lib;
  nurPkgs = import ../default.nix { inherit pkgs; };

  updateScriptOf =
    pkg:
    let
      script = (if pkg.passthru or null != null then pkg.passthru else { }).updateScript or null;
    in
    if script == null then
      null
    else if lib.isDerivation script then
      [ (toString script) ]
    else if lib.isAttrs script then
      if script ? command then map toString (lib.toList script.command) else null
    else
      map toString (lib.toList script);

  collect =
    prefix: attrs:
    let
      names = builtins.tryEval (builtins.attrNames attrs);
    in
    if !names.success then
      [ ]
    else
      builtins.concatLists (
        map (
          name:
          let
            result = builtins.tryEval attrs.${name};
          in
          if !result.success then
            [ ]
          else if lib.isDerivation result.value then
            let
              script = updateScriptOf result.value;
              meta = result.value.meta or null;
              position = if meta != null then meta.position or null else null;
              usesSources =
                if position == null then
                  false
                else
                  let
                    file = lib.head (lib.splitString ":" (toString position));
                    content = builtins.tryEval (builtins.readFile file);
                    lineHasRef = l: builtins.match ".*[^A-Za-z0-9_]?sources\\..+" l != null;
                  in
                  content.success && lib.any lineHasRef (lib.splitString "\n" content.value);
            in
            lib.optional (script != null && !usesSources) {
              inherit name;
              attrPath = lib.concatStringsSep "." (prefix ++ [ name ]);
              inherit script;
              pname = result.value.pname or (lib.getName result.value);
              pkgName = result.value.name;
              oldVersion = result.value.version or "";
              inherit position;
            }
          else if lib.isAttrs result.value then
            collect (prefix ++ [ name ]) result.value
          else
            [ ]
        ) names.value
      );

  allPackages = collect [ ] nurPkgs;

  grouped = lib.foldl (
    acc: cur:
    let
      key = builtins.hashString "sha256" (
        lib.concatStringsSep "\n" (cur.script ++ [ (toString cur.position) ])
      );
      prev = acc.${key} or null;
      keep = prev == null || (lib.hasInfix "." cur.attrPath && !lib.hasInfix "." prev.attrPath);
    in
    acc // { ${key} = if keep then cur else prev; }
  ) { } allPackages;

  deduplicated = map (k: grouped.${k}) (builtins.attrNames grouped);

  matchesSelection = p: sel: p.attrPath == sel || lib.hasSuffix ".${sel}" p.attrPath;

  selected =
    let
      candidates = lib.filter (p: !lib.any (exclude: matchesSelection p exclude) excludes) deduplicated;
    in
    if packages != "" then
      lib.filter (p: lib.any (sel: matchesSelection p sel) (lib.splitString " " packages)) candidates
    else if path != null then
      lib.filter (p: p.attrPath == path || lib.hasPrefix "${path}." p.attrPath) candidates
    else if predicate != null then
      lib.filter (
        p: predicate p.attrPath (lib.attrByPath (lib.splitString "." p.attrPath) null nurPkgs)
      ) candidates
    else
      candidates;

  invalidSelections = builtins.filter (sel: !lib.any (p: matchesSelection p sel) selected) (
    lib.filter (s: s != "") (lib.splitString " " packages)
  );

  packagesJson = pkgs.writeText "nur-update-packages.json" (
    builtins.toJSON (
      map (p: {
        inherit (p) attrPath oldVersion;
        inherit (p) pname;
        name = p.pkgName;
        updateScript = p.script;
      }) selected
    )
  );

  helpText = ''
    No packages with passthru.updateScript were selected.
  '';
in
pkgs.stdenvNoCC.mkDerivation {
  name = "nur-update-script";
  nativeBuildInputs = [
    pkgs.git
    pkgs.cacert
    pkgs.jq
  ];
  buildCommand = ''
    echo ""
    echo "Not possible to run update scripts using nix-build."
    echo ""
    echo "${lib.replaceStrings [ "\n" ] [ " " ] helpText}"
    exit 1
  '';
  shellHook = ''
    unset shellHook

    ${lib.optionalString (invalidSelections != [ ]) ''
      echo "WARNING: no updateScript found for: ${lib.concatStringsSep " " invalidSelections}" >&2
    ''}

    ${lib.optionalString (selected == [ ]) ''
      echo "${lib.replaceStrings [ "\n" ] [ " " ] helpText}" >&2
      exit 1
    ''}

    FAILED=""
    LOGDIR=$(mktemp -d)
    trap 'rm -rf "$LOGDIR"' EXIT
    cd "${toString ./.}/.."

    MAX_JOBS="''${UPDATE_PACKAGE_JOBS:-$(nproc)}"
    declare -A JOB_ATTR=() JOB_LOG=()
    RUNNING=0

    launch() {
      local PKG="$1" ATTR_PATH OLD_VERSION LOG
      ATTR_PATH=$(jq -r .attrPath <<<"$PKG")
      OLD_VERSION=$(jq -r .oldVersion <<<"$PKG")
      LOG=$(mktemp "$LOGDIR/log.XXXXXX")
      echo ">>> $ATTR_PATH: updating ($OLD_VERSION)"
      (
        if env \
            UPDATE_NIX_ATTR_PATH="$ATTR_PATH" \
            UPDATE_NIX_PNAME="$(jq -r .pname <<<"$PKG")" \
            UPDATE_NIX_NAME="$(jq -r .name <<<"$PKG")" \
            UPDATE_NIX_OLD_VERSION="$OLD_VERSION" \
            bash -c "$(jq -r '.updateScript | map(@sh) | join(" ")' <<<"$PKG")"; then
          echo ">>> $ATTR_PATH: done"
          exit 0
        else
          echo ">>> $ATTR_PATH: FAILED" >&2
          exit 1
        fi
      ) >"$LOG" 2>&1 &
      JOB_ATTR[$!]="$ATTR_PATH"
      JOB_LOG[$!]="$LOG"
      RUNNING=$((RUNNING + 1))
    }

    reap_one() {
      local PID STATUS ATTR_PATH LOG
      PID=""
      STATUS=0
      wait -n -p PID || STATUS=$?
      ATTR_PATH="''${JOB_ATTR[$PID]}"
      LOG="''${JOB_LOG[$PID]}"
      echo ""
      cat "$LOG"
      rm -f "$LOG"
      if [ "$STATUS" -ne 0 ]; then
        FAILED="$FAILED $ATTR_PATH"
      fi
      unset "JOB_ATTR[$PID]" "JOB_LOG[$PID]"
      RUNNING=$((RUNNING - 1))
    }

    while IFS= read -r PKG; do
      while [ "$RUNNING" -ge "$MAX_JOBS" ]; do
        reap_one
      done
      launch "$PKG"
    done < <(jq -c '.[]' ${packagesJson})

    while [ "$RUNNING" -gt 0 ]; do
      reap_one
    done

    echo ""
    if [ -n "$FAILED" ]; then
      echo "Finished with failures:$FAILED" >&2
      exit 1
    fi
    echo "All update scripts finished successfully."
  '';
}
