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
$ npm install -g @tencent/gongfeng-cli-plugin-aicr
$ gf COMMAND
running command...
$ gf (--version)
@tencent/gongfeng-cli-plugin-aicr/0.21.0-beta.0 darwin-x64 node-v18.16.0
$ gf --help [COMMAND]
USAGE
  $ gf COMMAND
...
```
<!-- usagestop -->

# Commands

<!-- commands -->
* [`gf aicr <command> [flags]`](#gf-aicr-command-flags)
* [`gf aicr commit <commitSha> [-- flags...]`](#gf-aicr-commit-commitsha----flags)
* [`gf aicr diff [-- flags...]`](#gf-aicr-diff----flags)
* [`gf help [COMMANDS]`](#gf-help-commands)
* [`gf plugins`](#gf-plugins)
* [`gf plugins:install PLUGIN...`](#gf-pluginsinstall-plugin)
* [`gf plugins:inspect PLUGIN...`](#gf-pluginsinspect-plugin)
* [`gf plugins:install PLUGIN...`](#gf-pluginsinstall-plugin-1)
* [`gf plugins:link PLUGIN`](#gf-pluginslink-plugin)
* [`gf plugins:uninstall PLUGIN...`](#gf-pluginsuninstall-plugin)
* [`gf plugins:uninstall PLUGIN...`](#gf-pluginsuninstall-plugin-1)
* [`gf plugins:uninstall PLUGIN...`](#gf-pluginsuninstall-plugin-2)
* [`gf plugins update`](#gf-plugins-update)

## `gf aicr <command> [flags]`

工蜂AICR

```
USAGE
  $ gf aicr <command> [flags]

EXAMPLES
  $ gf aicr diff

  $ gf aicr commit
```

## `gf aicr commit <commitSha> [-- flags...]`

aicr commit 评审

```
USAGE
  $ gf aicr commit <commitSha> [-- flags...]

ARGUMENTS
  SHA1  提交ID

FLAGS
  -A, --author=<value>       按作者过滤
  -B, --begintime=<value>    直接给定评审的起始时间,格式为YYYY-MM-DDTHH:MM:SS
  -C, --cc=<value>           抄送人, 使用英文逗号分隔,支持id或者英文名
  -E, --endtime=<value>      直接给定评审的结束时间,格式为YYYY-MM-DDTHH:MM:SS
  -F, --fromversion=<value>  从指定的版本号开始检查
  -S, --stopversion=<value>  检查到指定的版本号结束
  -T, --timeback=<value>     按时间过滤,只将从现在开始对指定时间范围内的提交包括在评审内容中,目前只支持天和周,如1d,1w
  -b, --background           异步执行创建aicr，不等待结果返回
  -d, --dryrun               演习模式，工蜂copilot告知审查的范围，但是不会开始执行任务
  -f, --files=<value>...     指定评审文件(文件路径从 git 项目根目录开始)
  -p, --path=<value>         按路径过滤,只将指定路径下的文件包括在评审内容中
  -r, --ref=<value>          指定git分支或者tag
  -s, --skips=<value>...     指定忽略评审文件(文件路径从 git 项目根目录开始)
  -t, --title=<value>        aicr 评审标题
  -v, --verbose              输出全部 AI 评审结果

EXAMPLES
  $ gf aicr commit c325e4b9

  $ gf aicr commit c325e4b9 -f src/test.js -f src/add.js

  $ gf aicr commit c325e4b9 -s src/test.js -s src/add.js
```

## `gf aicr diff [-- flags...]`

aicr diff 评审

```
USAGE
  $ gf aicr diff [-- flags...]

FLAGS
  -b, --background        异步执行创建aicr，不等待结果返回
  -e, --encoding=<value>  [default: utf-8] 指定变更编码, 如中文：GB18030
  -f, --files=<value>...  指定评审文件(文件路径从 git 项目根目录开始)
  -s, --skips=<value>...  指定忽略评审文件(文件路径从 git 项目根目录开始)
  -t, --title=<value>     aicr 评审标题
  -v, --verbose           输出全部 AI 评审结果

EXAMPLES
  $ gf aicr diff

  $ gf aicr diff -f src/test.js -f src/add.js

  $ gf aicr diff -s src/test.js -s src/add.js
```

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
