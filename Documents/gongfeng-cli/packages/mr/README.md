# oclif-hello-world

oclif example Hello World CLI

[![oclif](https://img.shields.io/badge/cli-oclif-brightgreen.svg)](https://oclif.io)
[![Version](https://img.shields.io/npm/v/oclif-hello-world.svg)](https://npmjs.org/package/oclif-hello-world)
[![CircleCI](https://circleci.com/gh/oclif/hello-world/tree/main.svg?style=shield)](https://circleci.com/gh/oclif/hello-world/tree/main)
[![Downloads/week](https://img.shields.io/npm/dw/oclif-hello-world.svg)](https://npmjs.org/package/oclif-hello-world)
[![License](https://img.shields.io/npm/l/oclif-hello-world.svg)](https://github.com/oclif/hello-world/blob/main/package.json)

<!-- toc -->
* [oclif-hello-world](#oclif-hello-world)
* [Usage](#usage)
* [Commands](#commands)
<!-- tocstop -->

# Usage

<!-- usage -->
```sh-session
$ npm install -g @tencent/gongfeng-cli-plugin-mr
$ gf COMMAND
running command...
$ gf (--version)
@tencent/gongfeng-cli-plugin-mr/0.21.0-beta.0 darwin-x64 node-v18.16.0
$ gf --help [COMMAND]
USAGE
  $ gf COMMAND
...
```
<!-- usagestop -->

# Commands

<!-- commands -->
* [`gf help [COMMANDS]`](#gf-help-commands)
* [`gf mr <command> [flags]`](#gf-mr-command-flags)
* [`gf mr checkout <iidOrBranch> [flags]`](#gf-mr-checkout-iidorbranch-flags)
* [`gf mr close [iidOrBranch] [flags]`](#gf-mr-close-iidorbranch-flags)
* [`gf mr create [flags]`](#gf-mr-create-flags)
* [`gf mr edit <iidOrBranch> [flags]`](#gf-mr-edit-iidorbranch-flags)
* [`gf mr list [flags]`](#gf-mr-list-flags)
* [`gf mr reopen <iidOrBranch> [flags]`](#gf-mr-reopen-iidorbranch-flags)
* [`gf mr show <iidOrBranch> [flags]`](#gf-mr-show-iidorbranch-flags)
* [`gf mr status [flags]`](#gf-mr-status-flags)
* [`gf plugins`](#gf-plugins)
* [`gf plugins:install PLUGIN...`](#gf-pluginsinstall-plugin)
* [`gf plugins:inspect PLUGIN...`](#gf-pluginsinspect-plugin)
* [`gf plugins:install PLUGIN...`](#gf-pluginsinstall-plugin-1)
* [`gf plugins:link PLUGIN`](#gf-pluginslink-plugin)
* [`gf plugins:uninstall PLUGIN...`](#gf-pluginsuninstall-plugin)
* [`gf plugins:uninstall PLUGIN...`](#gf-pluginsuninstall-plugin-1)
* [`gf plugins:uninstall PLUGIN...`](#gf-pluginsuninstall-plugin-2)
* [`gf plugins update`](#gf-plugins-update)

## `gf help [COMMANDS]`

Display help for gf.

```
USAGE
  $ gf help [COMMANDS] [-n]

ARGUMENTS
  COMMANDS  Command to show help for.

FLAGS
  -n, --nested-commands  Include all nested commands in the output.

DESCRIPTION
  Display help for gf.
```

_See code: [@oclif/plugin-help](https://github.com/oclif/plugin-help/blob/v5.2.9/src/commands/help.ts)_

## `gf mr <command> [flags]`

工蜂合并请求管理

```
USAGE
  $ gf mr <command> [flags]

EXAMPLES
  $ gf mr list

  $ gf mr create

  $ gf mr show 3

  $ gf mr close 1

  $ gf mr reopen dev
```

## `gf mr checkout <iidOrBranch> [flags]`

检出合并请求源分支

```
USAGE
  $ gf mr checkout <iidOrBranch> [flags]

ARGUMENTS
  IIDORBRANCH  合并请求 id 或者源分支名称

FLAGS
  -R, --repo=<value>    指定仓库，参数值使用“namespace/repo”的格式
  -b, --branch=<value>  本地分支使用的名称（默认为合并请求源分支名称）

DESCRIPTION
  检出合并请求源分支

  从远程仓库检出合并请求源分支到本地。

EXAMPLES
  $ gf mr checkout 42

  $ gf mr checkout dev
```

## `gf mr close [iidOrBranch] [flags]`

关闭一个合并请求

```
USAGE
  $ gf mr close [iidOrBranch] [flags]

ARGUMENTS
  IIDORBRANCH  合并请求 iid 或者源分支名称

FLAGS
  -R, --repo=<value>     指定仓库，参数值使用“namespace/repo”的格式
  -c, --comment=<value>  关闭的同时发表一条评论

DESCRIPTION
  关闭一个合并请求

  可以通过 iid 或者源分支指定需要关闭的合并请求
  当通过源分支指定时默认关闭源分支最新的合并请求

EXAMPLES
  $ gf mr close 42

  $ gf mr close dev
```

## `gf mr create [flags]`

创建合并请求

```
USAGE
  $ gf mr create [flags]

FLAGS
  -R, --repo=<value>                指定仓库，参数值使用“namespace/repo”格式
  -T, --target=<value>              目标分支（默认为仓库的默认分支）
  -d, --description=<value>         合并请求描述
  -n, --necessary-reviewer=<value>  通过用户名指定必要评审人，使用英文逗号(,)分割
  -q, --quick                       快速发起合并请求，所有字段使用默认值
  -r, --reviewer=<value>            通过用户名指定评审人，使用英文逗号(,)分割
  -s, --source=<value>              源分支（默认为当前分支）
  -t, --title=<value>               合并请求标题
  -w, --web                         打开浏览器创建合并请求

DESCRIPTION
  创建合并请求

  没有指定源分支时，会默认将当前分支的更改推送至远程跟踪分支，然后发起与目标分支的合并请求。
  命令行默认会通过问答的模式引导填写信息，同时带-t和-d参数时会跳过问答模式直接发起MR。使用-q可以使用默认信息快速创建合并
  请求，使用-w参数可以打开浏览器创建合并请求。

EXAMPLES
  $ gf mr create

  $ gf mr create -q

  $ gf mr create --title "merge request title" --description "merge request description"
```

## `gf mr edit <iidOrBranch> [flags]`

编辑合并请求

```
USAGE
  $ gf mr edit <iidOrBranch> [flags]

ARGUMENTS
  IIDORBRANCH  合并请求 id 或者源分支名称

FLAGS
  -R, --repo=<value>           指定仓库，参数值使用“namespace/repo”的格式
  -c, --rm-reviewer=<value>    删除评审人，可以删除多个评审人 , 使用英文逗号(,)分割
  -d, --description=<value>    设置新的描述
  -t, --title=<value>          设置新的标题
  -v, --rm-necessary=<value>   删除必要评审人，可以删除多个必要评审人 , 使用英文逗号(,)分割
  -x, --add-necessary=<value>  添加必要评审人，可以添加多个必要评审人，使用英文逗号(,)分割
  -z, --add-reviewer=<value>   添加评审人，可以添加多个评审人，使用英文逗号(,)分割

EXAMPLES
  $ gf mr edit 123 --title "edit merge request title" --description "edit merge request description"

  $ gf mr edit master --add-reviewer jack,rose --rm-reviewer alex
```

## `gf mr list [flags]`

显示仓库下的合并请求

```
USAGE
  $ gf mr list [flags]

公共参数 FLAGS
  -A, --author=<value>    按作者过滤
  -L, --limit=<value>     [default: 20] 最多显示的合并请求数量
  -R, --repo=<value>      指定仓库，参数值使用“namespace/repo”的格式
  -T, --target=<value>    按目标分支过滤
  -a, --assignee=<value>  按合并负责人过滤
  -l, --label=<value>     按标签过滤
  -r, --reviewer=<value>  按评审人过滤
  -s, --state=<value>     [default: opened] 按合并请求状态过滤，可选值为“opened|merged|closed|all”
  -w, --web               打开浏览器查看合并请求列表
  --columns=<value>       仅显示指定列（多个值之间用,分隔）
  --csv                   以csv格式输出（“--output=csv” 的别名）
  --extended              显示更多的列
  --filter=<value>        对指定列进行过滤，例如: --filter="标题=wip"
  --no-header             隐藏列表的header
  --no-truncate           不截断输出
  --output=<value>        以其他格式输出，可选值为“csv|json|yaml”
  --sort=<value>          通过指定字段名进行排序（降序在字段名前加上“-”）

EXAMPLES
  $ gf mr list

  $ gf mr list --author zhangsan
```

## `gf mr reopen <iidOrBranch> [flags]`

重新打开一个合并请求

```
USAGE
  $ gf mr reopen <iidOrBranch> [flags]

ARGUMENTS
  IIDORBRANCH  合并请求 iid 或者源分支名称

FLAGS
  -R, --repo=<value>     指定仓库，参数值使用“namespace/repo”的格式
  -c, --comment=<value>  重新打开的同时发表一条评论

DESCRIPTION
  重新打开一个合并请求

  可以通过 iid 或者源分支指定需要重新打开的合并请求
  当通过源分支指定时默认重新打开源分支最新的合并请求

EXAMPLES
  $ gf mr reopen 42

  $ gf mr reopen dev
```

## `gf mr show <iidOrBranch> [flags]`

查看单个合并请求

```
USAGE
  $ gf mr show <iidOrBranch> [flags]

ARGUMENTS
  IIDORBRANCH  合并请求 iid 或者源分支名称

FLAGS
  -R, --repo=<value>  指定仓库，参数值使用“namespace/repo”的格式
  -w, --web           打开浏览器查看合并请求

DESCRIPTION
  查看单个合并请求


  显示单个合并请求的标题、描述、状态、评审人等信息
  如果不指定合并请求的 iid 或源分支，默认显示属于当前分支且正在处理中的合并请求

EXAMPLES
  $ gf mr show 42

  $ gf mr show dev
```

## `gf mr status [flags]`

显示与我相关的合并请求

```
USAGE
  $ gf mr status [flags]

公共参数 FLAGS
  -R, --repo=<value>  指定仓库，参数值使用“namespace/repo”的格式
  --columns=<value>   仅显示指定列（多个值之间用,分隔）
  --csv               以csv格式输出（“--output=csv” 的别名）
  --extended          显示更多的列
  --filter=<value>    对指定列进行过滤，例如: --filter="标题=wip"
  --no-header         隐藏列表的header
  --no-truncate       不截断输出
  --output=<value>    以其他格式输出，可选值为“csv|json|yaml”
  --sort=<value>      通过指定字段名进行排序（降序在字段名前加上“-”）

EXAMPLES
  $ gf mr status

  $ gf mr status --R namespace/repo
```

## `gf plugins`

List installed plugins.

```
USAGE
  $ gf plugins [--core]

FLAGS
  --core  Show core plugins.

DESCRIPTION
  List installed plugins.

EXAMPLES
  $ gf plugins
```

_See code: [@oclif/plugin-plugins](https://github.com/oclif/plugin-plugins/blob/v2.4.7/src/commands/plugins/index.ts)_

## `gf plugins:install PLUGIN...`

Installs a plugin into the CLI.

```
USAGE
  $ gf plugins:install PLUGIN...

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
  $ gf plugins add

EXAMPLES
  $ gf plugins:install myplugin 

  $ gf plugins:install https://github.com/someuser/someplugin

  $ gf plugins:install someuser/someplugin
```

## `gf plugins:inspect PLUGIN...`

Displays installation properties of a plugin.

```
USAGE
  $ gf plugins:inspect PLUGIN...

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
  $ gf plugins:inspect myplugin
```

## `gf plugins:install PLUGIN...`

Installs a plugin into the CLI.

```
USAGE
  $ gf plugins:install PLUGIN...

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
  $ gf plugins add

EXAMPLES
  $ gf plugins:install myplugin 

  $ gf plugins:install https://github.com/someuser/someplugin

  $ gf plugins:install someuser/someplugin
```

## `gf plugins:link PLUGIN`

Links a plugin into the CLI for development.

```
USAGE
  $ gf plugins:link PLUGIN

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
  $ gf plugins:link myplugin
```

## `gf plugins:uninstall PLUGIN...`

Removes a plugin from the CLI.

```
USAGE
  $ gf plugins:uninstall PLUGIN...

ARGUMENTS
  PLUGIN  plugin to uninstall

FLAGS
  -h, --help     Show CLI help.
  -v, --verbose

DESCRIPTION
  Removes a plugin from the CLI.

ALIASES
  $ gf plugins unlink
  $ gf plugins remove
```

## `gf plugins:uninstall PLUGIN...`

Removes a plugin from the CLI.

```
USAGE
  $ gf plugins:uninstall PLUGIN...

ARGUMENTS
  PLUGIN  plugin to uninstall

FLAGS
  -h, --help     Show CLI help.
  -v, --verbose

DESCRIPTION
  Removes a plugin from the CLI.

ALIASES
  $ gf plugins unlink
  $ gf plugins remove
```

## `gf plugins:uninstall PLUGIN...`

Removes a plugin from the CLI.

```
USAGE
  $ gf plugins:uninstall PLUGIN...

ARGUMENTS
  PLUGIN  plugin to uninstall

FLAGS
  -h, --help     Show CLI help.
  -v, --verbose

DESCRIPTION
  Removes a plugin from the CLI.

ALIASES
  $ gf plugins unlink
  $ gf plugins remove
```

## `gf plugins update`

Update installed plugins.

```
USAGE
  $ gf plugins update [-h] [-v]

FLAGS
  -h, --help     Show CLI help.
  -v, --verbose

DESCRIPTION
  Update installed plugins.
```
<!-- commandsstop -->
