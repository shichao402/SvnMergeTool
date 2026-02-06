# 工蜂 CLI

在控制台上使用工蜂。工蜂 CLI 是基于[oclif](https://oclif.io)开发而成。

<!-- toc -->
* [工蜂 CLI](#工蜂-cli)
* [Usage](#usage)
* [Commands](#commands)
<!-- tocstop -->

# Usage

<!-- usage -->
```sh-session
$ npm install -g @tencent/gongfeng-cli
$ gf COMMAND
running command...
$ gf (--version|-v)
@tencent/gongfeng-cli/0.25.3-beta.0 darwin-x64 node-v18.16.0
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
* [`gf aiut <command> [flags]`](#gf-aiut-command-flags)
* [`gf aiut fix <testFilePath> [-- flags...]`](#gf-aiut-fix-testfilepath----flags)
* [`gf aiut run <projectPath> [-- flags...]`](#gf-aiut-run-projectpath----flags)
* [`gf auth <command> [flags]`](#gf-auth-command-flags)
* [`gf auth login`](#gf-auth-login)
* [`gf auth logout`](#gf-auth-logout)
* [`gf auth whoami`](#gf-auth-whoami)
* [`gf autocomplete [SHELL]`](#gf-autocomplete-shell)
* [`gf copilot <command> [flags]`](#gf-copilot-command-flags)
* [`gf copilot git QUESTION`](#gf-copilot-git-question)
* [`gf copilot sh QUESTION`](#gf-copilot-sh-question)
* [`gf cr <command> [flags]`](#gf-cr-command-flags)
* [`gf cr close [iid] [flags]`](#gf-cr-close-iid-flags)
* [`gf cr create [path] [flags]`](#gf-cr-create-path-flags)
* [`gf cr edit <iid> [flags]`](#gf-cr-edit-iid-flags)
* [`gf cr list [flags]`](#gf-cr-list-flags)
* [`gf cr reopen [iid] [flags]`](#gf-cr-reopen-iid-flags)
* [`gf cr update IID`](#gf-cr-update-iid)
* [`gf help [COMMANDS]`](#gf-help-commands)
* [`gf issue <command> [flags]`](#gf-issue-command-flags)
* [`gf issue list [flags]`](#gf-issue-list-flags)
* [`gf issue show <iid> [flags]`](#gf-issue-show-iid-flags)
* [`gf login`](#gf-login)
* [`gf logout`](#gf-logout)
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
* [`gf release <command> [flags]`](#gf-release-command-flags)
* [`gf release list [flags]`](#gf-release-list-flags)
* [`gf release show <release title> [flags]`](#gf-release-show-release-title-flags)
* [`gf repo <command> [flags]`](#gf-repo-command-flags)
* [`gf repo clone <repository> [-- gitflags...]`](#gf-repo-clone-repository----gitflags)
* [`gf repo show <repository> [flags]`](#gf-repo-show-repository-flags)
* [`gf update [CHANNEL]`](#gf-update-channel)
* [`gf whoami`](#gf-whoami)

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

## `gf auth <command> [flags]`

工蜂账号管理

```
USAGE
  $ gf auth <command> [flags]
```

_See code: [@tencent/gongfeng-cli-plugin-auth](https://github.com/packages/auth/blob/v0.21.0-beta.0/dist/commands/auth/index.ts)_

## `gf auth login`

登录工蜂

```
USAGE
  $ gf auth login [-t <value>]

FLAGS
  -t, --token=<value>  从标准输入中获取token进行登录。

DESCRIPTION
  登录工蜂

  不带任何参数时，工蜂CLI会通过交互的方式引导登录，这种模式下支持3种登录方式：
  1. 通过IOA登录；
  2. 打开Web浏览器输入设备码；
  3. 输入Token（oauth2 access token或者personal access token）。

  此外，也可以执行‘gf auth login --token xxx’，直接从标准输入中获取token登录工蜂。

  最后，如果将token定义在了环境变量中“xxx”，工蜂CLI会直接使用环境变量的值进行认证而无需执行登录命令，此方式适用于流水线
  等自动化场景。

ALIASES
  $ gf login

EXAMPLES
  $ gf auth login
```

## `gf auth logout`

退出账号

```
USAGE
  $ gf auth logout

ALIASES
  $ gf logout

EXAMPLES
  $ gf auth logout
```

## `gf auth whoami`

显示当前登录账号的信息

```
USAGE
  $ gf auth whoami

ALIASES
  $ gf whoami
```

## `gf autocomplete [SHELL]`

display autocomplete installation instructions

```
USAGE
  $ gf autocomplete [SHELL] [-r]

ARGUMENTS
  SHELL  (zsh|bash|powershell) Shell type

FLAGS
  -r, --refresh-cache  Refresh cache (ignores displaying instructions)

DESCRIPTION
  display autocomplete installation instructions

EXAMPLES
  $ gf autocomplete

  $ gf autocomplete bash

  $ gf autocomplete zsh

  $ gf autocomplete powershell

  $ gf autocomplete --refresh-cache
```

_See code: [@oclif/plugin-autocomplete](https://github.com/oclif/plugin-autocomplete/blob/v2.3.0/src/commands/autocomplete/index.ts)_

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

_See code: [@tencent/gongfeng-cli-plugin-copilot](https://github.com/packages/copilot/blob/v0.21.0-beta.0/dist/commands/copilot/index.ts)_

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

## `gf cr <command> [flags]`

工蜂代码评审管理

```
USAGE
  $ gf cr <command> [flags]

EXAMPLES
  $ gf cr list

  $ gf cr create

  $ gf cr close 1

  $ gf cr reopen 13
```

## `gf cr close [iid] [flags]`

关闭一个代码评审

```
USAGE
  $ gf cr close [iid] [flags]

ARGUMENTS
  IID  代码评审 iid

FLAGS
  -c, --comment=<value>  关闭的同时发表一条评论

DESCRIPTION
  关闭一个代码评审

  通过指定 iid 关闭一个代码评审

EXAMPLES
  $ gf cr close 123
```

## `gf cr create [path] [flags]`

创建代码评审(目前只支持 svn 代码在本地模式)

```
USAGE
  $ gf cr create [path] [flags]

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
  $ gf cr create /users/project/test/trunk

  $ gf cr create
```

## `gf cr edit <iid> [flags]`

编辑代码评审

```
USAGE
  $ gf cr edit <iid> [flags]

ARGUMENTS
  IID  代码评审 iid

SVN 代码评审参数 FLAGS
  -c, --cc=<value>  添加抄送人，可以添加多个抄送人，使用英文逗号(,)分割

公共参数 FLAGS
  -d, --description=<value>   设置新的描述
  -t, --title=<value>         设置新的标题
  -z, --add-reviewer=<value>  添加评审人，可以添加多个评审人，使用英文逗号(,)分割

EXAMPLES
  $ gf cr edit 123 --title "edit code review title" --description "edit code review description"
```

## `gf cr list [flags]`

显示仓库下的代码评审

```
USAGE
  $ gf cr list [flags]

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
  $ gf cr list

  $ gf cr list --author zhangsan
```

## `gf cr reopen [iid] [flags]`

重新打开一个代码评审

```
USAGE
  $ gf cr reopen [iid] [flags]

ARGUMENTS
  IID  代码评审 iid

FLAGS
  -c, --comment=<value>  关闭的同时发表一条评论

DESCRIPTION
  重新打开一个代码评审

  通过指定 iid 重新打开一个代码评审

EXAMPLES
  $ gf cr reopen 123
```

## `gf cr update IID`

上传修订集(目前只支持 svn 代码在本地模式)

```
USAGE
  $ gf cr update IID [-d <value>] [-a <value>] [--only-filename] [-f <value>] [-s <value>] [-e <value>]

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

## `gf issue <command> [flags]`

工蜂issue管理

```
USAGE
  $ gf issue <command> [flags]

DESCRIPTION
  工蜂issue管理

EXAMPLES
  $ gf issue list --label "feature"

  $ gf issue show 1 -w
```

## `gf issue list [flags]`

查看项目下的issue列表

```
USAGE
  $ gf issue list [flags]

公共参数 FLAGS
  -A, --author=<value>    按作者过滤
  -L, --limit=<value>     [default: 20] 最多显示的issue数量
  -R, --repo=<value>      指定仓库，参数值使用“namespace/repo”的格式
  -a, --assignee=<value>  按负责人过滤
  -l, --label=<value>     按标签过滤
  -s, --state=<value>     [default: opened] 按issue状态过滤，可选值为“opened|closed|all
  -w, --web               打开浏览器查看issue列表
  --columns=<value>       仅显示指定列（多个值之间用,分隔）
  --csv                   以csv格式输出（“--output=csv” 的别名）
  --extended              显示更多的列
  --filter=<value>        对指定列进行过滤，例如: --filter="标题=wip"
  --no-header             隐藏列表的header
  --no-truncate           不截断输出
  --output=<value>        以其他格式输出，可选值为“csv|json|yaml”
  --sort=<value>          通过指定字段名进行排序（降序在字段名前加上“-”）

EXAMPLES
  $ gf issue list --label "feature"

  $ gf issue list --author zhangsan
```

## `gf issue show <iid> [flags]`

查看 issue 的详细信息

```
USAGE
  $ gf issue show <iid> [flags]

ARGUMENTS
  IID  议题的iid

FLAGS
  -R, --repo=<value>  指定仓库，参数值使用“namespace/repo”的格式
  -w, --web           打开浏览器查看issue

EXAMPLES
  $ gf issue show 1 -w
```

## `gf login`

登录工蜂

```
USAGE
  $ gf login [-t <value>]

FLAGS
  -t, --token=<value>  从标准输入中获取token进行登录。

DESCRIPTION
  登录工蜂

  不带任何参数时，工蜂CLI会通过交互的方式引导登录，这种模式下支持3种登录方式：
  1. 通过IOA登录；
  2. 打开Web浏览器输入设备码；
  3. 输入Token（oauth2 access token或者personal access token）。

  此外，也可以执行‘gf auth login --token xxx’，直接从标准输入中获取token登录工蜂。

  最后，如果将token定义在了环境变量中“xxx”，工蜂CLI会直接使用环境变量的值进行认证而无需执行登录命令，此方式适用于流水线
  等自动化场景。

ALIASES
  $ gf login

EXAMPLES
  $ gf auth login
```

## `gf logout`

退出账号

```
USAGE
  $ gf logout

ALIASES
  $ gf logout

EXAMPLES
  $ gf auth logout
```

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

## `gf release <command> [flags]`

工蜂 release 管理

```
USAGE
  $ gf release <command> [flags]

EXAMPLES
  $ gf release list

  $ gf release show v1.5.0
```

## `gf release list [flags]`

查看仓库下的 release

```
USAGE
  $ gf release list [flags]

公共参数 FLAGS
  -A, --author=<value>  按作者过滤
  -L, --limit=<value>   [default: 20] 最多显示的 release 数量
  -R, --repo=<value>    指定仓库，参数值使用“namespace/repo”的格式
  -l, --label=<value>   按标签过滤
  -w, --web             打开浏览器查看 release 列表
  --columns=<value>     仅显示指定列（多个值之间用,分隔）
  --csv                 以csv格式输出（“--output=csv” 的别名）
  --extended            显示更多的列
  --filter=<value>      对指定列进行过滤，例如: --filter="标题=wip"
  --no-header           隐藏列表的header
  --no-truncate         不截断输出
  --output=<value>      以其他格式输出，可选值为“csv|json|yaml”
  --sort=<value>        通过指定字段名进行排序（降序在字段名前加上“-”）

EXAMPLES
  $ gf release list
```

## `gf release show <release title> [flags]`

查看release的详细信息

```
USAGE
  $ gf release show <release title> [flags]

ARGUMENTS
  RELEASETITLE  release的标题

FLAGS
  -R, --repo=<value>  指定仓库，参数值使用“namespace/repo”的格式
  -w, --web           打开浏览器查看 release 详细信息

EXAMPLES
  $ gf release show v1.5.0 -w
```

## `gf repo <command> [flags]`

工蜂仓库管理

```
USAGE
  $ gf repo <command> [flags]

EXAMPLES
  $ gf repo show -w

  $ gf repo clone code/cli
```

## `gf repo clone <repository> [-- gitflags...]`

克隆工蜂仓库到本地

```
USAGE
  $ gf repo clone <repository> [-- gitflags...]

ARGUMENTS
  REPOSITORY  指定仓库，参数值使用项目链接或者“namespace/repo”格式

EXAMPLES
  $ gf repo clone code/cli
```

## `gf repo show <repository> [flags]`

显示仓库的名称和README

```
USAGE
  $ gf repo show <repository> [flags]

ARGUMENTS
  REPOSITORY  指定仓库，参数值使用仓库链接或者“namespace/repo”格式

FLAGS
  -w, --web  打开浏览器查看仓库

DESCRIPTION
  显示仓库的名称和README

  不指定仓库时，默认显示当前本地目录对应的远程仓库。
  使用“--web”可以直接在浏览器中打开相应仓库查看。

EXAMPLES
  $ gf repo show -w
```

## `gf update [CHANNEL]`

update the gf CLI

```
USAGE
  $ gf update [CHANNEL] [-a] [-v <value> | -i] [--force]

FLAGS
  -a, --available        Install a specific version.
  -i, --interactive      Interactively select version to install. This is ignored if a channel is provided.
  -v, --version=<value>  Install a specific version.
  --force                Force a re-download of the requested version.

DESCRIPTION
  update the gf CLI

EXAMPLES
  Update to the stable channel:

    $ gf update stable

  Update to a specific version:

    $ gf update --version 1.0.0

  Interactively select version:

    $ gf update --interactive

  See available versions:

    $ gf update --available
```

_See code: [@tencent/code-plugin-update](https://github.com/oclif/plugin-update/blob/v3.0.13/src/commands/update.ts)_

## `gf whoami`

显示当前登录账号的信息

```
USAGE
  $ gf whoami

ALIASES
  $ gf whoami
```
<!-- commandsstop -->
