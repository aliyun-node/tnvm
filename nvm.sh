# Node Version Manager
# Implemented as a POSIX-compliant function
# Should work on sh, dash, bash, ksh, zsh
# To use source this file from your bash profile
#
# Implemented by Tim Caswell <tim@creationix.com>
# with much bash help from Matthew Ranney

{ # this ensures the entire script is downloaded #

NVM_SCRIPT_SOURCE="$_"

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


# Setup mirror location if not already set
if [ -z "$TNVM_NODEJS_ORG_MIRROR" ]; then
  export TNVM_NODEJS_ORG_MIRROR="http://121.43.234.185:8000/dist/node"
fi


if [ -z "$TNVM_IOJS_ORG_MIRROR" ]; then
  export TNVM_IOJS_ORG_MIRROR="http://121.43.234.185:8000/dist/iojs"
fi


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

# Traverse up in directory tree to find containing folder
tnvm_find_up() {
  local path
  path=$PWD
  while [ "$path" != "" ] && [ ! -f "$path/$1" ]; do
    path=${path%/*}
  done
  echo "$path"
}


tnvm_find_nvmrc() {
  local dir
  dir="$(tnvm_find_up '.tnvmrc')"
  if [ -e "$dir/.tnvmrc" ]; then
    echo "$dir/.tnvmrc"
  fi
}

# Obtain nvm version from rc file
tnvm_rc_version() {
  export TNVM_RC_VERSION=''
  local NVMRC_PATH
  NVMRC_PATH="$(tnvm_find_nvmrc)"
  if [ -e "$NVMRC_PATH" ]; then
    read TNVM_RC_VERSION < "$NVMRC_PATH"
    echo "Found '$NVMRC_PATH' with version <$TNVM_RC_VERSION>"
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
# todo 区分
tnvm_version_dir() {
  local NVM_WHICH_DIR
  NVM_WHICH_DIR="$1"
  if [ -z "$NVM_WHICH_DIR" ] || [ "_$NVM_WHICH_DIR" = "_new" ]; then
    echo "$TNVM_DIR/ali_versions/node"
  elif [ "_$NVM_WHICH_DIR" = "_iojs" ]; then
    echo "$TNVM_DIR/ali_versions/io.js"
  elif [ "_$NVM_WHICH_DIR" = "_old" ]; then
    echo "$TNVM_DIR"
  else
    echo "unknown version dir" >&2
    return 3
  fi
}

tnvm_alias_path() {
  echo "$(tnvm_version_dir old)/alias"
}
# todo
tnvm_version_path() {
  local VERSION
  VERSION="$1"
  if [ -z "$VERSION" ]; then
    echo "version is required" >&2
    return 3
  elif tnvm_is_iojs_version "$VERSION"; then
    echo "$(tnvm_version_dir iojs)/$(tnvm_strip_iojs_prefix "$VERSION")"
  elif tnvm_version_greater 0.12.0 "$VERSION"; then
    echo "$(tnvm_version_dir old)/$VERSION"
  else
    echo "$(tnvm_version_dir new)/$VERSION"
  fi
}

tnvm_ensure_version_installed() {
  local PROVIDED_VERSION
  PROVIDED_VERSION="$1"
  local LOCAL_VERSION
  LOCAL_VERSION="$(tnvm_version "$PROVIDED_VERSION")"
  local NVM_VERSION_DIR
  NVM_VERSION_DIR="$(tnvm_version_path "$LOCAL_VERSION")"
  if [ ! -d "$NVM_VERSION_DIR" ]; then
    VERSION="$(tnvm_resolve_alias "$PROVIDED_VERSION")"
    if [ $? -eq 0 ]; then
      echo "N/A: version \"$PROVIDED_VERSION -> $VERSION\" is not yet installed" >&2
    else
      echo "N/A: version \"$(tnvm_ensure_version_prefix "$PROVIDED_VERSION")\" is not yet installed" >&2
    fi
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

  local NVM_NODE_PREFIX
  NVM_NODE_PREFIX="$(tnvm_node_prefix)"
  case "_$PATTERN" in
    "_$NVM_NODE_PREFIX" | "_$NVM_NODE_PREFIX-")
      PATTERN="stable"
    ;;
  esac
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
  PATTERN="$1"
  local VERSION
  if tnvm_validate_implicit_alias "$PATTERN" 2> /dev/null ; then
    case "_$PATTERN" in
      "_$(tnvm_iojs_prefix)")
        VERSION="$(tnvm_ls_remote_iojs | tail -n1)"
      ;;
      *)
        VERSION="$(tnvm_ls_remote "$PATTERN")"
      ;;
    esac
  else
    VERSION="$(tnvm_remote_versions "$PATTERN" | tail -n1)"
  fi
  echo "$VERSION"
  if [ "_$VERSION" = '_N/A' ]; then
    return 3
  fi
}
#todo
tnvm_remote_versions() {
  local NVM_IOJS_PREFIX
  NVM_IOJS_PREFIX="$(tnvm_iojs_prefix)"
  local PATTERN
  PATTERN="$1"
  case "_$PATTERN" in
    "_$NVM_IOJS_PREFIX" | "_io.js")
      VERSIONS="$(tnvm_ls_remote_iojs)"
    ;;
    "_$(tnvm_node_prefix)")
      VERSIONS="$(tnvm_ls_remote)"
    ;;
    *)
      if tnvm_validate_implicit_alias "$PATTERN" 2> /dev/null ; then
        echo >&2 "Implicit aliases are not supported in tnvm_remote_versions."
        return 1
      fi
      VERSIONS="$(echo "$(tnvm_ls_remote "$PATTERN")
$(tnvm_ls_remote_iojs "$PATTERN")" | command grep -v "N/A" | command sed '/^$/d')"
    ;;
  esac

  if [ -z "$VERSIONS" ]; then
    echo "N/A"
    return 3
  else
    echo "$VERSIONS"
  fi
}

tnvm_is_valid_version() {
  if tnvm_validate_implicit_alias "$1" 2> /dev/null; then
    return 0
  fi
  case "$1" in
    "$(tnvm_iojs_prefix)" | "$(tnvm_node_prefix)")
      return 0
    ;;
    *)
      local VERSION
      VERSION="$(tnvm_strip_iojs_prefix "$1")"
      tnvm_version_greater "$VERSION"
    ;;
  esac
}

tnvm_normalize_version() {
  echo "${1#v}" | command awk -F. '{ printf("%d%06d%06d\n", $1,$2,$3); }'
}

tnvm_ensure_version_prefix() {
  local NVM_VERSION
  NVM_VERSION="$(tnvm_strip_iojs_prefix "$1" | command sed -e 's/^\([0-9]\)/v\1/g')"
  if tnvm_is_iojs_version "$1"; then
    echo "$(tnvm_add_iojs_prefix "$NVM_VERSION")"
  else
    echo "$NVM_VERSION"
  fi
}

tnvm_format_version() {
  local VERSION
  VERSION="$(tnvm_ensure_version_prefix "$1")"
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
    -e "s#$TNVM_DIR/ali_versions/[^/]*/[^/]*$2[^:]*:##g" \
    -e "s#:$TNVM_DIR/ali_versions/[^/]*/[^/]*$2[^:]*##g" \
    -e "s#$TNVM_DIR/ali_versions/[^/]*/[^/]*$2[^:]*##g"
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
  tnvm_version_greater_than_or_equal_to "$(tnvm_strip_iojs_prefix $1)" "$FIRST_VERSION_WITH_BINARY"
}

tnvm_alias() {
  local ALIAS
  ALIAS="$1"
  if [ -z "$ALIAS" ]; then
    echo >&2 'An alias is required.'
    return 1
  fi

  local NVM_ALIAS_PATH
  NVM_ALIAS_PATH="$(tnvm_alias_path)/$ALIAS"
  if [ ! -f "$NVM_ALIAS_PATH" ]; then
    echo >&2 'Alias does not exist.'
    return 2
  fi

  cat "$NVM_ALIAS_PATH"
}
#todo
tnvm_ls_current() {
  local NVM_LS_CURRENT_NODE_PATH
  NVM_LS_CURRENT_NODE_PATH="$(command which node 2> /dev/null)"
  if [ $? -ne 0 ]; then
    echo 'none'
  elif tnvm_tree_contains_path "$(tnvm_version_dir iojs)" "$NVM_LS_CURRENT_NODE_PATH"; then
    echo "$(ali-iojs $(iojs --version 2>/dev/null))"
  elif tnvm_tree_contains_path "$TNVM_DIR" "$NVM_LS_CURRENT_NODE_PATH"; then
    local VERSION
    VERSION="(ali-node $(node --version 2>/dev/null))"
    echo "$VERSION"
  else
    echo 'system'
  fi
}

tnvm_resolve_alias() {
  if [ -z "$1" ]; then
    return 1
  fi

  local PATTERN
  PATTERN="$1"

  local ALIAS
  ALIAS="$PATTERN"
  local ALIAS_TEMP

  local SEEN_ALIASES
  SEEN_ALIASES="$ALIAS"
  while true; do
    ALIAS_TEMP="$(tnvm_alias "$ALIAS" 2> /dev/null)"

    if [ -z "$ALIAS_TEMP" ]; then
      break
    fi

    if [ -n "$ALIAS_TEMP" ] \
      && printf "$SEEN_ALIASES" | command grep -e "^$ALIAS_TEMP$" > /dev/null; then
      ALIAS="∞"
      break
    fi

    SEEN_ALIASES="$SEEN_ALIASES\n$ALIAS_TEMP"
    ALIAS="$ALIAS_TEMP"
  done

  if [ -n "$ALIAS" ] && [ "_$ALIAS" != "_$PATTERN" ]; then
    local NVM_IOJS_PREFIX
    NVM_IOJS_PREFIX="$(tnvm_iojs_prefix)"
    local NVM_NODE_PREFIX
    NVM_NODE_PREFIX="$(tnvm_node_prefix)"
    case "_$ALIAS" in
      "_∞" | \
      "_$NVM_IOJS_PREFIX" | "_$NVM_IOJS_PREFIX-" | \
      "_$NVM_NODE_PREFIX" )
        echo "$ALIAS"
      ;;
      *)
        tnvm_ensure_version_prefix "$ALIAS"
      ;;
    esac
    return 0
  fi

  if tnvm_validate_implicit_alias "$PATTERN" 2> /dev/null ; then
    local IMPLICIT
    IMPLICIT="$(tnvm_print_implicit_alias local "$PATTERN" 2> /dev/null)"
    if [ -n "$IMPLICIT" ]; then
      tnvm_ensure_version_prefix "$IMPLICIT"
    fi
  fi

  return 2
}

tnvm_resolve_local_alias() {
  if [ -z "$1" ]; then
    return 1
  fi

  local VERSION
  local EXIT_CODE
  VERSION="$(tnvm_resolve_alias "$1")"
  EXIT_CODE=$?
  if [ -z "$VERSION" ]; then
    return $EXIT_CODE
  fi
  if [ "_$VERSION" != "_∞" ]; then
    tnvm_version "$VERSION"
  else
    echo "$VERSION"
  fi
}

tnvm_iojs_prefix() {
  echo "iojs"
}
tnvm_node_prefix() {
  echo "node"
}

tnvm_is_iojs_version() {
  case "$1" in iojs-*) return 0 ;; esac
  return 1
}

tnvm_add_iojs_prefix() {
  command echo "$(tnvm_iojs_prefix)-$(tnvm_ensure_version_prefix "$(tnvm_strip_iojs_prefix "$1")")"
}

tnvm_strip_iojs_prefix() {
  local NVM_IOJS_PREFIX
  NVM_IOJS_PREFIX="$(tnvm_iojs_prefix)"
  if [ "_$1" = "_$NVM_IOJS_PREFIX" ]; then
    echo
  else
    echo "${1#"$NVM_IOJS_PREFIX"-}"
  fi
}

tnvm_ls() {
  local PATTERN
  PATTERN="$1"
  local VERSIONS
  VERSIONS=''
  if [ "$PATTERN" = 'current' ]; then
    tnvm_ls_current
    return
  fi

  local NVM_IOJS_PREFIX
  NVM_IOJS_PREFIX="$(tnvm_iojs_prefix)"
  local NVM_NODE_PREFIX
  NVM_NODE_PREFIX="$(tnvm_node_prefix)"
  local NVM_VERSION_DIR_IOJS
  NVM_VERSION_DIR_IOJS="$(tnvm_version_dir iojs)"
  local NVM_VERSION_DIR_NEW
  NVM_VERSION_DIR_NEW="$(tnvm_version_dir new)"
  local NVM_VERSION_DIR_OLD
  NVM_VERSION_DIR_OLD="$(tnvm_version_dir old)"

  case "$PATTERN" in
    "$NVM_IOJS_PREFIX" | "$NVM_NODE_PREFIX" )
      PATTERN="$PATTERN-"
    ;;
    *)
      if tnvm_resolve_local_alias "$PATTERN"; then
        return
      fi
      PATTERN=$(tnvm_ensure_version_prefix $PATTERN)
    ;;
  esac
  # If it looks like an explicit version, don't do anything funny
  local NVM_PATTERN_STARTS_WITH_V
  case $PATTERN in
    v*) NVM_PATTERN_STARTS_WITH_V=true ;;
    *) NVM_PATTERN_STARTS_WITH_V=false ;;
  esac
  if [ $NVM_PATTERN_STARTS_WITH_V = true ] && [ "_$(tnvm_num_version_groups "$PATTERN")" = "_3" ]; then
    if [ -d "$(tnvm_version_path "$PATTERN")" ]; then
      VERSIONS="$PATTERN"
    elif [ -d "$(tnvm_version_path "$(tnvm_add_iojs_prefix "$PATTERN")")" ]; then
      VERSIONS="$(tnvm_add_iojs_prefix "$PATTERN")"
    fi
  else
    case "$PATTERN" in
      "$NVM_IOJS_PREFIX-" | "$NVM_NODE_PREFIX-" | "system") ;;
      *)
        local NUM_VERSION_GROUPS
        NUM_VERSION_GROUPS="$(tnvm_num_version_groups "$PATTERN")"
        if [ "_$NUM_VERSION_GROUPS" = "_2" ] || [ "_$NUM_VERSION_GROUPS" = "_1" ]; then
          PATTERN="${PATTERN%.}."
        fi
      ;;
    esac

    local ZHS_HAS_SHWORDSPLIT_UNSET
    ZHS_HAS_SHWORDSPLIT_UNSET=1
    if tnvm_has "setopt"; then
      ZHS_HAS_SHWORDSPLIT_UNSET=$(setopt | command grep shwordsplit > /dev/null ; echo $?)
      setopt shwordsplit
    fi

    local TNVM_DIRS_TO_TEST_AND_SEARCH
    local TNVM_DIRS_TO_SEARCH
    local NVM_ADD_SYSTEM
    NVM_ADD_SYSTEM=false
    if tnvm_is_iojs_version "$PATTERN"; then
      TNVM_DIRS_TO_TEST_AND_SEARCH="$NVM_VERSION_DIR_IOJS"
      PATTERN="$(tnvm_strip_iojs_prefix "$PATTERN")"
      if tnvm_has_system_iojs; then
        NVM_ADD_SYSTEM=true
      fi
    elif [ "_$PATTERN" = "_$NVM_NODE_PREFIX-" ]; then
      TNVM_DIRS_TO_TEST_AND_SEARCH="$NVM_VERSION_DIR_OLD $NVM_VERSION_DIR_NEW"
      PATTERN=''
      if tnvm_has_system_node; then
        NVM_ADD_SYSTEM=true
      fi
    else
      TNVM_DIRS_TO_TEST_AND_SEARCH="$NVM_VERSION_DIR_OLD $NVM_VERSION_DIR_NEW $NVM_VERSION_DIR_IOJS"
      if tnvm_has_system_iojs || tnvm_has_system_node; then
        NVM_ADD_SYSTEM=true
      fi
    fi
    for NVM_VERSION_DIR in $TNVM_DIRS_TO_TEST_AND_SEARCH; do
      if [ -d "$NVM_VERSION_DIR" ]; then
        TNVM_DIRS_TO_SEARCH="$NVM_VERSION_DIR $TNVM_DIRS_TO_SEARCH"
      fi
    done

    if [ -z "$PATTERN" ]; then
      PATTERN='v'
    fi
    if [ -n "$TNVM_DIRS_TO_SEARCH" ]; then
      VERSIONS="$(command find $TNVM_DIRS_TO_SEARCH -maxdepth 1 -type d -name "$PATTERN*" \
        | command sed "
            s#$NVM_VERSION_DIR_IOJS/#$NVM_IOJS_PREFIX-#;
            \#$NVM_VERSION_DIR_IOJS# d;
            s#^$TNVM_DIR/##;
            \#^ali_versions\$# d;
            s#^ali_versions/##;
            s#^v#$NVM_NODE_PREFIX-v#;
            s#^\($NVM_IOJS_PREFIX\)[-/]v#\1.v#;
            s#^\($NVM_NODE_PREFIX\)[-/]v#\1.v#" \
        | command sort -t. -u -k 2.2,2n -k 3,3n -k 4,4n \
        | command sort -s -t- -k1.1,1.1 \
        | command sed "
            s/^\($NVM_IOJS_PREFIX\)\./\1-/;
            s/^$NVM_NODE_PREFIX\.//")"
    fi

    if [ $ZHS_HAS_SHWORDSPLIT_UNSET -eq 1 ] && tnvm_has "unsetopt"; then
      unsetopt shwordsplit
    fi
  fi

  if [ "$NVM_ADD_SYSTEM" = true ]; then
    if [ -z "$PATTERN" ] || [ "_$PATTERN" = "_v" ]; then
      VERSIONS="$VERSIONS$(command printf '\n%s' 'system')"
    elif [ "$PATTERN" = 'system' ]; then
      VERSIONS="$(command printf '%s' 'system')"
    fi
  fi

  if [ -z "$VERSIONS" ]; then
    echo "N/A"
    return 3
  fi

  echo "$VERSIONS"
}

tnvm_ls_remote() {
  local PATTERN
  PATTERN="$1"
  local VERSIONS
  local GREP_OPTIONS
  GREP_OPTIONS=''
  if tnvm_validate_implicit_alias "$PATTERN" 2> /dev/null ; then
    PATTERN="$(tnvm_ls_remote "$(tnvm_print_implicit_alias remote "$PATTERN")" | tail -n1)"
  elif [ -n "$PATTERN" ]; then
    PATTERN="$(tnvm_ensure_version_prefix "$PATTERN")"
  else
    PATTERN=".*"
  fi
  VERSIONS=`tnvm_download -L -s $TNVM_NODEJS_ORG_MIRROR/ -o - \
              | \egrep -o 'v[0-9]+\.[0-9]+\.[0-9]+' \
              | command grep -w "${PATTERN}" \
              | sort -t. -u -k 1.2,1n -k 2,2n -k 3,3n`
  if [ -z "$VERSIONS" ]; then
    echo "N/A"
    return 3
  fi
  echo "$VERSIONS"
}

tnvm_ls_remote_iojs() {
  local PATTERN
  PATTERN="$1"
  local VERSIONS
  if [ -n "$PATTERN" ]; then
    PATTERN="$(tnvm_ensure_version_prefix $(tnvm_strip_iojs_prefix "$PATTERN"))"
  else
    PATTERN=".*"
  fi
  VERSIONS=`tnvm_download -L -s $TNVM_IOJS_ORG_MIRROR/ -o - \
              | \egrep -o 'v[0-9]+\.[0-9]+\.[0-9]+' \
              | command grep -w "${PATTERN}" \
              | command sed "s/^/$(tnvm_iojs_prefix)-/" \
              | sort -t. -u -k 1.2,1n -k 2,2n -k 3,3n`
  if [ -z "$VERSIONS" ]; then
    echo "N/A"
    return 3
  fi
  echo "$VERSIONS"
}

tnvm_checksum() {
  local NVM_CHECKSUM
  if tnvm_has "sha1sum" && ! tnvm_is_alias "sha1sum"; then
    NVM_CHECKSUM="$(command sha1sum "$1" | command awk '{print $1}')"
  elif tnvm_has "sha1" && ! tnvm_is_alias "sha1"; then
    NVM_CHECKSUM="$(command sha1 -q "$1")"
  elif tnvm_has "shasum" && ! tnvm_is_alias "shasum"; then
    NVM_CHECKSUM="$(shasum "$1" | command awk '{print $1}')"
  else
    echo "Unaliased sha1sum, sha1, or shasum not found." >&2
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

tnvm_validate_implicit_alias() {
  local NVM_IOJS_PREFIX
  NVM_IOJS_PREFIX="$(tnvm_iojs_prefix)"
  local NVM_NODE_PREFIX
  NVM_NODE_PREFIX="$(tnvm_node_prefix)"

  case "$1" in
    "stable" | "unstable" | "$NVM_IOJS_PREFIX" | "$NVM_NODE_PREFIX" )
      return
    ;;
    *)
      echo "Only implicit aliases 'stable', 'unstable', '$NVM_IOJS_PREFIX', and '$NVM_NODE_PREFIX' are supported." >&2
      return 1
    ;;
  esac
}

tnvm_print_implicit_alias() {
  if [ "_$1" != "_local" ] && [ "_$1" != "_remote" ]; then
    echo "tnvm_print_implicit_alias must be specified with local or remote as the first argument." >&2
    return 1
  fi

  if ! tnvm_validate_implicit_alias "$2"; then
    return 2
  fi

  local ZHS_HAS_SHWORDSPLIT_UNSET

  local NVM_IOJS_PREFIX
  NVM_IOJS_PREFIX="$(tnvm_iojs_prefix)"
  local NVM_NODE_PREFIX
  NVM_NODE_PREFIX="$(tnvm_node_prefix)"
  local NVM_COMMAND
  local LAST_TWO
  case "$2" in
    "$NVM_IOJS_PREFIX")
      NVM_COMMAND="tnvm_ls_remote_iojs"
      if [ "_$1" = "_local" ]; then
        NVM_COMMAND="tnvm_ls iojs"
      fi

      ZHS_HAS_SHWORDSPLIT_UNSET=1
      if tnvm_has "setopt"; then
        ZHS_HAS_SHWORDSPLIT_UNSET=$(setopt | command grep shwordsplit > /dev/null ; echo $?)
        setopt shwordsplit
      fi

      local NVM_IOJS_VERSION
      NVM_IOJS_VERSION="$($NVM_COMMAND | sed "s/^"$NVM_IOJS_PREFIX"-//" | command grep -e '^v' | cut -c2- | cut -d . -f 1,2 | uniq | tail -1)"
      local EXIT_CODE
      EXIT_CODE="$?"

      if [ $ZHS_HAS_SHWORDSPLIT_UNSET -eq 1 ] && tnvm_has "unsetopt"; then
        unsetopt shwordsplit
      fi

      echo "$(tnvm_add_iojs_prefix "$NVM_IOJS_VERSION")"
      return $EXIT_CODE
    ;;
    "$NVM_NODE_PREFIX")
      echo "stable"
      return
    ;;
    *)
      NVM_COMMAND="tnvm_ls_remote"
      if [ "_$1" = "_local" ]; then
        NVM_COMMAND="tnvm_ls node"
      fi

      ZHS_HAS_SHWORDSPLIT_UNSET=1
      if tnvm_has "setopt"; then
        ZHS_HAS_SHWORDSPLIT_UNSET=$(setopt | command grep shwordsplit > /dev/null ; echo $?)
        setopt shwordsplit
      fi

      LAST_TWO=$($NVM_COMMAND | command grep -e '^v' | cut -c2- | cut -d . -f 1,2 | uniq)

      if [ $ZHS_HAS_SHWORDSPLIT_UNSET -eq 1 ] && tnvm_has "unsetopt"; then
        unsetopt shwordsplit
      fi
    ;;
  esac
  local MINOR
  local STABLE
  local UNSTABLE
  local MOD

  ZHS_HAS_SHWORDSPLIT_UNSET=1
  if tnvm_has "setopt"; then
    ZHS_HAS_SHWORDSPLIT_UNSET=$(setopt | command grep shwordsplit > /dev/null ; echo $?)
    setopt shwordsplit
  fi
  for MINOR in $LAST_TWO; do
    MOD=$(expr "$(tnvm_normalize_version "$MINOR")" \/ 1000000 \% 2)
    if [ $MOD -eq 0 ]; then
      STABLE="$MINOR"
    elif [ $MOD -eq 1 ]; then
      UNSTABLE="$MINOR"
    fi
  done
  if [ $ZHS_HAS_SHWORDSPLIT_UNSET -eq 1 ] && tnvm_has "unsetopt"; then
    unsetopt shwordsplit
  fi

  if [ "_$2" = "_stable" ]; then
    echo $STABLE
  elif [ "_$2" = "_unstable" ]; then
    echo $UNSTABLE
  fi
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

tnvm_ensure_default_set() {
  local VERSION
  VERSION="$1"
  if [ -z "$VERSION" ]; then
    echo 'tnvm_ensure_default_set: a version is required' >&2
    return 1
  fi
  if tnvm_alias default >/dev/null 2>&1; then
    # default already set
    return 0
  fi
  local OUTPUT
  OUTPUT="$(tnvm alias default "$VERSION")"
  local EXIT_CODE
  EXIT_CODE="$?"
  echo "Creating default alias: $OUTPUT"
  return $EXIT_CODE
}

tnvm_install_iojs_binary() {
  local PREFIXED_VERSION
  PREFIXED_VERSION="$1"
  local REINSTALL_PACKAGES_FROM
  REINSTALL_PACKAGES_FROM="$2"

  if ! tnvm_is_iojs_version "$PREFIXED_VERSION"; then
    echo 'tnvm_install_iojs_binary requires an iojs-prefixed version.' >&2
    return 10
  fi

  local VERSION
  VERSION="$(tnvm_strip_iojs_prefix "$PREFIXED_VERSION")"
  local VERSION_PATH
  VERSION_PATH="$(tnvm_version_path "$PREFIXED_VERSION")"
  local NVM_OS
  NVM_OS="$(tnvm_get_os)"
  local t
  local url
  local sum

  if [ -n "$NVM_OS" ]; then
    if tnvm_binary_available "$VERSION"; then
      t="$VERSION-$NVM_OS-$(tnvm_get_arch)"
      url="$TNVM_IOJS_ORG_MIRROR/$VERSION/$(tnvm_iojs_prefix)-${t}.tar.gz"
      sum="$(tnvm_download -L -s $TNVM_IOJS_ORG_MIRROR/$VERSION/SHASUMS.txt -o - | command grep $(tnvm_iojs_prefix)-${t}.tar.gz | command awk '{print $1}')"
      local tmpdir
      tmpdir="$TNVM_DIR/bin/iojs-${t}"
      local tmptarball
      tmptarball="$tmpdir/iojs-${t}.tar.gz"
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

tnvm_install_node_binary() {
  local VERSION
  VERSION="$1"
  local REINSTALL_PACKAGES_FROM
  REINSTALL_PACKAGES_FROM="$2"

  if tnvm_is_iojs_version "$PREFIXED_VERSION"; then
    echo 'tnvm_install_node_binary does not allow an iojs-prefixed version.' >&2
    return 10
  fi

  local VERSION_PATH
  VERSION_PATH="$(tnvm_version_path "$VERSION")"
  local NVM_OS
  NVM_OS="$(tnvm_get_os)"
  local t
  local url
  local sum

  if [ -n "$NVM_OS" ]; then
    if tnvm_binary_available "$VERSION"; then
      local NVM_ARCH
      NVM_ARCH="$(tnvm_get_arch)"
      if [ $NVM_ARCH = "armv6l" ] || [ $NVM_ARCH = "armv7l" ]; then
         NVM_ARCH="arm-pi"
      fi
      t="$VERSION-$NVM_OS-$NVM_ARCH"
      url="$TNVM_NODEJS_ORG_MIRROR/$VERSION/node-${t}.tar.gz"
      sum=`tnvm_download -L -s $TNVM_NODEJS_ORG_MIRROR/$VERSION/SHASUMS.txt -o - | command grep node-${t}.tar.gz | command awk '{print $1}'`
      local tmpdir
      tmpdir="$TNVM_DIR/bin/node-${t}"
      local tmptarball
      tmptarball="$tmpdir/node-${t}.tar.gz"
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
        echo >&2 "Binary download failed, trying source."
        command rm -rf "$tmptarball" "$tmpdir"
        return 1
      fi
    fi
  fi
  return 2
}

tnvm_install_node_source() {
  local VERSION
  VERSION="$1"
  local ADDITIONAL_PARAMETERS
  ADDITIONAL_PARAMETERS="$2"

  if [ -n "$ADDITIONAL_PARAMETERS" ]; then
    echo "Additional options while compiling: $ADDITIONAL_PARAMETERS"
  fi

  local VERSION_PATH
  VERSION_PATH="$(tnvm_version_path "$VERSION")"
  local NVM_OS
  NVM_OS="$(tnvm_get_os)"

  local tarball
  tarball=''
  local sum
  sum=''
  local make
  make='make'
  if [ "_$NVM_OS" = "_freebsd" ]; then
    make='gmake'
    MAKE_CXX="CXX=c++"
  fi
  local tmpdir
  tmpdir="$TNVM_DIR/src"
  local tmptarball
  tmptarball="$tmpdir/node-$VERSION.tar.gz"

  if [ "`tnvm_download -L -s -I "$TNVM_NODEJS_ORG_MIRROR/$VERSION/node-$VERSION.tar.gz" -o - 2>&1 | command grep '200 OK'`" != '' ]; then
    tarball="$TNVM_NODEJS_ORG_MIRROR/$VERSION/node-$VERSION.tar.gz"
    sum=`tnvm_download -L -s $TNVM_NODEJS_ORG_MIRROR/$VERSION/SHASUMS.txt -o - | command grep "node-$VERSION.tar.gz" | command awk '{print $1}'`
  elif [ "`tnvm_download -L -s -I "$TNVM_NODEJS_ORG_MIRROR/node-$VERSION.tar.gz" -o - | command grep '200 OK'`" != '' ]; then
    tarball="$TNVM_NODEJS_ORG_MIRROR/node-$VERSION.tar.gz"
  fi

  if (
    [ -n "$tarball" ] && \
    command mkdir -p "$tmpdir" && \
    tnvm_download -L --progress-bar $tarball -o "$tmptarball" && \
    tnvm_checksum "$tmptarball" $sum && \
    command tar -xzf "$tmptarball" -C "$tmpdir" && \
    cd "$tmpdir/node-$VERSION" && \
    ./configure --prefix="$VERSION_PATH" $ADDITIONAL_PARAMETERS && \
    $make $MAKE_CXX && \
    command rm -f "$VERSION_PATH" 2>/dev/null && \
    $make $MAKE_CXX install
    )
  then
    if ! tnvm_has "npm" ; then
      echo "Installing npm..."
      if tnvm_version_greater 0.2.0 "$VERSION"; then
        echo "npm requires node v0.2.3 or higher" >&2
      elif tnvm_version_greater_than_or_equal_to "$VERSION" 0.2.0; then
        if tnvm_version_greater 0.2.3 "$VERSION"; then
          echo "npm requires node v0.2.3 or higher" >&2
        else
          tnvm_download -L https://npmjs.org/install.sh -o - | clean=yes npm_install=0.2.19 sh
        fi
      else
        tnvm_download -L https://npmjs.org/install.sh -o - | clean=yes sh
      fi
    fi
  else
    echo "tnvm: install $VERSION failed!" >&2
    return 1
  fi

  return $?
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
  local ADDITIONAL_PARAMETERS
  local ALIAS

  case $1 in
    "help" )
      echo
      echo "Taobao Node Version Manager"
      echo
      echo "Usage:"
      echo "  tnvm help                              Show this message"
      echo "  tnvm --version                         Print out the latest released version of tnvm"
      echo "  tnvm install <version>            Download and install a <version>"
      echo "  tnvm uninstall <version>               Uninstall a version"
      echo "  tnvm use <version>                     Modify PATH to use <version>. Uses .nvmrc if available"
      echo "  tnvm run <version> [<args>]            Run <version> with <args> as arguments. Uses .nvmrc if available for <version>"
      echo "  tnvm current                           Display currently activated version"
      echo "  tnvm ls                                List installed versions"
      echo "  tnvm ls <version>                      List versions matching a given description"
      echo "  tnvm ls-remote                         List remote versions available for install"
      echo "  tnvm deactivate                        Undo effects of \`nvm\` on current shell"
      echo "  tnvm alias [<pattern>]                 Show all aliases beginning with <pattern>"
      echo "  tnvm alias <name> <version>            Set an alias named <name> pointing to <version>"
      echo "  tnvm unalias <name>                    Deletes the alias named <name>"
      echo "  tnvm unload                            Unload \`nvm\` from shell"
      echo "  tnvm which [<version>]                 Display path to installed node version. Uses .nvmrc if available"
      echo
      echo "Example:"
      echo "  tnvm install v0.10.32                  Install a specific version number"
      echo "  tnvm use 0.10                          Use the latest available 0.10.x release"
      echo "  tnvm run 0.10.32 app.js                Run app.js using node v0.10.32"
      echo "  tnvm exec 0.10.32 node app.js          Run \`node app.js\` with the PATH pointing to node v0.10.32"
      echo "  tnvm alias default 0.10.32             Set default node version on a shell"
      echo
      echo "Note:"
      echo "  to remove, delete, or uninstall tnvm - just remove ~/.tnvm, ~/.npm, and ~/.bower folders"
      echo
    ;;

    "debug" )
      echo >&2 "\$SHELL: $SHELL"
      echo >&2 "\$TNVM_DIR: $(echo $TNVM_DIR | sed "s#$HOME#\$HOME#g")"
      for NVM_DEBUG_COMMAND in 'tnvm current' 'which node' 'which iojs' 'which npm' 'npm config get prefix' 'npm root -g'
      do
        local NVM_DEBUG_OUTPUT="$($NVM_DEBUG_COMMAND | sed "s#$TNVM_DIR#\$TNVM_DIR#g")"
        echo >&2 "$NVM_DEBUG_COMMAND: ${NVM_DEBUG_OUTPUT}"
      done
      return 42
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
      if [ "_$1" = "_-s" ]; then
        nobinary=1
        shift
      fi

      provided_version="$1"

      if [ -z "$provided_version" ]; then
        if [ $version_not_provided -ne 1 ]; then
          tnvm_rc_version
        fi
        provided_version="$TNVM_RC_VERSION"
      else
        shift
      fi

      VERSION="$(tnvm_remote_version "$provided_version")"

      if [ "_$VERSION" = "_N/A" ]; then
        echo "Version '$provided_version' not found - try \`tnvm ls-remote\` to browse available versions." >&2
        return 3
      fi

      ADDITIONAL_PARAMETERS=''
      local PROVIDED_REINSTALL_PACKAGES_FROM
      local REINSTALL_PACKAGES_FROM

      while [ $# -ne 0 ]
      do
        case "$1" in
          --reinstall-packages-from=*)
            PROVIDED_REINSTALL_PACKAGES_FROM="$(echo "$1" | command cut -c 27-)"
            REINSTALL_PACKAGES_FROM="$(tnvm_version "$PROVIDED_REINSTALL_PACKAGES_FROM")"
          ;;
          --copy-packages-from=*)
            PROVIDED_REINSTALL_PACKAGES_FROM="$(echo "$1" | command cut -c 22-)"
            REINSTALL_PACKAGES_FROM="$(tnvm_version "$PROVIDED_REINSTALL_PACKAGES_FROM")"
          ;;
          *)
            ADDITIONAL_PARAMETERS="$ADDITIONAL_PARAMETERS $1"
          ;;
        esac
        shift
      done

      if [ "_$(tnvm_ensure_version_prefix "$PROVIDED_REINSTALL_PACKAGES_FROM")" = "_$VERSION" ]; then
        echo "You can't reinstall global packages from the same version of node you're installing." >&2
        return 4
      elif [ ! -z "$PROVIDED_REINSTALL_PACKAGES_FROM" ] && [ "_$REINSTALL_PACKAGES_FROM" = "_N/A" ]; then
        echo "If --reinstall-packages-from is provided, it must point to an installed version of node." >&2
        return 5
      fi

      local NVM_IOJS
      if tnvm_is_iojs_version "$VERSION"; then
        NVM_IOJS=true
      fi

      local VERSION_PATH
      VERSION_PATH="$(tnvm_version_path "$VERSION")"
      if [ -d "$VERSION_PATH" ]; then
        echo "$VERSION is already installed." >&2
        if tnvm use "$VERSION" && [ ! -z "$REINSTALL_PACKAGES_FROM" ] && [ "_$REINSTALL_PACKAGES_FROM" != "_N/A" ]; then
          tnvm reinstall-packages "$REINSTALL_PACKAGES_FROM"
        fi
        return $?
      fi

      if [ "_$NVM_OS" = "_freebsd" ]; then
        # node.js and io.js do not have a FreeBSD binary
        nobinary=1
      elif [ "_$NVM_OS" = "_sunos" ] && [ "$NVM_IOJS" = true ]; then
        # io.js does not have a SunOS binary
        nobinary=1
      fi
      local NVM_INSTALL_SUCCESS
      # skip binary install if "nobinary" option specified.
      if [ $nobinary -ne 1 ] && tnvm_binary_available "$VERSION"; then
        if [ "$NVM_IOJS" = true ] && tnvm_install_iojs_binary "$VERSION" "$REINSTALL_PACKAGES_FROM"; then
          NVM_INSTALL_SUCCESS=true
        elif [ "$NVM_IOJS" != true ] && tnvm_install_node_binary "$VERSION" "$REINSTALL_PACKAGES_FROM"; then
          NVM_INSTALL_SUCCESS=true
        fi
      fi
      if [ "$NVM_INSTALL_SUCCESS" != true ]; then
        if [ "$NVM_IOJS" = true ]; then
          # tnvm_install_iojs_source "$VERSION" "$ADDITIONAL_PARAMETERS"
          echo "Installing iojs from source is not currently supported" >&2
          return 105
        elif tnvm_install_node_source "$VERSION" "$ADDITIONAL_PARAMETERS"; then
          NVM_INSTALL_SUCCESS=true
        fi
      fi

      if [ "$NVM_INSTALL_SUCCESS" = true ] && tnvm use "$VERSION"; then
        if [ ! -z "$REINSTALL_PACKAGES_FROM" ] \
          && [ "_$REINSTALL_PACKAGES_FROM" != "_N/A" ]; then
          tnvm reinstall-packages "$REINSTALL_PACKAGES_FROM"
        fi
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
      case "_$PATTERN" in
        "_$(tnvm_iojs_prefix)" | "_$(tnvm_iojs_prefix)-" \
        | "_$(tnvm_node_prefix)" | "_$(tnvm_node_prefix)-")
          VERSION="$(tnvm_version "$PATTERN")"
        ;;
        *)
          VERSION="$(tnvm_version "$PATTERN")"
        ;;
      esac
      if [ "_$VERSION" = "_$(tnvm_ls_current)" ]; then
        if tnvm_is_iojs_version "$VERSION"; then
          echo "tnvm: Cannot uninstall currently-active io.js version, $VERSION (inferred from $PATTERN)." >&2
        else
          echo "tnvm: Cannot uninstall currently-active node version, $VERSION (inferred from $PATTERN)." >&2
        fi
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
      if tnvm_is_iojs_version "$VERSION"; then
        NVM_PREFIX="$(tnvm_iojs_prefix)"
        NVM_SUCCESS_MSG="Uninstalled io.js $(tnvm_strip_iojs_prefix $VERSION)"
      else
        NVM_PREFIX="$(tnvm_node_prefix)"
        NVM_SUCCESS_MSG="Uninstalled node $VERSION"
      fi
      # Delete all files related to target version.
      command rm -rf "$TNVM_DIR/src/$NVM_PREFIX-$VERSION" \
             "$TNVM_DIR/src/$NVM_PREFIX-$VERSION.tar.gz" \
             "$TNVM_DIR/bin/$NVM_PREFIX-${t}" \
             "$TNVM_DIR/bin/$NVM_PREFIX-${t}.tar.gz" \
             "$VERSION_PATH" 2>/dev/null
      echo "$NVM_SUCCESS_MSG and reopen your terminal"

      # rm any aliases that point to uninstalled version.
      for ALIAS in `command grep -l $VERSION "$(tnvm_alias_path)/*" 2>/dev/null`
      do
        tnvm unalias "$(command basename "$ALIAS")"
      done
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
        tnvm_rc_version
        if [ -n "$TNVM_RC_VERSION" ]; then
          PROVIDED_VERSION="$TNVM_RC_VERSION"
          VERSION="$(tnvm_version "$PROVIDED_VERSION")"
        fi
      else
        local NVM_IOJS_PREFIX
        NVM_IOJS_PREFIX="$(tnvm_iojs_prefix)"
        local NVM_NODE_PREFIX
        NVM_NODE_PREFIX="$(tnvm_node_prefix)"
        PROVIDED_VERSION="$2"
        case "_$PROVIDED_VERSION" in
          "_$NVM_IOJS_PREFIX" | "_io.js")
            VERSION="$(tnvm_version $NVM_IOJS_PREFIX)"
          ;;
          "_system")
            VERSION="system"
          ;;
          *)
            VERSION="$(tnvm_version "$PROVIDED_VERSION")"
          ;;
        esac
      fi

      if [ -z "$VERSION" ]; then
        >&2 tnvm help
        return 127
      fi

      if [ "_$VERSION" = '_system' ]; then
        if tnvm_has_system_node && nvm deactivate >/dev/null 2>&1; then
          echo "Now using system version of node: $(node -v 2>/dev/null)$(tnvm_print_npm_version)"
          return
        elif tnvm_has_system_iojs && nvm deactivate >/dev/null 2>&1; then
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
      if [ "$NVM_SYMLINK_CURRENT" = true ]; then
        command rm -f "$TNVM_DIR/current" && ln -s "$NVM_VERSION_DIR" "$TNVM_DIR/current"
      fi
      if tnvm_is_iojs_version "$VERSION"; then
        echo "Now using io.js $(tnvm_strip_iojs_prefix "$VERSION")$(tnvm_print_npm_version)"
      else
        echo "Now using node $VERSION$(tnvm_print_npm_version)"
      fi
    ;;
    "run" )
      local provided_version
      local has_checked_nvmrc
      has_checked_nvmrc=0
      # run given version of node
      shift
      if [ $# -lt 1 ]; then
        tnvm_rc_version && has_checked_nvmrc=1
        if [ -n "$TNVM_RC_VERSION" ]; then
          VERSION="$(tnvm_version "$TNVM_RC_VERSION")"
        else
          VERSION='N/A'
        fi
        if [ $VERSION = "N/A" ]; then
          >&2 tnvm help
          return 127
        fi
      fi

      provided_version=$1
      if [ -n "$provided_version" ]; then
        VERSION="$(tnvm_version "$provided_version")"
        if [ "_$VERSION" = "_N/A" ] && ! tnvm_is_valid_version "$provided_version"; then
          provided_version=''
          if [ $has_checked_nvmrc -ne 1 ]; then
            tnvm_rc_version && has_checked_nvmrc=1
          fi
          VERSION="$(tnvm_version "$TNVM_RC_VERSION")"
        else
          shift
        fi
      fi

      local NVM_IOJS
      if tnvm_is_iojs_version "$VERSION"; then
        NVM_IOJS=true
      fi

      local ARGS
      ARGS="$@"
      local OUTPUT
      local EXIT_CODE

      local ZHS_HAS_SHWORDSPLIT_UNSET
      ZHS_HAS_SHWORDSPLIT_UNSET=1
      if tnvm_has "setopt"; then
        ZHS_HAS_SHWORDSPLIT_UNSET=$(setopt | command grep shwordsplit > /dev/null ; echo $?)
        setopt shwordsplit
      fi
      if [ "_$VERSION" = "_N/A" ]; then
        echo "$(tnvm_ensure_version_prefix "$provided_version") is not installed yet" >&2
        EXIT_CODE=1
      elif [ -z "$ARGS" ]; then
        if [ "$NVM_IOJS" = true ]; then
          tnvm exec "$VERSION" iojs
        else
          tnvm exec "$VERSION" node
        fi
        EXIT_CODE="$?"
      elif [ "$NVM_IOJS" = true ]; then
        echo "Running io.js $(tnvm_strip_iojs_prefix "$VERSION")"
        OUTPUT="$(tnvm use "$VERSION" >/dev/null && iojs $ARGS)"
        EXIT_CODE="$?"
      else
        echo "Running node $VERSION"
        OUTPUT="$(tnvm use "$VERSION" >/dev/null && node $ARGS)"
        EXIT_CODE="$?"
      fi
      if [ $ZHS_HAS_SHWORDSPLIT_UNSET -eq 1 ] && tnvm_has "unsetopt"; then
        unsetopt shwordsplit
      fi
      if [ -n "$OUTPUT" ]; then
        echo "$OUTPUT"
      fi
      return $EXIT_CODE
    ;;
    "exec" )
      shift

      local provided_version
      provided_version="$1"
      if [ -n "$provided_version" ]; then
        VERSION="$(tnvm_version "$provided_version")"
        if [ "_$VERSION" = "_N/A" ]; then
          tnvm_rc_version
          provided_version="$TNVM_RC_VERSION"
          VERSION="$(tnvm_version "$provided_version")"
        else
          shift
        fi
      fi

      tnvm_ensure_version_installed "$provided_version"
      EXIT_CODE=$?
      if [ "$EXIT_CODE" != "0" ]; then
        return $EXIT_CODE
      fi

      echo "Running node $VERSION"
      NODE_VERSION="$VERSION" $TNVM_DIR/nvm-exec "$@"
    ;;
    "ls" | "list" )
      local NVM_LS_OUTPUT
      local NVM_LS_EXIT_CODE
      NVM_LS_OUTPUT=$(tnvm_ls "$2")
      NVM_LS_EXIT_CODE=$?
      tnvm_print_versions "$NVM_LS_OUTPUT"
      if [ $# -eq 1 ]; then
        tnvm alias
      fi
      return $NVM_LS_EXIT_CODE
    ;;
    "ls-remote" | "list-remote" )
      local PATTERN
      PATTERN="$2"
      local NVM_FLAVOR
      case "_$PATTERN" in
        "_$(tnvm_iojs_prefix)" | "_$(tnvm_node_prefix)" )
          NVM_FLAVOR="$PATTERN"
          PATTERN="$3"
        ;;
      esac

      local NVM_LS_REMOTE_EXIT_CODE
      NVM_LS_REMOTE_EXIT_CODE=0
      local NVM_LS_REMOTE_OUTPUT
      NVM_LS_REMOTE_OUTPUT=''
      if [ "_$NVM_FLAVOR" != "_$(tnvm_iojs_prefix)" ]; then
        NVM_LS_REMOTE_OUTPUT=$(tnvm_ls_remote "$PATTERN")
        NVM_LS_REMOTE_EXIT_CODE=$?
      fi

      local NVM_LS_REMOTE_IOJS_EXIT_CODE
      NVM_LS_REMOTE_IOJS_EXIT_CODE=0
      local NVM_LS_REMOTE_IOJS_OUTPUT
      NVM_LS_REMOTE_IOJS_OUTPUT=''
      if [ "_$NVM_FLAVOR" != "_$(tnvm_node_prefix)" ]; then
        NVM_LS_REMOTE_IOJS_OUTPUT=$(tnvm_ls_remote_iojs "$PATTERN")
        NVM_LS_REMOTE_IOJS_EXIT_CODE=$?
      fi

      local NVM_OUTPUT
      NVM_OUTPUT="$(echo "$NVM_LS_REMOTE_OUTPUT
$NVM_LS_REMOTE_IOJS_OUTPUT" | command grep -v "N/A" | sed '/^$/d')"
      if [ -n "$NVM_OUTPUT" ]; then
        tnvm_print_versions "$NVM_OUTPUT"
        return $NVM_LS_REMOTE_EXIT_CODE || $NVM_LS_REMOTE_IOJS_EXIT_CODE
      else
        tnvm_print_versions "N/A"
        return 3
      fi
    ;;
    "current" )
      tnvm_version current
    ;;
    "which" )
      local provided_version
      provided_version="$2"
      if [ $# -eq 1 ]; then
        tnvm_rc_version
        if [ -n "$TNVM_RC_VERSION" ]; then
          provided_version="$TNVM_RC_VERSION"
          VERSION=$(tnvm_version "$TNVM_RC_VERSION")
        fi
      elif [ "_$2" != '_system' ]; then
        VERSION="$(tnvm_version "$provided_version")"
      else
        VERSION="$2"
      fi
      if [ -z "$VERSION" ]; then
        >&2 tnvm help
        return 127
      fi

      if [ "_$VERSION" = '_system' ]; then
        if tnvm_has_system_iojs >/dev/null 2>&1 || tnvm_has_system_node >/dev/null 2>&1; then
          local NVM_BIN
          NVM_BIN="$(tnvm use system >/dev/null 2>&1 && command which node)"
          if [ -n "$NVM_BIN" ]; then
            echo "$NVM_BIN"
            return
          else
            return 1
          fi
        else
          echo "System version of node not found." >&2
          return 127
        fi
      elif [ "_$VERSION" = "_∞" ]; then
        echo "The alias \"$2\" leads to an infinite loop. Aborting." >&2
        return 8
      fi

      tnvm_ensure_version_installed "$provided_version"
      EXIT_CODE=$?
      if [ "$EXIT_CODE" != "0" ]; then
        return $EXIT_CODE
      fi
      local NVM_VERSION_DIR
      NVM_VERSION_DIR="$(tnvm_version_path "$VERSION")"
      echo "$NVM_VERSION_DIR/bin/node"
    ;;
    "alias" )
      local NVM_ALIAS_DIR
      NVM_ALIAS_DIR="$(tnvm_alias_path)"
      command mkdir -p "$NVM_ALIAS_DIR"
      if [ $# -le 2 ]; then
        local DEST
        for ALIAS_PATH in "$NVM_ALIAS_DIR"/"$2"*; do
          ALIAS="$(command basename "$ALIAS_PATH")"
          DEST="$(tnvm_alias "$ALIAS" 2> /dev/null)"
          if [ -n "$DEST" ]; then
            VERSION="$(tnvm_version "$DEST")"
            if [ "_$DEST" = "_$VERSION" ]; then
              echo "$ALIAS -> $DEST"
            else
              echo "$ALIAS -> $DEST (-> $VERSION)"
            fi
          fi
        done

        for ALIAS in "$(tnvm_node_prefix)" "stable" "unstable" "$(tnvm_iojs_prefix)"; do
          if [ ! -f "$NVM_ALIAS_DIR/$ALIAS" ]; then
            if [ $# -lt 2 ] || [ "~$ALIAS" = "~$2" ]; then
              DEST="$(tnvm_print_implicit_alias local "$ALIAS")"
              if [ "_$DEST" != "_" ]; then
                VERSION="$(tnvm_version "$DEST")"
                echo "$ALIAS -> $DEST (-> $VERSION) (default)"
              fi
            fi
          fi
        done
        return
      fi
      if [ -z "$3" ]; then
        command rm -f "$NVM_ALIAS_DIR/$2"
        echo "$2 -> *poof*"
        return
      fi
      VERSION="$(tnvm_version "$3")"
      if [ $? -ne 0 ]; then
        echo "! WARNING: Version '$3' does not exist." >&2
      fi
      echo "$3" | tee "$NVM_ALIAS_DIR/$2" >/dev/null
      if [ ! "_$3" = "_$VERSION" ]; then
        echo "$2 -> $3 (-> $VERSION)"
      else
        echo "$2 -> $3"
      fi
    ;;
    "unalias" )
      local NVM_ALIAS_DIR
      NVM_ALIAS_DIR="$(tnvm_alias_path)"
      command mkdir -p "$NVM_ALIAS_DIR"
      if [ $# -ne 2 ]; then
        >&2 tnvm help
        return 127
      fi
      [ ! -f "$NVM_ALIAS_DIR/$2" ] && echo "Alias $2 doesn't exist!" >&2 && return
      command rm -f "$NVM_ALIAS_DIR/$2"
      echo "Deleted alias $2"
    ;;
    
    "clear-cache" )
      command rm -f $TNVM_DIR/v* "$(tnvm_version_dir)" 2>/dev/null
      echo "Cache cleared."
    ;;
    "version" )
      tnvm_version $2
    ;;
    "--version" )
      echo "0.25.4"
    ;;
    "unload" )
      unset -f tnvm tnvm_print_versions tnvm_checksum \
        tnvm_iojs_prefix tnvm_node_prefix \
        tnvm_add_iojs_prefix tnvm_strip_iojs_prefix \
        tnvm_is_iojs_version \
        tnvm_ls_remote tnvm_ls tnvm_remote_version tnvm_remote_versions \
        tnvm_version tnvm_rc_version \
        tnvm_version_greater tnvm_version_greater_than_or_equal_to \
        tnvm_supports_source_options > /dev/null 2>&1
      unset RC_VERSION TNVM_NODEJS_ORG_MIRROR TNVM_DIR NVM_CD_FLAGS > /dev/null 2>&1
    ;;
    * )
      >&2 tnvm help
      return 127
    ;;
  esac
}

tnvm_supports_source_options() {
  [ "_$(echo 'echo $1' | . /dev/stdin yes 2> /dev/null)" = "_yes" ]
}

VERSION="$(tnvm_alias default 2>/dev/null || echo)"
if tnvm_supports_source_options && [ "_$1" = "_--install" ]; then
  if [ -n "$VERSION" ]; then
    tnvm install "$VERSION" >/dev/null
  elif tnvm_rc_version >/dev/null 2>&1; then
    tnvm install >/dev/null
  fi
elif [ -n "$VERSION" ]; then
  tnvm use "$VERSION" >/dev/null
elif tnvm_rc_version >/dev/null 2>&1; then
  tnvm use >/dev/null
fi

} # this ensures the entire script is downloaded #

tnvm ls
