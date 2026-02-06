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
$ npm install -g @tencent/gongfeng-cli-plugin-copilot
$ gf COMMAND
running command...
$ gf (--version)
@tencent/gongfeng-cli-plugin-copilot/0.21.0-beta.0 darwin-x64 node-v18.16.0
$ gf --help [COMMAND]
USAGE
  $ gf COMMAND
...
```
<!-- usagestop -->

# Commands

<!-- commands -->
* [`gf copilot <command> [flags]`](#gf-copilot-command-flags)
* [`gf copilot git QUESTION`](#gf-copilot-git-question)
* [`gf copilot sh QUESTION`](#gf-copilot-sh-question)
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

## `gf copilot <command> [flags]`

AI 命令行 Copilot

```
USAGE
  $ gf copilot <command> [flags]

DESCRIPTION
  AI 命令行 Copilot

  根据自然语言描述推荐命令。

  还在为记住某个shell命令而苦恼吗？还在写命令时需要去网络上查询相关帮助吗？有没有想过可以直接在终端通过自然语言说出你需
  要什么？别担心，我们将工蜂Copilot带到了您的命令行中。工蜂Copilot for CLI可以帮您：
  - 安装和升级软件
  - 排除和调试系统问题
  - 处理和操作文件
  - 使用Git命令

  工蜂Copilot for CLI目前支持以下命令：
  - gf copilot sh：生成通用任意shell命令
  - gf copilot git：专用于生成Git命令，当你不需要解释您在Git的上下文中时，您的描述可以更加简洁

EXAMPLES
  $ gf copilot sh "列出js文件"

  $ gf copilot git "删除 feature 分支"
```

_See code: [dist/commands/copilot/index.ts](https://github.com/packages/copilot/blob/v0.21.0-beta.0/dist/commands/copilot/index.ts)_

## `gf copilot git QUESTION`

Git AI 命令行 Copilot

```
USAGE
  $ gf copilot git QUESTION

ARGUMENTS
  QUESTION  需要查询的问题

EXAMPLES
  $ gf copilot git "删除feature分支"
```

## `gf copilot sh QUESTION`

Shell AI 命令行 Copilot

```
USAGE
  $ gf copilot sh QUESTION

ARGUMENTS
  QUESTION  需要查询的问题

EXAMPLES
  $ gf copilot sh "列出js文件"
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
