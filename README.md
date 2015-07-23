# tnvm
Taobao Node Version Manager

## Installation
```shell
wget https://raw.githubusercontent.com/yjhjstz/tnvm/master/install.sh　| chmod a+x install.sh | bash install.sh
```

## Usage
Usage:
  * tnvm help                              Show this message
  * tnvm --version                         Print out the latest released version of tnvm
  * tnvm install <version>                 Download and install a <version>
  * tnvm uninstall <version>               Uninstall a version
  * tnvm use <version>                     Modify PATH to use <version>. Uses .tnvmrc if available
  * tnvm run <version> [<args>]            Run <version> with <args> as arguments. Uses .nvmrc if available for <version>
  * tnvm current                           Display currently activated version
  * tnvm ls                                List installed versions
  * tnvm ls <version>                      List versions matching a given description
  * tnvm ls-remote                         List remote versions available for install
  * tnvm deactivate                        Undo effects of `tnvm` on current shell
  * tnvm alias [<pattern>]                 Show all aliases beginning with <pattern>
  * tnvm alias <name> <version>            Set an alias named <name> pointing to <version>
  * tnvm unalias <name>                    Deletes the alias named <name>
  * tnvm unload                            Unload `tnvm` from shell
  * tnvm which [<version>]                 Display path to installed node version. Uses .tnvmrc if available

Example:
  * tnvm install v0.10.32                  Install a specific version number
  * tnvm use 0.10                          Use the latest available 0.10.x release
  * tnvm alias default 0.10.32             Set default node version on a shell

Note:
  * to remove, delete, or uninstall tnvm - just remove ~/.tnvm, ~/.npm, and ~/.bower folders


## License

nvm is released under the MIT license.
