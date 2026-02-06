# gongfeng-hello-world

gongfeng example Hello World CLI

基于 oclif 的工蜂 cli 模板项目

<!-- toc -->
* [gongfeng-hello-world](#gongfeng-hello-world)
* [Usage](#usage)
* [Commands](#commands)
<!-- tocstop -->

# Usage

<!-- usage -->
```sh-session
$ npm install -g @tencent/gongfeng-cli-plugin-cr
$ cr COMMAND
running command...
$ cr (--version)
@tencent/gongfeng-cli-plugin-cr/0.21.0-beta.0 darwin-x64 node-v18.16.0
$ cr --help [COMMAND]
USAGE
  $ cr COMMAND
...
```
<!-- usagestop -->

# Commands

<!-- commands -->
* [`cr cr <command> [flags]`](#cr-cr-command-flags)
* [`cr cr close [iid] [flags]`](#cr-cr-close-iid-flags)
* [`cr cr create [path] [flags]`](#cr-cr-create-path-flags)
* [`cr cr edit <iid> [flags]`](#cr-cr-edit-iid-flags)
* [`cr cr list [flags]`](#cr-cr-list-flags)
* [`cr cr reopen [iid] [flags]`](#cr-cr-reopen-iid-flags)
* [`cr cr update IID`](#cr-cr-update-iid)
* [`cr help [COMMANDS]`](#cr-help-commands)
* [`cr plugins`](#cr-plugins)
* [`cr plugins:install PLUGIN...`](#cr-pluginsinstall-plugin)
* [`cr plugins:inspect PLUGIN...`](#cr-pluginsinspect-plugin)
* [`cr plugins:install PLUGIN...`](#cr-pluginsinstall-plugin-1)
* [`cr plugins:link PLUGIN`](#cr-pluginslink-plugin)
* [`cr plugins:uninstall PLUGIN...`](#cr-pluginsuninstall-plugin)
* [`cr plugins:uninstall PLUGIN...`](#cr-pluginsuninstall-plugin-1)
* [`cr plugins:uninstall PLUGIN...`](#cr-pluginsuninstall-plugin-2)
* [`cr plugins update`](#cr-plugins-update)

## `cr cr <command> [flags]`

工蜂代码评审管理

```
USAGE
  $ cr cr <command> [flags]

EXAMPLES
  gf cr list

  gf cr create

  gf cr close 1

  gf cr reopen 13
```

## `cr cr close [iid] [flags]`

关闭一个代码评审

```
USAGE
  $ cr cr close [iid] [flags]

ARGUMENTS
  IID  代码评审 iid

FLAGS
  -c, --comment=<value>  关闭的同时发表一条评论

DESCRIPTION
  关闭一个代码评审

  通过指定 iid 关闭一个代码评审

EXAMPLES
  gf cr close 123
```

## `cr cr create [path] [flags]`

创建代码评审(目前只支持 svn 代码在本地模式)

```
USAGE
  $ cr cr create [path] [flags]

ARGUMENTS
  PATH  svn 项目路径

SVN 代码评审参数 FLAGS
  -a, --author=<value>    指定代码评审作者
  -c, --cc=<value>        抄送人, 使用英文逗号(,)分割
  -e, --encoding=<value>  指定变更编码, 如中文：GB18030
  -f, --files=<value>...  指定需评审文件
  -s, --skips=<value>...  指定需跳过评审的文件
  --only-filename         只发起文件名评审
  --tapd=<value>          关联 TAPD 需求单

公共参数 FLAGS
  -d, --description=<value>  代码请求描述
  -q, --quick                快速发起代码评审，所有字段使用默认值
  -r, --reviewer=<value>     通过用户名指定评审人，使用英文逗号(,)分割
  -t, --title=<value>        代码评审标题

DESCRIPTION
  创建代码评审(目前只支持 svn 代码在本地模式)

  可以指定 svn 项目路径或者不指定路径(即命令当前所在路径)创建代码在本地的代码评审

EXAMPLES
  gf cr create /users/project/test/trunk

  gf cr create
```

## `cr cr edit <iid> [flags]`

编辑代码评审

```
USAGE
  $ cr cr edit <iid> [flags]

ARGUMENTS
  IID  代码评审 iid

SVN 代码评审参数 FLAGS
  -c, --cc=<value>  添加抄送人，可以添加多个抄送人，使用英文逗号(,)分割

公共参数 FLAGS
  -d, --description=<value>   设置新的描述
  -t, --title=<value>         设置新的标题
  -z, --add-reviewer=<value>  添加评审人，可以添加多个评审人，使用英文逗号(,)分割

EXAMPLES
  gf cr edit 123 --title "edit code review title" --description "edit code review description"
```

## `cr cr list [flags]`

显示仓库下的代码评审

```
USAGE
  $ cr cr list [flags]

公共参数 FLAGS
  -A, --author=<value>    按作者过滤
  -L, --limit=<value>     [default: 20] 最多显示的代码评审数量
  -l, --label=<value>     按标签过滤，同时筛选多个时使用英文逗号(,)分割
  -r, --reviewer=<value>  按评审人过滤
  -s, --state=<value>     [default: approving] 按代码评审状态过滤，可选值为“approving|change_required|approved|closed”，
                          同时筛选多个时使用英文逗号(,)分割
  -w, --web               打开浏览器查看代码评审列表
  --columns=<value>       仅显示指定列（多个值之间用,分隔）
  --csv                   以csv格式输出（“--output=csv” 的别名）
  --extended              显示更多的列
  --filter=<value>        对指定列进行过滤，例如: --filter="标题=wip"
  --no-header             隐藏列表的header
  --no-truncate           不截断输出
  --output=<value>        以其他格式输出，可选值为“csv|json|yaml”
  --sort=<value>          通过指定字段名进行排序（降序在字段名前加上“-”）

EXAMPLES
  gf cr list

  gf cr list --author zhangsan
```

## `cr cr reopen [iid] [flags]`

重新打开一个代码评审

```
USAGE
  $ cr cr reopen [iid] [flags]

ARGUMENTS
  IID  代码评审 iid

FLAGS
  -c, --comment=<value>  关闭的同时发表一条评论

DESCRIPTION
  重新打开一个代码评审

  通过指定 iid 重新打开一个代码评审

EXAMPLES
  gf cr reopen 123
```

## `cr cr update IID`

上传修订集(目前只支持 svn 代码在本地模式)

```
USAGE
  $ cr cr update IID [-d <value>] [-a <value>] [--only-filename] [-f <value>] [-s <value>] [-e <value>]

ARGUMENTS
  IID  svn 代码评审 iid

SVN 代码评审参数 FLAGS
  -a, --author=<value>    指定修订集作者，会展示在评论中：xxx上传了修订集
  -e, --encoding=<value>  指定变更编码, 如简体中文：GB18030
  -f, --files=<value>...  指定需评审文件
  -s, --skips=<value>...  指定需跳过评审的文件
  --only-filename         只发起文件名评审

公共参数 FLAGS
  -d, --description=<value>  修订集描述

DESCRIPTION
  上传修订集(目前只支持 svn 代码在本地模式)

  指定代码评审 iid 上传本地变更为代码评审修订集
```

## `cr help [COMMANDS]`

Display help for cr.

```
USAGE
  $ cr help [COMMANDS] [-n]

ARGUMENTS
  COMMANDS  Command to show help for.

FLAGS
  -n, --nested-commands  Include all nested commands in the output.

DESCRIPTION
  Display help for cr.
```

_See code: [@oclif/plugin-help](https://github.com/oclif/plugin-help/blob/v5.2.9/src/commands/help.ts)_

## `cr plugins`

List installed plugins.

```
USAGE
  $ cr plugins [--core]

FLAGS
  --core  Show core plugins.

DESCRIPTION
  List installed plugins.

EXAMPLES
  $ cr plugins
```

_See code: [@oclif/plugin-plugins](https://github.com/oclif/plugin-plugins/blob/v2.4.7/src/commands/plugins/index.ts)_

## `cr plugins:install PLUGIN...`

Installs a plugin into the CLI.

```
USAGE
  $ cr plugins:install PLUGIN...

ARGUMENTS
  PLUGIN  Plugin to install.

FLAGS
  -f, --force    Run yarn install with force flag.
  -h, --help     Show CLI help.
  -v, --verbose

DESCRIPTION
  Installs a plugin into the CLI.
  Can be installed from npm or a git url.

  Installation of a user-installed plugin will override a core plugin.

  e.g. If you have a core plugin that has a 'hello' command, installing a user-installed plugin with a 'hello' command
  will override the core plugin implementation. This is useful if a user needs to update core plugin functionality in
  the CLI without the need to patch and update the whole CLI.


ALIASES
  $ cr plugins add

EXAMPLES
  $ cr plugins:install myplugin 

  $ cr plugins:install https://github.com/someuser/someplugin

  $ cr plugins:install someuser/someplugin
```

## `cr plugins:inspect PLUGIN...`

Displays installation properties of a plugin.

```
USAGE
  $ cr plugins:inspect PLUGIN...

ARGUMENTS
  PLUGIN  [default: .] Plugin to inspect.

FLAGS
  -h, --help     Show CLI help.
  -v, --verbose

GLOBAL FLAGS
  --json  Format output as json.

DESCRIPTION
  Displays installation properties of a plugin.

EXAMPLES
  $ cr plugins:inspect myplugin
```

## `cr plugins:install PLUGIN...`

Installs a plugin into the CLI.

```
USAGE
  $ cr plugins:install PLUGIN...

ARGUMENTS
  PLUGIN  Plugin to install.

FLAGS
  -f, --force    Run yarn install with force flag.
  -h, --help     Show CLI help.
  -v, --verbose

DESCRIPTION
  Installs a plugin into the CLI.
  Can be installed from npm or a git url.

  Installation of a user-installed plugin will override a core plugin.

  e.g. If you have a core plugin that has a 'hello' command, installing a user-installed plugin with a 'hello' command
  will override the core plugin implementation. This is useful if a user needs to update core plugin functionality in
  the CLI without the need to patch and update the whole CLI.


ALIASES
  $ cr plugins add

EXAMPLES
  $ cr plugins:install myplugin 

  $ cr plugins:install https://github.com/someuser/someplugin

  $ cr plugins:install someuser/someplugin
```

## `cr plugins:link PLUGIN`

Links a plugin into the CLI for development.

```
USAGE
  $ cr plugins:link PLUGIN

ARGUMENTS
  PATH  [default: .] path to plugin

FLAGS
  -h, --help     Show CLI help.
  -v, --verbose

DESCRIPTION
  Links a plugin into the CLI for development.
  Installation of a linked plugin will override a user-installed or core plugin.

  e.g. If you have a user-installed or core plugin that has a 'hello' command, installing a linked plugin with a 'hello'
  command will override the user-installed or core plugin implementation. This is useful for development work.


EXAMPLES
  $ cr plugins:link myplugin
```

## `cr plugins:uninstall PLUGIN...`

Removes a plugin from the CLI.

```
USAGE
  $ cr plugins:uninstall PLUGIN...

ARGUMENTS
  PLUGIN  plugin to uninstall

FLAGS
  -h, --help     Show CLI help.
  -v, --verbose

DESCRIPTION
  Removes a plugin from the CLI.

ALIASES
  $ cr plugins unlink
  $ cr plugins remove
```

## `cr plugins:uninstall PLUGIN...`

Removes a plugin from the CLI.

```
USAGE
  $ cr plugins:uninstall PLUGIN...

ARGUMENTS
  PLUGIN  plugin to uninstall

FLAGS
  -h, --help     Show CLI help.
  -v, --verbose

DESCRIPTION
  Removes a plugin from the CLI.

ALIASES
  $ cr plugins unlink
  $ cr plugins remove
```

## `cr plugins:uninstall PLUGIN...`

Removes a plugin from the CLI.

```
USAGE
  $ cr plugins:uninstall PLUGIN...

ARGUMENTS
  PLUGIN  plugin to uninstall

FLAGS
  -h, --help     Show CLI help.
  -v, --verbose

DESCRIPTION
  Removes a plugin from the CLI.

ALIASES
  $ cr plugins unlink
  $ cr plugins remove
```

## `cr plugins update`

Update installed plugins.

```
USAGE
  $ cr plugins update [-h] [-v]

FLAGS
  -h, --help     Show CLI help.
  -v, --verbose

DESCRIPTION
  Update installed plugins.
```
<!-- commandsstop -->
