import { User } from '../gong-feng';

/**
 * 用在项目级别
 */
export enum Role {
  ANONYMOUS = 0,
  USER = 5,
  GUEST = 10,
  FOLLOWER = 15,
  REPORTER = 20,
  DEVELOPER = 30,
  MASTER = 40,
  OWNER = 50,
  ADMIN = 100,
}

export enum PermissionType {
  PROJECT = 'project',
  GROUP = 'group',
}

export interface UserSession {
  maxRole: Role;
  /**
   * 当前用户【无论是匿名还是认证】访问的资源类型
   */
  permissionType: PermissionType;
  authorities: string[];
  permissions: string[];
  isInitialized: boolean;
  user?: User;
}
