#!/bin/bash

set -e

{ # this ensures the entire script is downloaded #

tnvm_has() {
  type "$1" > /dev/null 2>&1
}

if [ -z "$TNVM_DIR" ]; then
  TNVM_DIR="$HOME/.tnvm"
fi

#
# Outputs the location to NVM depending on:
# * The availability of $NVM_SOURCE
# * The method used ("script" or "git" in the script, defaults to "git")
#
tnvm_source() {
  local NVM_METHOD
  NVM_METHOD="$1"
  local NVM_SOURCE_URL
  NVM_SOURCE_URL="$NVM_SOURCE"
  if [ -z "$NVM_SOURCE_URL" ]; then
    if [ "_$NVM_METHOD" = "_script" ]; then
      NVM_SOURCE_URL="https://raw.githubusercontent.com/ali-sdk/tnvm/master/tnvm.sh"
    elif [ "_$NVM_METHOD" = "_git" ] || [ -z "$NVM_METHOD" ]; then
      NVM_SOURCE_URL="https://github.com/ali-sdk/tnvm.git"
    else
      echo >&2 "Unexpected value \"$NVM_METHOD\" for \$NVM_METHOD"
      return 1
    fi
  fi
  echo "$NVM_SOURCE_URL"
}

tnvm_download() {
  if tnvm_has "wget"; then
    # Emulate curl with wget
    ARGS=$(echo "$*" | command sed -e 's/--progress-bar /--progress=bar /' \
                           -e 's/-L //' \
                           -e 's/-I /--server-response /' \
                           -e 's/-s /-q /' \
                           -e 's/-o /-O /' \
                           -e 's/-C - /-c /')
    wget $ARGS
  elif tnvm_has "curl"; then
    curl -q $*
  fi
}

install_tnvm_from_git() {
  if [ -d "$TNVM_DIR/.git" ]; then
    echo "=> tnvm is already installed in $TNVM_DIR, trying to update using git"
    printf "\r=> "
    cd "$TNVM_DIR" && (command git pull 2> /dev/null || {
      echo >&2 "Failed to update tnvm, run 'git pull' in $TNVM_DIR yourself." && exit 1
    })
  else
    # Cloning to $TNVM_DIR
    echo "=> Downloading tnvm from git to '$TNVM_DIR'"
    printf "\r=> "
    mkdir -p "$TNVM_DIR"
    command git clone "$(tnvm_source git)" "$TNVM_DIR"
  fi
  cd "$TNVM_DIR" && command git checkout --quiet master
  return
}

install_tnvm_as_script() {
  local NVM_SOURCE_LOCAL
  NVM_SOURCE_LOCAL=$(tnvm_source script)

  # Downloading to $TNVM_DIR
  mkdir -p "$TNVM_DIR"

  if [ -d "$TNVM_DIR/tnvm.sh" ]; then
    echo "=> tnvm is already installed in $TNVM_DIR, trying to update the script"
  else
    echo "=> Downloading tnvm as script to '$TNVM_DIR'"
  fi
  tnvm_download -s "$NVM_SOURCE_LOCAL" -o "$TNVM_DIR/tnvm.sh" || {
    echo >&2 "Failed to download '$NVM_SOURCE_LOCAL'"
    return 1
  }
}

#
# Detect profile file if not specified as environment variable
# (eg: PROFILE=~/.myprofile)
# The echo'ed path is guaranteed to be an existing file
# Otherwise, an empty string is returned
#
tnvm_detect_profile() {
  if [ -f "$PROFILE" ]; then
    echo "$PROFILE"
  elif [ -f "$HOME/.bashrc" ]; then
    echo "$HOME/.bashrc"
  elif [ -f "$HOME/.bash_profile" ]; then
    echo "$HOME/.bash_profile"
  elif [ -f "$HOME/.zshrc" ]; then
    echo "$HOME/.zshrc"
  elif [ -f "$HOME/.profile" ]; then
    echo "$HOME/.profile"
  fi
}

#
# Check whether the user has any globally-installed npm modules in their system
# Node, and warn them if so.
#
tnvm_check_global_modules() {
  command -v npm >/dev/null 2>&1 || return 0

  local NPM_VERSION
  NPM_VERSION="$(npm --version)"
  NPM_VERSION="${NPM_VERSION:--1}"
  [ "${NPM_VERSION%%[!-0-9]*}" -gt 0 ] || return 0

  local NPM_GLOBAL_MODULES
  NPM_GLOBAL_MODULES="$(
    npm list -g --depth=0 |
    sed '/ npm@/d' |
    sed '/ (empty)$/d'
  )"

  local MODULE_COUNT
  MODULE_COUNT="$(
    printf %s\\n "$NPM_GLOBAL_MODULES" |
    sed -ne '1!p' |                             # Remove the first line
    wc -l | tr -d ' '                           # Count entries
  )"

  if [ $MODULE_COUNT -ne 0 ]; then
    cat <<-'END_MESSAGE'
	=> You currently have modules installed globally with `npm`. These will no
	=> longer be linked to the active version of Node when you install a new node
	=> with `nvm`; and they may (depending on how you construct your `$PATH`)
	=> override the binaries of modules installed with `nvm`:

	END_MESSAGE
    printf %s\\n "$NPM_GLOBAL_MODULES"
    cat <<-'END_MESSAGE'

	=> If you wish to uninstall them at a later point (or re-install them under your
	=> `nvm` Nodes), you can remove them from the system Node as follows:

	     $ tnvm use system
	     $ npm uninstall -g a_module

	END_MESSAGE
  fi
}

tnvm_do_install() {
  if [ -z "$METHOD" ]; then
    # Autodetect install method
    if tnvm_has "git"; then
      install_tnvm_from_git
    elif tnvm_has "tnvm_download"; then
      install_tnvm_as_script
    else
      echo >&2 "You need git, curl, or wget to install tnvm"
      exit 1
    fi
  elif [ "~$METHOD" = "~git" ]; then
    if ! tnvm_has "git"; then
      echo >&2 "You need git to install tnvm"
      exit 1
    fi
    install_tnvm_from_git
  elif [ "~$METHOD" = "~script" ]; then
    if ! tnvm_has "tnvm_download"; then
      echo >&2 "You need curl or wget to install tnvm"
      exit 1
    fi
    install_tnvm_as_script
  fi

  echo

  local NVM_PROFILE
  NVM_PROFILE=$(tnvm_detect_profile)

  SOURCE_STR="\nexport TNVM_DIR=\"$TNVM_DIR\"\n[ -s \"\$TNVM_DIR/tnvm.sh\" ] && . \"\$TNVM_DIR/tnvm.sh\"  # This loads nvm"

  if [ -z "$NVM_PROFILE" ] ; then
    echo "=> Profile not found. Tried $NVM_PROFILE (as defined in \$PROFILE), ~/.bashrc, ~/.bash_profile, ~/.zshrc, and ~/.profile."
    echo "=> Create one of them and run this script again"
    echo "=> Create it (touch $NVM_PROFILE) and run this script again"
    echo "   OR"
    echo "=> Append the following lines to the correct file yourself:"
    printf "$SOURCE_STR"
    echo
  else
    if ! grep -qc '$TNVM_DIR' "$NVM_PROFILE"; then
      echo "=> Appending source string to $NVM_PROFILE"
      printf "$SOURCE_STR\n" >> "$NVM_PROFILE"
    else
      echo "=> Source string already in $NVM_PROFILE"
    fi
    source "$NVM_PROFILE"
    exec bash
  fi
  #tnvm_check_global_modules
  echo "=> Try source $NVM_PROFILE to start using tnvm"

  tnvm_reset
}

#
# Unsets the various functions defined
# during the execution of the install script
#
tnvm_reset() {
  unset -f tnvm_reset tnvm_has \
    tnvm_source tnvm_download install_tnvm_as_script install_tnvm_from_git \
    tnvm_detect_profile tnvm_check_global_modules tnvm_do_install
}

tnvm_do_install

} # this ensures the entire script is downloaded #
