import { Hook } from '@oclif/core';

const hook: Hook.CommandNotFound = async function (options) {
  this.log(`命令${options.id}不存在，执行gf --help获取帮助`);
};

export default hook;
