# tnvm
Taobao Node Version Manager


## Installation
```shell
wget -O- https://raw.githubusercontent.com/aliyun-node/tnvm/master/install.sh | bash
```
PS: 内网环境或者代理环境可在执行上述命令前增加执行, 使用wget获取文件
```
export METHOD=script
```
手动source rc文件或重新打开sh,即可启动。

如果遇到 ssl 证书问题， 尝试`wget`加上选项`--no-check-certificate`



## Usage
Support `alinode`, `node`, `iojs`, `node-profiler` version manager

`tnvm lookup` 查看 `alinode` 基于 `node` 的版本, 便于替换相应版本。

Example install alinode:
 * tnvm ls-remote alinode
 * tnvm lookup
 * tnvm install alinode-v1.0.1
 * tnvm use alinode-v1.0.1

Example install node:
 * tnvm install node-v4.2.1
 * tnvm use node-v4.2.1

Example install node-profiler:
 * tnvm install profiler-v0.12.6
 * tnvm use profiler-v0.12.6

More:
 * refer to `tnvm help`

Note:
  * to remove, delete, or uninstall tnvm - just remove ~/.tnvm folders


## License

tnvm is released under the MIT license.
