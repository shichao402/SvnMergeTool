import { isWindows } from './utils';
import * as path from 'path';
import { tmpdir, userInfo } from 'os';

const { username } = userInfo?.() || {};
const BASE_URL_MAP = {
  dev: 'https://ut-service.wolf.woa.com',
  ty: 'http://ut-service-ty.tapd.woa.com',
  prod: 'https://copilot.code.woa.com/api/ut/service/',
};
const UT_BASE_PATH_MAP = {
  dev: `copilot_ut_${username}_test`,
  ty: `copilot_ut_${username}_ty`,
  prod: `copilot_ut_${username}`,
};

export const BASE_URL = BASE_URL_MAP[process.env.UT_ENV as keyof typeof BASE_URL_MAP] || BASE_URL_MAP.prod;
export const COBUDDY_BASE_URL = 'https://copilot.code.woa.com';
export const UT_BASE_PATH = path.join(
  tmpdir(),
  UT_BASE_PATH_MAP[process.env.UT_ENV as keyof typeof UT_BASE_PATH_MAP] || UT_BASE_PATH_MAP.prod,
);
export const UT_GEN_PROJECT_PROGRESS_PATH = path.join(UT_BASE_PATH, '.progress_gen_by_project');
export const UT_GEN_FILE_PROGRESS_PATH = path.join(UT_BASE_PATH, '.progress_gen_by_file');
export const UT_FILE_NAME = isWindows() ? 'generate_ut.exe' : 'generate_ut';
export const TIMEOUT = 600 * 1000;
