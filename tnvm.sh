# Taobao Node Version Manager
# Implemented as a POSIX-compliant function
# Should work on sh, dash, bash, ksh, zsh
# To use source this file from your bash profile


{ # this ensures the entire script is downloaded #

NVM_SCRIPT_SOURCE="$_"

MIRRORS=("http://npm.taobao.org/mirrors/node"
        "http://npm.taobao.org/mirrors/iojs"
        "http://alinode.aliyun.com/dist/alinode"
        "http://alinode.aliyun.com/dist/node-profiler")

TNVM_IFS='-' #TODO

tnvm_has() {
  type "$1" > /dev/null 2>&1
}

tnvm_is_alias() {
  # this is intentionally not "command alias" so it works in zsh.
  \alias "$1" > /dev/null 2>&1
}

tnvm_download() {
  if tnvm_has "curl"; then
    curl -q $*
  elif tnvm_has "wget"; then
    # Emulate curl with wget
    ARGS=$(echo "$*" | command sed -e 's/--progress-bar /--progress=bar /' \
                           -e 's/-L //' \
                           -e 's/-I /--server-response /' \
                           -e 's/-s /-q /' \
                           -e 's/-o /-O /' \
                           -e 's/-C - /-c /')
    eval wget $ARGS
  fi
}

tnvm_has_system_node() {
  [ "$(tnvm deactivate >/dev/null 2>&1 && command -v node)" != '' ]
}

tnvm_has_system_iojs() {
  [ "$(tnvm deactivate >/dev/null 2>&1 && command -v iojs)" != '' ]
}

tnvm_print_npm_version() {
  if tnvm_has "npm"; then
    npm --version 2>/dev/null | command xargs printf " (npm v%s)"
  fi
}

# Make zsh glob matching behave same as bash
# This fixes the "zsh: no matches found" errors
if tnvm_has "unsetopt"; then
  unsetopt nomatch 2>/dev/null
  NVM_CD_FLAGS="-q"
fi

# Auto detect the TNVM_DIR when not set
if [ -z "$TNVM_DIR" ]; then
  if [ -n "$BASH_SOURCE" ]; then
    NVM_SCRIPT_SOURCE="${BASH_SOURCE[0]}"
  fi
  export TNVM_DIR=$(cd $NVM_CD_FLAGS $(dirname "${NVM_SCRIPT_SOURCE:-$0}") > /dev/null && \pwd)
fi
unset NVM_SCRIPT_SOURCE 2> /dev/null


tnvm_tree_contains_path() {
  local tree
  tree="$1"
  local node_path
  node_path="$2"

  if [ "@$tree@" = "@@" ] || [ "@$node_path@" = "@@" ]; then
    >&2 echo "both the tree and the node path are required"
    return 2
  fi

  local pathdir
  pathdir=$(dirname "$node_path")
  while [ "$pathdir" != "" ] && [ "$pathdir" != "." ] && [ "$pathdir" != "/" ] && [ "$pathdir" != "$tree" ]; do
    pathdir=$(dirname "$pathdir")
  done
  [ "$pathdir" = "$tree" ]
}

tnvm_rc_version() {
  export TNVM_RC_VERSION=''
  local NVMRC_PATH
  NVMRC_PATH="$TNVM_DIR/.tnvmrc"
  if [ -e "$NVMRC_PATH" ]; then
    read TNVM_RC_VERSION < "$NVMRC_PATH"
    echo "Found '$NVMRC_PATH' with version <$NVM_RC_VERSION>"
  else
    >&2 echo "No .tnvmrc file found"
    return 1
  fi
}

tnvm_version_greater() {
  local LHS
  LHS=$(tnvm_normalize_version "$1")
  local RHS
  RHS=$(tnvm_normalize_version "$2")
  [ $LHS -gt $RHS ];
}

tnvm_version_greater_than_or_equal_to() {
  local LHS
  LHS=$(tnvm_normalize_version "$1")
  local RHS
  RHS=$(tnvm_normalize_version "$2")
  [ $LHS -ge $RHS ];
}

tnvm_version_dir() {
  local PREFIX
  PREFIX="$(tnvm_get_prefix $1)"
  echo "$TNVM_DIR/versions/$PREFIX"
}

# ~/versions/node/v0.12.4 etc
tnvm_version_path() {
  local VERSION
  VERSION="$1"
  if [ -z "$VERSION" ]; then
    echo "version is required" >&2
    return 3
  fi
  echo "$(tnvm_version_dir $VERSION)/$(tnvm_get_version $VERSION)"
}


tnvm_ensure_version_installed() {
  local PROVIDED_VERSION
  PROVIDED_VERSION="$1"
  local LOCAL_VERSION
  LOCAL_VERSION="$(tnvm_version "$PROVIDED_VERSION")"
  local NVM_VERSION_DIR
  NVM_VERSION_DIR="$(tnvm_version_path "$LOCAL_VERSION")"
  if [ ! -d "$NVM_VERSION_DIR" ]; then
    echo "N/A: version \"$PROVIDED_VERSION\" is not yet installed" >&2
    return 1
  fi
}


# Expand a version using the version cache
tnvm_version() {
  local PATTERN
  PATTERN=$1
  local VERSION
  # The default version is the current one
  if [ -z "$PATTERN" ]; then
    PATTERN='current'
  fi

  if [ "$PATTERN" = "current" ]; then
    tnvm_ls_current
    return $?
  fi

  VERSION="$(tnvm_ls "$PATTERN" | tail -n1)"
  if [ -z "$VERSION" ] || [ "_$VERSION" = "_N/A" ]; then
    echo "N/A"
    return 3;
  else
    echo "$VERSION"
  fi
}


tnvm_remote_version() {
  local PATTERN
  PATTERN="$(tnvm_get_version "$1")"
  local VERSION
  VERSION="$(tnvm_remote_versions "$PREFIX" | command grep -w "$PATTERN")"
  if [ "_$VERSION" = '_N/A' ] || [ -z "$VERSION" ] ; then
    echo "N/A"
    return 3
  fi
  echo "$VERSION"
}


tnvm_remote_versions() {
  local PATTERN
  PATTERN="$1"
  VERSIONS="$(tnvm_ls_remote $PATTERN)"

  if [ -z "$VERSIONS" ]; then
    echo "N/A"
    return 3
  else
    echo "$VERSIONS"
  fi
}


tnvm_normalize_version() {
  echo "${1#v}" | command awk -F. '{ printf("%d%06d%06d\n", $1,$2,$3); }'
}


tnvm_format_version() {
  local VERSION
  VERSION="$1"
  if [ "_$(tnvm_num_version_groups "$VERSION")" != "_3" ]; then
    tnvm_format_version "${VERSION%.}.0"
  else
    echo "$VERSION"
  fi
}


tnvm_num_version_groups() {
  local VERSION
  VERSION="$1"
  VERSION="${VERSION#v}"
  VERSION="${VERSION%.}"
  if [ -z "$VERSION" ]; then
    echo "0"
    return
  fi
  local NVM_NUM_DOTS
  NVM_NUM_DOTS=$(echo "$VERSION" | command sed -e 's/[^\.]//g')
  local NVM_NUM_GROUPS
  NVM_NUM_GROUPS=".$NVM_NUM_DOTS" # add extra dot, since it's (n - 1) dots at this point
  echo "${#NVM_NUM_GROUPS}"
}


tnvm_strip_path() {
  echo "$1" | command sed \
    -e "s#$TNVM_DIR/[^/]*$2[^:]*:##g" \
    -e "s#:$TNVM_DIR/[^/]*$2[^:]*##g" \
    -e "s#$TNVM_DIR/[^/]*$2[^:]*##g" \
    -e "s#$TNVM_DIR/versions/[^/]*/[^/]*$2[^:]*:##g" \
    -e "s#:$TNVM_DIR/versions/[^/]*/[^/]*$2[^:]*##g" \
    -e "s#$TNVM_DIR/versions/[^/]*/[^/]*$2[^:]*##g"
}

tnvm_prepend_path() {
  if [ -z "$1" ]; then
    echo "$2"
  else
    echo "$2:$1"
  fi
}

tnvm_binary_available() {
  # binaries started with node 0.11.12
  local FIRST_VERSION_WITH_BINARY
  FIRST_VERSION_WITH_BINARY="0.11.12"
  tnvm_version_greater_than_or_equal_to "$(tnvm_get_version $1)" "$FIRST_VERSION_WITH_BINARY"
}

tnvm_ls_current() {
  local NVM_LS_CURRENT_NODE_PATH
  NVM_LS_CURRENT_NODE_PATH="$(command which node 2> /dev/null)"
  if [ $? -ne 0 ]; then
    echo 'none'
  elif tnvm_tree_contains_path "$(tnvm_version_dir iojs-v)" "$NVM_LS_CURRENT_NODE_PATH"; then
    echo "(iojs $(iojs -v 2>/dev/null))"
  elif tnvm_tree_contains_path "$(tnvm_version_dir node-v)" "$NVM_LS_CURRENT_NODE_PATH"; then
    echo "(node $(node -v 2>/dev/null))"
  elif tnvm_tree_contains_path "$(tnvm_version_dir alinode-v)" "$NVM_LS_CURRENT_NODE_PATH"; then
    echo "(alinode $(node -V 2>/dev/null)) --> (node $(node -v 2>/dev/null))"
  elif tnvm_tree_contains_path "$(tnvm_version_dir profiler-v)" "$NVM_LS_CURRENT_NODE_PATH"; then
    echo "(profiler $(node -v 2>/dev/null))"
  else
    echo 'system'
  fi
}


tnvm_alinode_prefix() {
  echo "alinode"
}

tnvm_iojs_prefix() {
  echo "iojs"
}
tnvm_node_prefix() {
  echo "node"
}

tnvm_get_prefix() {
  echo "${1%-*}"
}

tnvm_get_version() {
  echo "${1#*-}"
}

# 访问本地
tnvm_ls() {
  local PATTERN
  PATTERN=$1
  local BASE_VERSIONS_DIR
  BASE_VERSIONS_DIR="$TNVM_DIR/versions"
  find $BASE_VERSIONS_DIR -maxdepth 2 -type d \
    | sed 's|'$BASE_VERSIONS_DIR'/||g' \
    | egrep "/v[0-9]+\.[0-9]+\.[0-9]+" \
    | sort -t. -u -k 1 -k 2,2n -k 3,3n \
    | sed 's|/|-|g' \
    | command grep -w "${PATTERN}"

}

tnvm_ls_remote() {
  local PATTERN
  PATTERN="$1"
  local VERSIONS
  local mirror
  case "$PATTERN" in
    "node") mirror=${MIRRORS[0]} ;;
    "iojs") mirror=${MIRRORS[1]} ;;
    "alinode") mirror=${MIRRORS[2]} ;;
    "profiler") mirror=${MIRRORS[3]} ;;
  esac

  VERSIONS=`tnvm_download -L -s $mirror/ -o - \
              | \egrep -o 'v[0-9]+\.[0-9]+\.[0-9]+' \
              | sort -t. -u -k 1.2,1n -k 2,2n -k 3,3n \
              | sed 's|^|'$PATTERN'-|g' `
  if [ -z "$VERSIONS" ]; then
    echo "N/A"
    return 3
  fi
  echo "$VERSIONS"
}


tnvm_checksum() {
  local NVM_CHECKSUM
  if tnvm_has "sha256sum" && ! tnvm_is_alias "sha256sum"; then
    NVM_CHECKSUM="$(command sha256sum "$1" | command awk '{print $1}')"
  elif tnvm_has "shasum" && ! tnvm_is_alias "shasum"; then
    NVM_CHECKSUM="$(command shasum -a 256 "$1" | command awk '{print $1}')"
  else
    echo "Unaliased sha256sum, or shasum not found." >&2
    return 2
  fi

  if [ "_$NVM_CHECKSUM" = "_$2" ]; then
    return
  elif [ -z "$2" ]; then
    echo 'Checksums empty' #missing in raspberry pi binary
    return
  else
    echo 'Checksums do not match.' >&2
    return 1
  fi
}

tnvm_print_versions() {
  local VERSION
  local FORMAT
  local NVM_CURRENT
  NVM_CURRENT=$(tnvm_ls_current)
  echo "$1" | while read VERSION; do
    if [ "_$VERSION" = "_$NVM_CURRENT" ]; then
      FORMAT='\033[0;32m-> %12s\033[0m'
    elif [ "$VERSION" = "system" ]; then
      FORMAT='\033[0;33m%15s\033[0m'
    elif [ -d "$(tnvm_version_path "$VERSION" 2> /dev/null)" ]; then
      FORMAT='\033[0;34m%15s\033[0m'
    else
      FORMAT='%15s'
    fi
    printf "$FORMAT\n" $VERSION
  done
}


tnvm_get_os() {
  local NVM_UNAME
  NVM_UNAME="$(uname -a)"
  local NVM_OS
  case "$NVM_UNAME" in
    Linux\ *) NVM_OS=linux ;;
    Darwin\ *) NVM_OS=darwin ;;
    SunOS\ *) NVM_OS=sunos ;;
    FreeBSD\ *) NVM_OS=freebsd ;;
  esac
  echo "$NVM_OS"
}

tnvm_get_arch() {
  local NVM_UNAME
  NVM_UNAME="$(uname -m)"
  local NVM_ARCH
  case "$NVM_UNAME" in
    x86_64) NVM_ARCH="x64" ;;
    i*86) NVM_ARCH="x86" ;;
    *) NVM_ARCH="$NVM_UNAME" ;;
  esac
  echo "$NVM_ARCH"
}


tnvm_install_binary() {
  local PREFIXED_VERSION
  PREFIXED_VERSION="$1"

  local VERSION
  VERSION="$(tnvm_get_version "$PREFIXED_VERSION")" #v0.12.4
  local PREFIX
  PREFIX="$(tnvm_get_prefix "$PREFIXED_VERSION")" #node, iojs, alinode


  local VERSION_PATH
  VERSION_PATH="$(tnvm_version_path "$PREFIXED_VERSION")"
  local NVM_OS
  NVM_OS="$(tnvm_get_os)"
  local t
  local url
  local sum
  local mirror

  case "$PREFIX" in
    "node") mirror=${MIRRORS[0]} ;;
    "iojs") mirror=${MIRRORS[1]} ;;
    "alinode") mirror=${MIRRORS[2]} ;;
    "profiler") mirror=${MIRRORS[3]} ;;
  esac

  if [ -n "$NVM_OS" ]; then
    if tnvm_binary_available "$VERSION"; then
      t="$VERSION-$NVM_OS-$(tnvm_get_arch)"
      url="$mirror/$VERSION/$PREFIX-${t}.tar.gz"
      sum="$(tnvm_download -L -s $mirror/$VERSION/SHASUMS256.txt -o - \
           | command grep $PREFIX-${t}.tar.gz | command awk '{print $1}')"
      if [ -z "$sum" ]; then
        echo >&2 "Binary download failed, $PREFIX-${t}.tar.gz N/A." >&2
        return 2
      fi
      local tmpdir
      tmpdir="$TNVM_DIR/bin/$PREFIX-${t}"
      local tmptarball
      tmptarball="$tmpdir/$PREFIX-${t}.tar.gz"
      local NVM_INSTALL_ERRORED
      command mkdir -p "$tmpdir" && \
        tnvm_download -L -C - --progress-bar $url -o "$tmptarball" || \
        NVM_INSTALL_ERRORED=true
      if grep '404 Not Found' "$tmptarball" >/dev/null; then
        NVM_INSTALL_ERRORED=true
        echo >&2 "HTTP 404 at URL $url";
      fi
      if (
        [ "$NVM_INSTALL_ERRORED" != true ] && \
        tnvm_checksum "$tmptarball" $sum && \
        command tar -xzf "$tmptarball" -C "$tmpdir" --strip-components 1 && \
        command rm -f "$tmptarball" && \
        command mkdir -p "$VERSION_PATH" && \
        command mv "$tmpdir"/* "$VERSION_PATH"
      ); then
        return 0
      else
        echo >&2 "Binary download failed, trying source." >&2
        command rm -rf "$tmptarball" "$tmpdir"
        return 1
      fi
    fi
  fi
  return 2
}

tnvm_check_params() {
  if [ "_$1" = '_system' ]; then
    return
  fi
  echo "$1" | egrep -o '^[a-z]+-v[0-9]+\.[0-9]+\.[0-9]+$' > /dev/null
}

tnvm() {
  if [ $# -lt 1 ]; then
    tnvm help
    return
  fi

  local GREP_OPTIONS
  GREP_OPTIONS=''

  # initialize local variables
  local VERSION

  case $1 in
    "help" )
      echo
      echo "Taobao Node Version Manager"
      echo
      echo "Usage:"
      echo "  tnvm help                                       Show this message"
      echo "  tnvm -v                                         Print out the latest released version of tnvm"
      echo "  tnvm install <version>                          Download and install a <version>"
      echo "  tnvm uninstall <version>                        Uninstall a version"
      echo "  tnvm use <version>                              Modify PATH to use <version>. Uses .tnvmrc if available"
      echo "  tnvm current                                    Display currently activated version"
      echo "  tnvm ls [node|alinode|iojs|profiler]            List versions matching a given description"
      echo "  tnvm ls-remote [node|alinode|iojs|profiler]     List remote versions available for install"
      echo "  tnvm deactivate                                 Undo effects of \`tnvm\` on current shell"
      echo "  tnvm unload                                     Unload \`tnvm\` from shell"

      echo
      echo "Example:"
      echo "  tnvm install alinode-v0.12.4           Install a specific version number"
      echo "  tnvm use alinode-0.12.4                Use the latest available 0.10.x release"
      echo
      echo "Note:"
      echo "  to remove, delete, or uninstall tnvm - just remove ~/.tnvm, ~/.npm, and ~/.bower folders"
      echo
    ;;


    "install" | "i" )
      local nobinary
      local version_not_provided
      version_not_provided=0
      local provided_version
      local NVM_OS
      NVM_OS="$(tnvm_get_os)"

      if ! tnvm_has "curl" && ! tnvm_has "wget"; then
        echo 'nvm needs curl or wget to proceed.' >&2;
        return 1
      fi

      if [ $# -lt 2 ]; then
        version_not_provided=1
        >&2 tnvm help
        return 127
      fi

      shift

      nobinary=0
      provided_version="$1"
      if ! tnvm_check_params "$1" ; then
        echo "Version '$1' not vaild." >&2
        return 3
      fi
      VERSION="$(tnvm_remote_version "$provided_version")"

      if [ "_$VERSION" = "_N/A" ]; then
        echo "Version '$provided_version' not found - try \`tnvm ls-remote\` to browse available versions." >&2
        return 3
      fi
      echo $VERSION
      local VERSION_PATH
      VERSION_PATH="$(tnvm_version_path "$VERSION")"
      if [ -d "$VERSION_PATH" ]; then
        echo "$VERSION is already installed." >&2
        return $?
      fi

      if [ "_$NVM_OS" = "_freebsd" ] || [ "_$NVM_OS" = "_sunos" ]; then
        # node.js and io.js do not have a FreeBSD binary
        nobinary=1
      fi
      local NVM_INSTALL_SUCCESS
      # skip binary install if "nobinary" option specified.
      if [ $nobinary -ne 1 ] && tnvm_binary_available "$VERSION"; then
        if tnvm_install_binary "$VERSION"; then
          NVM_INSTALL_SUCCESS=true
        fi
      fi
      if [ "$NVM_INSTALL_SUCCESS" != true ]; then
         echo "Installing binary from source is not currently supported" >&2
         return 105
      fi
      return $?
    ;;
    "uninstall" )
      if [ $# -ne 2 ]; then
        >&2 tnvm help
        return 127
      fi

      local PATTERN
      PATTERN="$2"

      if ! tnvm_check_params "$2" ; then
        echo "Version '$2' not vaild." >&2
        return 3
      fi

      VERSION="$(tnvm_version "$PATTERN")"
      if [ "_$VERSION" = "_$(tnvm_ls_current)" ]; then
        echo "tnvm: Cannot uninstall currently-active node version, $VERSION (inferred from $PATTERN)." >&2
        return 1
      fi

      local VERSION_PATH
      VERSION_PATH="$(tnvm_version_path "$VERSION")"
      if [ ! -d "$VERSION_PATH" ]; then
        echo "$VERSION version is not installed..." >&2
        return;
      fi

      t="$VERSION-$(tnvm_get_os)-$(tnvm_get_arch)"

      local NVM_PREFIX
      local NVM_SUCCESS_MSG

      NVM_PREFIX="$(tnvm_get_prefix)"
      NVM_SUCCESS_MSG="Uninstalled  $VERSION and reopen your terminal."

      # Delete all files related to target version.
      command rm -rf "$TNVM_DIR/src/$NVM_PREFIX-$VERSION" \
             "$TNVM_DIR/src/$NVM_PREFIX-$VERSION.tar.gz" \
             "$TNVM_DIR/bin/$NVM_PREFIX-${t}" \
             "$TNVM_DIR/bin/$NVM_PREFIX-${t}.tar.gz" \
             "$VERSION_PATH" 2>/dev/null
      echo "$NVM_SUCCESS_MSG"
    ;;
    "deactivate" )
      local NEWPATH
      NEWPATH="$(tnvm_strip_path "$PATH" "/bin")"
      if [ "_$PATH" = "_$NEWPATH" ]; then
        echo "Could not find $TNVM_DIR/*/bin in \$PATH" >&2
      else
        export PATH="$NEWPATH"
        hash -r
        echo "$TNVM_DIR/*/bin removed from \$PATH"
      fi

      NEWPATH="$(tnvm_strip_path "$MANPATH" "/share/man")"
      if [ "_$MANPATH" = "_$NEWPATH" ]; then
        echo "Could not find $TNVM_DIR/*/share/man in \$MANPATH" >&2
      else
        export MANPATH="$NEWPATH"
        echo "$TNVM_DIR/*/share/man removed from \$MANPATH"
      fi

      NEWPATH="$(tnvm_strip_path "$NODE_PATH" "/lib/node_modules")"
      if [ "_$NODE_PATH" != "_$NEWPATH" ]; then
        export NODE_PATH="$NEWPATH"
        echo "$TNVM_DIR/*/lib/node_modules removed from \$NODE_PATH"
      fi
    ;;
    "use" )
      local PROVIDED_VERSION
      if [ $# -eq 1 ]; then
        >&2 tnvm help
        return 127
      else
        PROVIDED_VERSION="$2"
        VERSION="$PROVIDED_VERSION"
      fi
      if ! tnvm_check_params "$2" ; then
        echo "Version '$2' not vaild." >&2
        return 3
      fi
      if [ -z "$VERSION" ]; then
        >&2 tnvm help
        return 127
      fi

      if [ "_$VERSION" = '_system' ]; then
        if tnvm_has_system_node && tnvm deactivate >/dev/null 2>&1; then
          echo "Now using system version of node: $(node -v 2>/dev/null)$(tnvm_print_npm_version)"
          return
        elif tnvm_has_system_iojs && tnvm deactivate >/dev/null 2>&1; then
          echo "Now using system version of io.js: $(iojs --version 2>/dev/null)$(tnvm_print_npm_version)"
          return
        else
          echo "System version of node not found." >&2
          return 127
        fi
      elif [ "_$VERSION" = "_∞" ]; then
        echo "The alias \"$PROVIDED_VERSION\" leads to an infinite loop. Aborting." >&2
        return 8
      fi

      # This tnvm_ensure_version_installed call can be a performance bottleneck
      # on shell startup. Perhaps we can optimize it away or make it faster.
      tnvm_ensure_version_installed "$PROVIDED_VERSION"
      EXIT_CODE=$?
      if [ "$EXIT_CODE" != "0" ]; then
        return $EXIT_CODE
      fi

      local NVM_VERSION_DIR
      NVM_VERSION_DIR="$(tnvm_version_path "$VERSION")"

      # Strip other version from PATH
      PATH="$(tnvm_strip_path "$PATH" "/bin")"
      # Prepend current version
      PATH="$(tnvm_prepend_path "$PATH" "$NVM_VERSION_DIR/bin")"
      if tnvm_has manpath; then
        if [ -z "$MANPATH" ]; then
          MANPATH=$(manpath)
        fi
        # Strip other version from MANPATH
        MANPATH="$(tnvm_strip_path "$MANPATH" "/share/man")"
        # Prepend current version
        MANPATH="$(tnvm_prepend_path "$MANPATH" "$NVM_VERSION_DIR/share/man")"
        export MANPATH
      fi
      export PATH
      hash -r
      export NVM_PATH="$NVM_VERSION_DIR/lib/node"
      export NVM_BIN="$NVM_VERSION_DIR/bin"
      echo "$VERSION" > "$TNVM_DIR/.tnvmrc" >/dev/null 2>&1
      echo "Now using node $VERSION$(tnvm_print_npm_version)"

    ;;
    "ls" | "list" )
      local NVM_LS_OUTPUT
      local NVM_LS_EXIT_CODE
      if [ $# -eq 1 ]; then
        >&2 tnvm help
        return 127
      fi
      NVM_LS_OUTPUT=$(tnvm_ls "$2")
      NVM_LS_EXIT_CODE=$?
      tnvm_print_versions "$NVM_LS_OUTPUT"
      return $NVM_LS_EXIT_CODE
    ;;
    "ls-remote" | "list-remote" )
      local PATTERN
      PATTERN="$2"

      local NVM_LS_REMOTE_EXIT_CODE
      NVM_LS_REMOTE_EXIT_CODE=0
      local NVM_LS_REMOTE_OUTPUT
      NVM_LS_REMOTE_OUTPUT=$(tnvm_ls_remote "$PATTERN")
      NVM_LS_REMOTE_EXIT_CODE=$?

      local NVM_OUTPUT
      NVM_OUTPUT="$(echo "$NVM_LS_REMOTE_OUTPUT" | command grep -v "N/A" | sed '/^$/d')"
      if [ -n "$NVM_OUTPUT" ]; then
        tnvm_print_versions "$NVM_OUTPUT"
        return $NVM_LS_REMOTE_EXIT_CODE
      else
        tnvm_print_versions "N/A"
        return 3
      fi
    ;;
    "current" )
      tnvm_version current
    ;;

    "clear-cache" )
      command rm -rf $TNVM_DIR/v* "$(tnvm_version_dir)" 2>/dev/null
      echo "Cache cleared."
    ;;

    "--v" | "-v" )
      echo "v1.x"
    ;;

    "unload" )
      unset -f tnvm tnvm_print_versions tnvm_checksum \
        tnvm_iojs_prefix tnvm_node_prefix \
        tnvm_ls_remote tnvm_ls tnvm_remote_version tnvm_remote_versions \
        tnvm_version tnvm_check_params \
        tnvm_version_greater tnvm_version_greater_than_or_equal_to \
        tnvm_supports_source_options > /dev/null 2>&1
      unset TNVM_DIR NVM_CD_FLAGS > /dev/null 2>&1
    ;;
    * )
      >&2 tnvm help
      return 127
    ;;
  esac
}

if tnvm_rc_version >/dev/null 2>&1; then
  tnvm use "$TNVM_RC_VERSION" >/dev/null 2>&1
fi

} # this ensures the entire script is downloaded #


#tnvm_version_dir
#tnvm_ls "node"
#tnvm_ls "iojs"
#tnvm_remote_versions "alinode"
#tnvm_remote_version "alinode-v0.12.5"
#tnvm_remote_version "alinode-v0.12.7"
#tnvm_ls "node-v0.12.4"
#tnvm_version "node-v0.12.4"
#tnvm_ensure_version_installed "node-v0.12.4"

# cmd test
#tnvm --version
#tnvm list-remote "iojs"
#tnvm ls-remote "alinode"
#tnvm install "node-v0.12.4"
#tnvm install "alinode-v0.12.4"
#tnvm install "iojs-v2.4.0"

#tnvm use "node-v0.12.4"

#tnvm ls "node"
#tnvm install "alinode-v0.12.4"
#tnvm install "profiler-v0.12.6"
#tnvm use "profiler-v0.12.6"
