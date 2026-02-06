import { Hook } from '@oclif/core';
import { initSentry } from '@tencent/gongfeng-cli-base';

export const sentryInit: Hook.Prerun = async function () {
  await initSentry();
};
