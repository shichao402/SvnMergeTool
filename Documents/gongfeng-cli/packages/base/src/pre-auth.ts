import 'reflect-metadata';
import netrc from 'netrc-parser';
import { vars } from './vars';
import { AUTH_TOKEN_TYPE_KEY, AuthTokenType } from './auth';

/**
 * 判断是否需要跳过检测登录
 * @param options
 */
export function preAuth(options: { skip: boolean }): MethodDecorator {
  return (target, key) => {
    Reflect.defineMetadata('skip', options.skip, target, key);
  };
}

/**
 * 判断是否登录
 */
export async function checkAuth() {
  const token = await authToken();
  return !!token;
}

/**
 * 判断某域名下是否登录
 * @param host 域名
 */
export async function checkHostAuth(host: string) {
  const token = await authHostToken(host);
  return !!token;
}

/**
 * 获取认证 token
 */
export async function authToken() {
  return authHostToken(vars.host());
}

export async function getAuthTokenType(): Promise<AuthTokenType> {
  const host = vars.host();
  await netrc.load();
  const netrcHost = netrc.machines[host];
  return (netrcHost?.[AUTH_TOKEN_TYPE_KEY] as AuthTokenType) || AuthTokenType.ACCESS_TOKEN;
}

/**
 * 获取指定域名下的认证 token
 * 优先读取环境变量中的 GF_TOKEN (access_token)/ GF_PERSONAL_TOKEN(personal_token)
 * @param host
 */
export async function authHostToken(host: string) {
  if (process.env.GF_PERSONAL_TOKEN) {
    return process.env.GF_PERSONAL_TOKEN;
  }
  if (process.env.GF_TOKEN) {
    return process.env.GF_TOKEN;
  }
  await netrc.load();
  const netrcHost = netrc.machines[host];
  return netrcHost?.password;
}

export async function authHeaders(): Promise<{
  'PRIVATE-TOKEN'?: string;
  'User-Agent': string;
  Authorization?: string;
}> {
  if (process.env.GF_PERSONAL_TOKEN) {
    return buildAuthHeaders(AuthTokenType.PERSONAL_TOKEN, process.env.GF_PERSONAL_TOKEN);
  }
  const token = await authToken();
  const authTokenType = await getAuthTokenType();
  return buildAuthHeaders(authTokenType, token);
}

export async function cloneTokenCompo() {
  if (process.env.GF_PERSONAL_TOKEN) {
    return `private:${process.env.GF_PERSONAL_TOKEN}`;
  }
  const token = await authToken();
  const authTokenType = await getAuthTokenType();
  switch (authTokenType) {
    case AuthTokenType.PERSONAL_TOKEN:
      return `private:${token}`;
    default:
      return `oauth2:${token}`;
  }
  return;
}

/**
 * 登录用户名
 */
export async function loginUser() {
  return loginHostUser(vars.host());
}

/**
 * 指定域名下的登录用户名
 * @param host
 */
export async function loginHostUser(host: string) {
  if (process.env.GF_USERNAME) {
    return process.env.GF_USERNAME;
  }
  await netrc.load();
  const netrcHost = netrc.machines[host];
  return netrcHost?.login ?? '';
}

export async function buildAuthHeaders(authTokenType: AuthTokenType, token?: string) {
  switch (authTokenType) {
    case AuthTokenType.PERSONAL_TOKEN: {
      return {
        'PRIVATE-TOKEN': token,
        'User-Agent': 'GFCLI',
      };
    }
    default: {
      return {
        Authorization: `Bearer ${token}`,
        'User-Agent': 'GFCLI',
      };
    }
  }
}
