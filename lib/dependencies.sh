#!/usr/bin/env bash

list_dependencies() {
  local build_dir="$1"
  cd "$build_dir" || return
  (pnpm ls --depth=0 | tail -n +2 || true) 2>/dev/null
}

pnpm_node_modules() {
  local build_dir=${1:-}
  local production

  if [[ "$NPM_CONFIG_PRODUCTION" == "true" ]] ; then
      production="true"
  fi

  if [ -e "$build_dir/package.json" ]; then
    cd "$build_dir" || return
    # N.B. you must not use double quotes here.
    pnpm install ${production:+"--prod"} 2>&1
  else
    echo "Skipping (no package.json)"
  fi
}

pnpm_prune_devdependencies() {
  local build_dir=${1:-}
  cd "$build_dir" || return
  pnpm prune 2>&1
}
