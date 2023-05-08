#!/usr/bin/env bash

# Compiled from: https://github.com/heroku/buildpacks-nodejs/blob/main/common/nodejs-utils/src/bin/resolve_version.rs
RESOLVE="$BP_DIR/lib/vendor/resolve-version-$(get_os)"

resolve() {
  local binary="$1"
  local versionRequirement="$2"
  local output

  if output=$($RESOLVE "$BP_DIR/inventory/$binary.toml" "$versionRequirement"); then
    if [[ $output = "No result" ]]; then
      return 1
    else
      echo $output
      return 0
    fi
  fi
  return 1
}

install_nodejs() {
  local version="${1:-}"
  local dir="${2:?}"
  local code resolve_result

  if [[ -z "$version" ]]; then
    # Node.js 18+ is incompatible with ubuntu:18 (and thus heroku-18) because of a libc mismatch:
    # node: /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.28' not found (required by node)
    # Fallback to a 16.x default for heroku-18 until heroku-18 or Node.js 16.x are EOL.
    if [[ "$STACK" == "heroku-18" ]]; then
      version="16.x"
    else
      version="18.x"
    fi
  fi

  if [[ -n "$NODE_BINARY_URL" ]]; then
    url="$NODE_BINARY_URL"
    echo "Downloading and installing node from $url"
  else
    echo "Resolving node version $version..."
    resolve_result=$(resolve node "$version" || echo "failed")

    read -r number url < <(echo "$resolve_result")

    if [[ "$resolve_result" == "failed" ]]; then
      fail_bin_install node "$version"
    fi

    echo "Downloading and installing node $number..."
  fi

  code=$(curl "$url" -L --silent --fail --retry 5 --retry-max-time 15 --retry-connrefused --connect-timeout 5 -o /tmp/node.tar.gz --write-out "%{http_code}")

  if [ "$code" != "200" ]; then
    echo "Unable to download node: $code" && false
  fi
  rm -rf "${dir:?}"/*
  tar xzf /tmp/node.tar.gz --strip-components 1 -C "$dir"
  chmod +x "$dir"/bin/*
}

install_npm() {
  local npm_version
  local version="$1"
  local dir="$2"
  # Verify npm works before capturing and ensure its stderr is inspectable later.
  npm --version 2>&1 1>/dev/null
  npm_version="$(npm --version)"

  if [ "$version" == "" ]; then
    echo "Using default npm version: $npm_version"
  elif [[ "$npm_version" == "$version" ]]; then
    echo "npm $npm_version already installed with node"
  else
    echo "Bootstrapping npm $version (replacing $npm_version)..."
    if ! npm install --unsafe-perm --quiet -g "npm@$version" 2>@1>/dev/null; then
      echo "Unable to install npm $version; does it exist?" && false
    fi
    # Verify npm works before capturing and ensure its stderr is inspectable later.
    npm --version 2>&1 1>/dev/null
    echo "npm $(npm --version) installed"
  fi
}

install_pnpm() {
  local pnpm_version
  local version="$1"

  npm install -g --no-save "pnpm@${version:-latest}"
  # Verify pnpm works before capturing and ensure its stderr is inspectable later.
  pnpm --version 2>&1 1>/dev/null
  echo "pnpm $(pnpm --version) installed"
}

install_nx() {
  pnpm install -g nx
  # Verify nx works before capturing and ensure its stderr is inspectable later.
  nx --version 2>&1 1>/dev/null
  echo "nx $(nx --version) installed"
}
