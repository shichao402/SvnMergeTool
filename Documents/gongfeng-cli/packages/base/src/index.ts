import { vars } from './vars';
import report, { BeaconEventParam, replaceBeaconSymbol } from './datahub/index';
import ActionReport from './datahub/action-report';
import { Git as GitShell, Remote } from './git-shell';
import * as file from './file';
import color from './color';
import getMAC from './mac';
import {
  preAuth,
  checkAuth,
  authToken,
  checkHostAuth,
  authHostToken,
  loginUser,
  authHeaders,
  cloneTokenCompo,
  buildAuthHeaders,
} from './pre-auth';
import {
  Project,
  Project4Detail,
  Group,
  Rules,
  Role,
  hasPermission,
  normalizeProjectPath,
  User,
  Commit,
  ProtectedBranch,
  Milestone,
  Label,
  LabelType,
  UserState,
  BackEndError,
  ApiUserMixin,
  AutocompleteUserScope,
  ApiUserStateScope,
  AutocompleteUserOptions,
  AutocompleteUser,
  UserSelectChoice,
  getBackEndError,
} from './gong-feng';
import { getCurrentRemote, getSourceRemote } from './context';
import * as git from './git';
import * as Models from './models';
import * as shell from './shell';
import logger from './logger';
import { initSentry } from './sentry';
import GongFengHelp from './help';
import { Auth, AuthResponse, LocaleTypes, AuthTokenType, AUTH_TOKEN_TYPE_KEY } from './auth';
import BaseApiService from './base-service';
import { truncateHalfAngleString } from './utils/text-utils';
import { getTraceId, getErrorMessage } from './utils/error';
import { getUrlWithAdTag } from './utils/url-utility';

const CONFIG_FILE = 'config.json';

export {
  vars,
  report,
  BeaconEventParam,
  replaceBeaconSymbol,
  CONFIG_FILE,
  GitShell,
  Remote,
  file,
  color,
  getMAC,
  preAuth,
  checkAuth,
  authToken,
  checkHostAuth,
  authHostToken,
  Project,
  Project4Detail,
  Group,
  Rules,
  Role,
  User,
  Commit,
  ProtectedBranch,
  Milestone,
  Label,
  LabelType,
  ApiUserMixin,
  AutocompleteUserScope,
  ApiUserStateScope,
  AutocompleteUserOptions,
  AutocompleteUser,
  UserSelectChoice,
  hasPermission,
  normalizeProjectPath,
  loginUser,
  getCurrentRemote,
  getSourceRemote,
  UserState,
  BackEndError,
  getBackEndError,
  git,
  Models,
  shell,
  logger,
  initSentry,
  GongFengHelp,
  Auth,
  AuthResponse,
  LocaleTypes,
  BaseApiService,
  truncateHalfAngleString,
  authHeaders,
  cloneTokenCompo,
  buildAuthHeaders,
  AuthTokenType,
  AUTH_TOKEN_TYPE_KEY,
  getTraceId,
  getErrorMessage,
  ActionReport,
  getUrlWithAdTag,
};
