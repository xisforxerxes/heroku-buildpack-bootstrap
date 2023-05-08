#!/usr/bin/env bash

measure_size() {
  (du -s node_modules 2>/dev/null || echo 0) | awk '{print $1}'
}

list_dependencies() {
  local build_dir="$1"

  cd "$build_dir" || return
  if $YARN; then
    echo ""
    (yarn list --depth=0 || true) 2>/dev/null
    echo ""
  else
    (npm ls --depth=0 | tail -n +2 || true) 2>/dev/null
  fi
}

run_if_present() {
  local build_dir=${1:-}
  local script_name=${2:-}
  local has_script_name
  local script

  has_script_name=$(has_script "$build_dir/package.json" "$script_name")
  script=$(read_json "$build_dir/package.json" ".scripts[\"$script_name\"]")

  if [[ "$has_script_name" == "true" ]]; then
    if $YARN || $YARN_2; then
      echo "Running $script_name (yarn)"
      # yarn will throw an error if the script is an empty string, so check for this case
      if [[ -n "$script" ]]; then
        monitor "${script_name}-script" yarn run "$script_name"
      fi
    else
      echo "Running $script_name"
      monitor "${script_name}-script" npm run "$script_name" --if-present
    fi
  fi
}

run_build_if_present() {
  local build_dir=${1:-}
  local script_name=${2:-}
  local has_script_name
  local script

  has_script_name=$(has_script "$build_dir/package.json" "$script_name")
  script=$(read_json "$build_dir/package.json" ".scripts[\"$script_name\"]")

  if [[ "$script" == "ng build" ]]; then
    warn "\"ng build\" detected as build script. We recommend you use \`ng build --prod\` or add \`--prod\` to your build flags. See https://devcenter.heroku.com/articles/nodejs-support#build-flags"
  fi

  if [[ "$has_script_name" == "true" ]]; then
    if $YARN || $YARN_2; then
      echo "Running $script_name (yarn)"
      # yarn will throw an error if the script is an empty string, so check for this case
      if [[ -n "$script" ]]; then
        if [[ -n $NODE_BUILD_FLAGS ]]; then
          echo "Running with $NODE_BUILD_FLAGS flags"
          monitor "${script_name}-script" yarn run "$script_name" "$NODE_BUILD_FLAGS"
        else
          monitor "${script_name}-script" yarn run "$script_name"
        fi
      fi
    else
      echo "Running $script_name"
      if [[ -n $NODE_BUILD_FLAGS ]]; then
        echo "Running with $NODE_BUILD_FLAGS flags"
        monitor "${script_name}-script" npm run "$script_name" --if-present -- "$NODE_BUILD_FLAGS"
      else
        monitor "${script_name}-script" npm run "$script_name" --if-present
      fi
    fi
  fi
}

run_prebuild_script() {
  local build_dir=${1:-}
  local has_heroku_prebuild_script

  has_heroku_prebuild_script=$(has_script "$build_dir/package.json" "heroku-prebuild")

  if [[ "$has_heroku_prebuild_script" == "true" ]]; then
    mcount "script.heroku-prebuild"
    header "Prebuild"
    run_if_present "$build_dir" 'heroku-prebuild'
  fi
}

run_build_script() {
  local build_dir=${1:-}
  local has_build_script has_heroku_build_script

  has_build_script=$(has_script "$build_dir/package.json" "build")
  has_heroku_build_script=$(has_script "$build_dir/package.json" "heroku-postbuild")
  if [[ "$has_heroku_build_script" == "true" ]] && [[ "$has_build_script" == "true" ]]; then
    echo "Detected both \"build\" and \"heroku-postbuild\" scripts"
    mcount "scripts.heroku-postbuild-and-build"
    run_if_present "$build_dir" 'heroku-postbuild'
  elif [[ "$has_heroku_build_script" == "true" ]]; then
    mcount "scripts.heroku-postbuild"
    run_if_present "$build_dir" 'heroku-postbuild'
  elif [[ "$has_build_script" == "true" ]]; then
    mcount "scripts.build"
    run_build_if_present "$build_dir" 'build'
  fi
}

run_cleanup_script() {
  local build_dir=${1:-}
  local has_heroku_cleanup_script

  has_heroku_cleanup_script=$(has_script "$build_dir/package.json" "heroku-cleanup")

  if [[ "$has_heroku_cleanup_script" == "true" ]]; then
    mcount "script.heroku-cleanup"
    header "Cleanup"
    run_if_present "$build_dir" 'heroku-cleanup'
  fi
}

should_use_npm_ci() {
  local build_dir=${1:-}
  local npm_version

  npm_version=$(npm --version)
  # major_string will be ex: "4." "5." "10"
  local major_string=${npm_version:0:2}
  # strip any "."s from major_string
  local major=${major_string//.}

  # We should only run `npm ci` if all of the manifest files are there, and we are running at least npm 6.x
  # `npm ci` was introduced in the 5.x line in 5.7.0, but this sees very little usage, < 5% of builds
  if [[ -f "$build_dir/package.json" ]] && [[ "$(has_npm_lock "$build_dir")" == "true" ]] && (( major >= 6 )); then
    echo "true"
  else
    echo "false"
  fi
}

npm_node_modules() {
  local build_dir=${1:-}
  local production

  if [[ "$NPM_CONFIG_PRODUCTION" == "true" ]] ; then
      production="true"
  fi

  if [ -e "$build_dir/package.json" ]; then
    cd "$build_dir" || return
    pnpm install "${production:+"--prod"}" 2>&1
    fi
  else
    echo "Skipping (no package.json)"
  fi
}

npm_rebuild() {
  local build_dir=${1:-}
  local production=

  if [[ "$NPM_CONFIG_PRODUCTION" == "true" ]] ; then
      production="true"
  fi

  if [ -e "$build_dir/package.json" ]; then
    cd "$build_dir" || return
    echo "Rebuilding any native modules"
    pnpm rebuild 2>&1
    echo "Installing any new modules (package.json)"
    pnpm install "${production:+"--prod"}" 2>&1
  else
    echo "Skipping (no package.json)"
  fi
}

pnpm_prune_devdependencies() {
  local build_dir=${1:-}
  cd "$build_dir" || return
  pnpm prune 2>&1
}
