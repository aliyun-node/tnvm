# tnvm
Taobao Node Version Manager


## Installation
```shell
wget -qO- https://raw.githubusercontent.com/ali-sdk/tnvm/master/install.sh --no-check-certificate | bash -i 
```
PS: 内网环境可在执行上述命令前增加执行, 内部使用wget获取文件
```
export METHOD=script
```

## Usage
Support `alinode`, `node`, `iojs`, `node-profiler` version manager

Example:
 * tnvm ls alinode
 * tnvm ls-remote alinode
 * tnvm install alinode-v0.12.6
 * tnvm install node-v0.12.6
 * tnvm use alinode-v0.12.6

More:
 * refer to `tnvm help`

Note:
  * to remove, delete, or uninstall tnvm - just remove ~/.tnvm folders


## License

tnvm is released under the MIT license.
