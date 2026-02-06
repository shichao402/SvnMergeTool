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
$ npm install -g @tencent/gongfeng-cli-plugin-aiut
$ gf COMMAND
running command...
$ gf (--version)
@tencent/gongfeng-cli-plugin-aiut/0.25.3-beta.0 darwin-x64 node-v18.16.0
$ gf --help [COMMAND]
USAGE
  $ gf COMMAND
...
```
<!-- usagestop -->

# Commands

<!-- commands -->
* [`gf aiut <command> [flags]`](#gf-aiut-command-flags)
* [`gf aiut fix <testFilePath> [-- flags...]`](#gf-aiut-fix-testfilepath----flags)
* [`gf aiut run <projectPath> [-- flags...]`](#gf-aiut-run-projectpath----flags)
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

## `gf aiut <command> [flags]`

工蜂AI单测

```
USAGE
  $ gf aiut <command> [flags]

EXAMPLES
  $ gf aiut run path

  $ gf aiut fix path
```

## `gf aiut fix <testFilePath> [-- flags...]`

修复单测

```
USAGE
  $ gf aiut fix <testFilePath> [-- flags...]

ARGUMENTS
  PATH  测试文件路径或测试目录路径（相对路径和绝对路径均可，多个路径使用逗号分隔）

FLAGS
  -p, --projectPath=<value>  项目路径
  -v, --verbose              是否输出详细日志

EXAMPLES
  修复单个测试文件：gf aiut fix test/example_test.go

  修复多个测试文件：gf aiut fix test/file1_test.go,test/file2_test.go

  修复整个测试目录：gf aiut fix test
```

## `gf aiut run <projectPath> [-- flags...]`

生成单测

```
USAGE
  $ gf aiut run <projectPath> [-- flags...]

ARGUMENTS
  PATH  项目生成传项目路径，文件/文件夹生成传文件/文件夹路径（相对路径和绝对路径均可，多个路径使用逗号分隔）

FLAGS
  -d, --default                是否使用默认值
  -e, --referencePath=<value>  指定文件路径
  -f, --framework=<value>      框架名称
  -i, --ignoreRule=<value>     忽略规则(glob语法, 多个用逗号分隔)
  -m, --model=<value>          模型名称
  -p, --projectPath=<value>    项目路径
  -r, --referenceType=<value>  参考类型
  -t, --type=<value>           [default: project] 生成类型（项目生成：project, 文件/文件夹生成：file）
  -v, --verbose                是否输出详细日志
  --langConfig=<value>         语言配置(JSON字符串)

EXAMPLES
  项目生成：gf aiut run . --type project --projectPath projectPath

  文件/文件夹生成：gf aiut run filePath,folderPath --type file --projectPath projectPath
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
