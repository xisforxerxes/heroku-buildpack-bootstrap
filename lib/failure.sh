#!/usr/bin/env bash

warnings=$(mktemp -t heroku-buildpack-nodejs-XXXX)

detect_package_manager() {
  case $YARN in
    true) echo "yarn";;
    *) echo "npm";;
  esac
}

fail() {
  exit 1
}

failure_message() {
  local warn

  warn="$(cat "$warnings")"

  echo ""
  echo "We're sorry this build is failing! You can troubleshoot common issues here:"
  echo "https://devcenter.heroku.com/articles/troubleshooting-node-deploys"
  echo ""
  if [ "$warn" != "" ]; then
    echo "Some possible problems:"
    echo ""
    echo "$warn"
  else
    echo "If you're stuck, please submit a ticket so we can help:"
    echo "https://help.heroku.com/"
  fi
  echo ""
  echo "Love,"
  echo "Heroku"
  echo ""
}

fail_no_nx_workspace() {
  if [ ! -f "${1:-}/nx.json" ] ; then
    header "Build failed"
    error "Unable to locate nx.json. Must be built in an NX workspace."
    fail
  fi
}

fail_prebuilt() {
  if [ -e "${1:-}/node_modules" ]; then
    header "Build failed"
    error "Prebuilt configurations are not supported in this build pack.

       It looks like node_modules is checked into this project. It should be
       placed in .gitignore or added to .slugignore
       "
    fail
  fi
}

fail_invalid_package_json() {
  local is_invalid

  is_invalid=$(is_invalid_json_file "${1:-}/package.json")

  if "$is_invalid"; then
    error "Unable to parse package.json"
    header "Build failed"
    failure_message
    fail
  fi
}

fail_dot_heroku() {
  if [ -f "${1:-}/.heroku" ]; then
    header "Build failed"
    warn "The directory .heroku could not be created

       It looks like a .heroku file is checked into this project.
       The Node.js buildpack uses the hidden directory .heroku to store
       binaries like the node runtime and npm. You should remove the
       .heroku file or ignore it by adding it to .slugignore
       "
    fail
  fi
}

fail_dot_heroku_node() {
  if [ -f "${1:-}/.heroku/node" ]; then
    header "Build failed"
    warn "The directory .heroku/node could not be created

       It looks like a .heroku file is checked into this project.
       The Node.js buildpack uses the hidden directory .heroku to store
       binaries like the node runtime and npm. You should remove the
       .heroku file or ignore it by adding it to .slugignore
       "
    fail
  fi
}


fail_multiple_lockfiles() {
  local has_modern_lockfile=false
  if [ -f "${1:-}/yarn.lock" ] || [ -f "${1:-}/package-lock.json" ]; then
    has_modern_lockfile=true
  fi

  if [ -f "${1:-}/yarn.lock" ] && [ -f "${1:-}/package-lock.json" ]; then
    header "Build failed"
    warn "Two different lockfiles found: package-lock.json and yarn.lock

       Both npm and yarn have created lockfiles for this application,
       but only one can be used to install dependencies. Installing
       dependencies using the wrong package manager can result in missing
       packages or subtle bugs in production.

       - To use npm to install your application's dependencies please delete
         the yarn.lock file.

         $ git rm yarn.lock

       - To use yarn to install your application's dependencies please delete
         the package-lock.json file.

         $ git rm package-lock.json
    " https://help.heroku.com/0KU2EM53
    fail
  fi

  if $has_modern_lockfile && [ -f "${1:-}/npm-shrinkwrap.json" ]; then
    header "Build failed"
    warn "Two different lockfiles found

       Your application has two lockfiles defined, but only one can be used
       to install dependencies. Installing dependencies using the wrong lockfile
       can result in missing packages or subtle bugs in production.

       It's most likely that you recently installed yarn which has its own
       lockfile by default, which conflicts with the shrinkwrap file you've been
       using.

       Please make sure there is only one of the following files in your
       application directory:

       - yarn.lock
       - package-lock.json
       - npm-shrinkwrap.json
    " https://help.heroku.com/0KU2EM53
    fail
  fi
}


fail_bin_install() {
  local error
  local bin="$1"
  local version="$2"

  # Allow the subcommand to fail without trapping the error so we can
  # get the failing message output
  set +e

  # re-request the result, saving off the reason for the failure this time
  error=$($RESOLVE "$BP_DIR/inventory/$bin.toml" "$version" 2>&1)

  # re-enable trapping
  set -e

  if [[ $error = "No result" ]]; then
    case $bin in
      node)
        echo "Could not find Node version corresponding to version requirement: $version";;
      yarn)
        echo "Could not find Yarn version corresponding to version requirement: $version";;
    esac
  elif [[ $error == "Could not parse"* ]] || [[ $error == "Could not get"* ]]; then
    echo "Error: Invalid semantic version \"$version\""
  else
    echo "Error: Unknown error installing \"$version\" of $bin"
  fi

  return 1
}

fail_node_install() {
  local node_engine
  local log_file="$1"
  local build_dir="$2"

  if grep -qi 'Could not find Node version corresponding to version requirement' "$log_file"; then
    node_engine=$(read_json "$build_dir/package.json" ".engines.node")
    echo ""
    warn "No matching version found for Node: $node_engine

       Heroku supports the latest Stable version of Node.js as well as all
       active LTS (Long-Term-Support) versions, however you have specified
       a version in package.json ($node_engine) that does not correspond to
       any published version of Node.js.

       You should always specify a Node.js version that matches the runtime
       you’re developing and testing with. To find your version locally:

       $ node --version
       v6.11.1

       Use the engines section of your package.json to specify the version of
       Node.js to use on Heroku. Drop the ‘v’ to save only the version number:

       \"engines\": {
         \"node\": \"6.11.1\"
       }
    " https://help.heroku.com/6235QYN4/
    fail
  fi
}

fail_invalid_semver() {
  local log_file="$1"
  if grep -qi 'Error: Invalid semantic version' "$log_file"; then
    echo ""
    warn "Invalid semver requirement

       Node, Yarn, and npm adhere to semver, the semantic versioning convention
       popularized by GitHub.

       http://semver.org/

       However you have specified a version requirement that is not a valid
       semantic version.
    " https://help.heroku.com/0ZIOF3ST
    fail
  fi
}

warning() {
  local tip=${1:-}
  local url=${2:-https://devcenter.heroku.com/articles/nodejs-support}
  {
  echo "- $tip"
  echo "  $url"
  echo ""
  } >> "$warnings"
}

warn() {
  local tip=${1:-}
  local url=${2:-https://devcenter.heroku.com/articles/nodejs-support}
  echo " !     $tip" || true
  echo "       $url" || true
  echo ""
}

warn_aws_proxy() {
  if { [[ -n "$HTTP_PROXY" ]] || [[ -n "$HTTPS_PROXY" ]]; } && [[ "$NO_PROXY" != "amazonaws.com" ]]; then
    warn "Your build may fail if NO_PROXY is not set to amazonaws.com" "https://devcenter.heroku.com/articles/troubleshooting-node-deploys#aws-proxy-error"
  fi
}

warn_node_engine() {
  local node_engine=${1:-}
  if [ "$node_engine" == "" ]; then
    warning "Node version not specified in package.json" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
  elif [ "$node_engine" == "*" ]; then
    warning "Dangerous semver range (*) in engines.node" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
  elif [ "${node_engine:0:1}" == ">" ]; then
    warning "Dangerous semver range (>) in engines.node" "https://devcenter.heroku.com/articles/nodejs-support#specifying-a-node-js-version"
  fi
}

warn_prebuilt_modules() {
  local build_dir=${1:-}
  if [ -e "$build_dir/node_modules" ]; then
    warning "node_modules checked into source control" "https://devcenter.heroku.com/articles/node-best-practices#only-git-the-important-bits"
  fi
}

warn_missing_package_json() {
  local build_dir=${1:-}
  if ! [ -e "$build_dir/package.json" ]; then
    warning "No package.json found"
  fi
}

warn_missing_devdeps() {
  local dev_deps
  local log_file="$1"
  local build_dir="$2"

  if grep -qi 'cannot find module' "$log_file"; then
    warning "A module may be missing from 'dependencies' in package.json" "https://devcenter.heroku.com/articles/troubleshooting-node-deploys#ensure-you-aren-t-relying-on-untracked-dependencies"
    if [ "$NPM_CONFIG_PRODUCTION" == "true" ]; then
      dev_deps=$(read_json "$build_dir/package.json" ".devDependencies")
      if [ "$dev_deps" != "" ]; then
        warning "This module may be specified in 'devDependencies' instead of 'dependencies'" "https://devcenter.heroku.com/articles/nodejs-support#devdependencies"
      fi
    fi
  fi
}

warn_no_start() {
  local start_script
  local build_dir="$1"

  if ! [ -e "$build_dir/Procfile" ]; then
    start_script=$(read_json "$build_dir/package.json" ".scripts.start")
    if [ "$start_script" == "" ]; then
      if ! [ -e "$build_dir/server.js" ]; then
        warn "This app may not specify any way to start a node process" "https://devcenter.heroku.com/articles/nodejs-support#default-web-process-type"
      fi
    fi
  fi
}

warn_econnreset() {
  local log_file="$1"
  if grep -qi 'econnreset' "$log_file"; then
    warning "ECONNRESET issues may be related to npm versions" "https://github.com/npm/registry/issues/10#issuecomment-217141066"
  fi
}

warn_unmet_dep() {
  local package_manager
  local log_file="$1"

  package_manager=$(detect_package_manager)

  if grep -qi 'unmet dependency' "$log_file" || grep -qi 'unmet peer dependency' "$log_file"; then
    warn "Unmet dependencies don't fail $package_manager install but may cause runtime issues" "https://github.com/npm/npm/issues/7494"
  fi
}
