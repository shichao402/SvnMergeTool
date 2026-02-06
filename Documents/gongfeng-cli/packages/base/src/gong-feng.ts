/**
 * 角色定义
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

/**
 * 权限定义
 */
export enum Rules {
  CREATE_GROUP = 'create_group',
  READ_GROUP = 'read_group',
  CREATE_PROJECTS = 'create_projects',
  ADMIN_GROUP = 'admin_group',
  ADMIN_NAMESPACE = 'admin_namespace',
  CREATE_SUBGROUP = 'create_subgroup',
  ADMIN_GROUP_MEMBER = 'admin_group_member',
  UPDATE_GROUP_MEMBER = 'update_group_member',
  DESTROY_GROUP_MEMBER = 'destroy_group_member',

  READ_PROJECT = 'read_project',
  READ_WIKI = 'read_wiki',
  READ_ISSUE = 'read_issue', // 可以查看 issue 的权限
  READ_LABEL = 'read_label',
  READ_MILESTONE = 'read_milestone',
  READ_PROJECT_SNIPPET = 'read_project_snippet',
  READ_PROJECT_MEMBER = 'read_project_member',
  READ_MERGE_REQUEST = 'read_merge_request',
  READ_COMPARISON = 'read_comparison',
  READ_NOTE = 'read_note',
  READ_BUILD = 'read_build',

  DOWNLOAD_CODE = 'download_code', // 该属性可以查看文件、下载单个文件，但不能下载整个项目
  DOWNLOAD_PROJECT = 'download_project', // 该属性可以查看文件、下载单个文件、下载整个项目
  FORK_PROJECT = 'fork_project',
  CREATE_PROJECT = 'create_project',
  CREATE_ISSUE = 'create_issue',
  CREATE_NOTE = 'create_note',
  CREATE_COMMIT_STATUS = 'create_commit_status',
  READ_COMMIT_STATUSES = 'read_commit_statuses',
  CREATE_PROJECT_SNIPPET = 'create_project_snippet',
  UPDATE_ISSUE = 'update_issue', // 编辑、更新 issue
  ADMIN_ISSUE = 'admin_issue',
  ADMIN_LABEL = 'admin_label',
  ADMIN_MERGE_REQUEST = 'admin_merge_request',
  ADMIN_FILE_LOCKS = 'admin_file_locks',
  CREATE_MERGE_REQUEST = 'create_merge_request',
  CREATE_COMPARISON = 'create_comparison',
  CREATE_WIKI = 'create_wiki',
  MANAGE_BUILDS = 'manage_builds',
  PUSH_CODE = 'push_code',
  PUSH_CODE_TO_PROTECTED_BRANCHES = 'push_code_to_protected_branches',
  UPDATE_MERGE_REQUEST = 'update_merge_request',
  UPDATE_COMPARISON = 'update_comparison',
  UPDATE_PROJECT_SNIPPET = 'update_project_snippet',
  ADMIN_MILESTONE = 'admin_milestone', // 项目里程碑相关操作-是否可以更新 milestone
  ADMIN_PROJECT_SNIPPET = 'admin_project_snippet',
  ADMIN_PROJECT_MEMBER = 'admin_project_member',
  ADMIN_NOTE = 'admin_note',
  ADMIN_WIKI = 'admin_wiki',
  ADMIN_PROJECT = 'admin_project',
  CHANGE_NAMESPACE = 'change_namespace',
  CHANGE_VISIBILITY_LEVEL = 'change_visibility_level',
  RENAME_PROJECT = 'rename_project',
  REMOVE_PROJECT = 'remove_project',
  ARCHIVE_PROJECT = 'archive_project',
  REMOVE_FORK_PROJECT = 'remove_fork_project',
  ADMIN_PROJECT_WATCHER = 'admin_project_watcher',

  /* code review */
  UPDATE_REVIEW = 'update_review',

  /* commit checker */
  CREATE_COMMIT_CHECKER = 'create_commit_checker',
  READ_COMMIT_CHECKER = 'read_commit_checker',

  /* 保护分支 */
  ADMIN_PROTECTED_BRANCHES_MEMBERS = 'admin_protected_branches_members',
  ADMIN_PROTECTED_BRANCH_RULES = 'admin_protected_branch_rules',
  READ_PROTECTED_BRANCHES = 'read_protected_branches',
  UPDATE_PROTECTED_BRANCHES = 'update_protected_branches',

  /* Label 权限管理 */
  LABEL_PERMISSION_MANAGEMENT = 'label_permission_management',
}

/**
 * 项目
 */
export interface Project {
  id: number;
  name: string;
  path: string;
  fullName: string;
  groupFullPath: string;
  fullPath: string;
  simplePath: string;
  groupFullName: string;
  visibilityLevel: number;
}

/**
 * 项目组
 */
export interface Group {
  id: number;
  name: string;
  path: string;
  type: string;
}

/**
 * 认证语言
 */
export interface CertifiedLanguageRuleDetail {
  languageId: number;
  language: string;
  defaultSuffix: string[];
  extendedSuffix: string[];
  enable: boolean;
}

export interface CertifiedLanguageRule {
  details: CertifiedLanguageRuleDetail[];
}

/**
 * 项目详情
 */
export interface Project4Detail extends Project {
  pushResetEnabled: boolean;
  suggestionReviewer: string;
  necessaryReviewer: string;
  approverRule: number;
  necessaryApproverRule: number;
  canApproveByCreator: boolean;
  autoCreateReviewAfterPush: boolean;
  autoCreateReviewPrePush: boolean;
  forbiddenModifyRule: boolean;
  mergeRequestTemplate: string;
  pathReviewerRules: string;
  fileOwnerPathRules: string;
  defaultBranch: string;
  allowMergeCommits: boolean;
  allowSquashMerging: boolean;
  allowRebaseMerging: boolean;
  forceAddLabelsInNote: boolean;
  mergeManager: string;
  mergeRequestMustLinkTapdTickets: boolean;
  allowCertifiedApproverEnabled: boolean;
  certifiedApproverRule: number;
  certificateLevel: number;
  certifiedLanguageRule: CertifiedLanguageRule;
  ownersReviewEnabled: boolean;
  initialOwnersMinCount: number;
  repositorySize: number;
  permissions: string[];
  group: Group;
}

/**
 * 用户
 */
export interface User {
  id: number;
  name: string;
  username: string;
  state?: UserState;
  blocked: boolean;
}

/**
 * 用户状态
 */
export enum UserState {
  ACTIVE = 'active',
  BLOCKED = 'blocked',
  // 评审单评审人区域的用户状态展示，除了 blocked 还有一个 invalid
  INVALID = 'invalid',
}

/**
 * 提交
 */
export interface Commit {
  author: string;
  email: string;
  when: number;
  commiter: string;
  commitWhen: number;
  objectId: string;
  parents: Commit[];
  shortMessageRaw: string;
}

/**
 * 保护分支配置
 */
export interface ProtectedBranch {
  name: string;
  pushResetEnabled: boolean;
  approverRule: number;
  necessaryApproverRule: number;
  canApproveByCreator: boolean;
  autoCreateReviewAfterPush: boolean;
  autoCreateReviewPrePush: boolean;
  forbiddenModifyRule: boolean;
  suggestionReviewer: string;
  necessaryReviewer: string;
  pathReviewerRules: string;
  fileOwnerPathRules: string;
  commitMrCheck: boolean;
  forceAddLabelsInNote: boolean;
  reviewCheck: boolean;
  resolvedCheck: boolean;
  mergeManager: string;
  mergeRequestMustLinkTapdTickets: boolean;
  allowMergeCommits: boolean;
  allowSquashMerging: boolean;
  allowRebaseMerging: boolean;
  defaultMergeMethod: number;
  ownersReviewEnabled: boolean;
  ruleId: number;
  initialOwnersMinCount: number;
  onlyMergeManagerMerge: boolean;
  mergeRequestTemplate: string;
}

/**
 * 里程碑
 */
export interface Milestone {
  title: string;
  state: string;
  iid: number;
  dueDate: number;
  createdAt: number;
  description: string;
}

/**
 * 标签
 */
export interface Label {
  id: number;
  title: string;
  color: string;
  sourceType: LabelType;
  sourceId: number;
  template: boolean;
  createdAt: number;
  updatedAt: number;
}

export enum LabelType {
  PROJECT = 'Project',
  NAMESPACE = 'Namespace',
}

export type ApiUserMixin = Pick<User, 'username' | 'id' | 'name' | 'state'>;

export enum AutocompleteUserScope {
  GLOBAL = 'Global',
  GROUP = 'Group',
  PROJECT = 'Project',
  BRANCH = 'Branch',
  ISSUE = 'Issue',
  PUSH = 'Push',
}

export enum ApiUserStateScope {
  ACTIVE = 'Active',
  BLOCKED = 'Blocked',
  ALL = 'All',
}

export interface AutocompleteUserOptions {
  scope?: AutocompleteUserScope;
  scopeId?: number;
  search?: string;
  fullMatch?: boolean; // 是否全匹配
  includeCurrentUser?: boolean;
  perPage?: number;
  projectPriority?: boolean; // 是否优先展示有项目权限的成员
  // 以下是兼容老接口 @see src/main/java/com/tencent/tgit/web/api/model/form/common/AutoCompleteForm.java
  global?: boolean; // 建议优先使用 scope = 'global' 代替
  projectId?: number;
  groupId?: number;
  branch?: boolean;
  full?: boolean;
  userState?: ApiUserStateScope;
}

export interface AutocompleteUser extends ApiUserMixin {
  order: number;
}

export interface UserSelectChoice {
  name: string;
  value: string;
  description?: string;
  disabled?: boolean;
}

export function hasPermission(permissions: string[], rule: Rules) {
  return permissions?.includes(rule);
}

export function normalizeProjectPath(path: string) {
  return path.replace(/\//g, '%2F');
}

export interface BackEndError {
  error: number | string;
  code: string;
  message: string;
  path: string;
  type?: string;
  trace?: string;
  status: number;
  timestamp: Date;
}

export function getBackEndError(error: any): BackEndError | undefined {
  return error.response?.data;
}

export enum CertifiedReviewerType {
  /**
   * @deprecated use `suggestion` instead
   * 历史数据以及 Open API 请求过来的数据，应注意兼容，等价于 SUGGESTION
   */
  INVITE = 'invite',
  /**
   * 普通评审人
   */
  SUGGESTION = 'suggestion',
  /**
   * 必要评审人
   */
  NECESSARY = 'necessary',
}

export enum ReviewerApproveState {
  APPROVING = 'approving',
  APPROVED = 'approved',
  DENIED = 'deny',
  CHANGE_DENIED = 'change_denied',
  CHANGE_REQUIRED = 'change_required',
}

export enum ReviewableType {
  MERGE_REQUEST = 'merge_request',
  COMPARISON = 'comparison',
}

export enum ReviewState {
  EMPTY = 'empty',
  APPROVING = 'approving',
  CHANGE_DENIED = 'change_denied',
  CHANGE_REQUIRED = 'change_required',
  APPROVED = 'approved',
  CLOSED = 'closed',
  REOPENED = 'reopened',
  CANCELED = 'canceled',
}

export enum FileReviewState {
  EMPTY = 'empty',
  APPROVING = 'approving',
  DENIED = 'denied',
  APPROVED = 'approved',
}

export enum CommitCheckState {
  SUCCESS = 'success',
  FAILURE = 'failure',
  PENDING = 'pending',
  ERROR = 'error',
}

export interface Reviewer {
  id: number;
  reviewId: number;
  userId: number;
  projectId: number;
  type: CertifiedReviewerType;
  state: ReviewerApproveState;
  user: User;
}

export interface Comparison {
  iid: number;
  targetCommit: string;
  sourceCommit: string;
  targetBranch: string;
  sourceBranch: string;
  sourceProjectId: number;
  targetProjectId: number;
  authorId: number;
  assigneeId: number;
  titleHtml: string;
  state: ReviewState;
  commitCheckState: CommitCheckState;
  descriptionRaw: string;
  updatedById: number;
  createdAt: number;
  updatedAt: number;
}

export interface Review {
  id: number;
  projectId: number;
  iid: number;
  reviewableId: number;
  reviewableType: ReviewableType;
  state: ReviewState;
  fileReviewState: FileReviewState;
  approverRule: number;
  necessaryApproverRule: number;
  pushResetEnabled: boolean;
  createdAt: number;
  noteUnresolvedTotal: number;
  allowCertifiedApproverEnabled: boolean;
  resolvedCheck: boolean;
  ownersReviewEnabled: boolean;
  initialOwnersMinCount: number;
  author: User;
  reviewCertifiedBadges: string;
  reviewers: Reviewer[];
  comparison: Comparison | null;
  svnMergeRequest: SvnMergeRequest | null;
}

export interface Reviewer {
  id: number;
  reviewId: number;
  userId: number;
  projectId: number;
  type: CertifiedReviewerType;
  state: ReviewerApproveState;
  user: User;
}

export enum CertificationLevels {
  ICODE,
  IREAD,
  ITEST,
  IWORK,
  IMASTER,
}

export enum BadgeNameEnum {
  ICODE = 'Code Explorer',
  IREAD = 'iRead',
  ITEST = 'iTest',
  IWORK = 'iWork',
  IMASTER = 'iMaster',
}

export interface BaseBadge {
  languageId: number;
  name: BadgeNameEnum;
  language: string;
  shortName: string;
  shortLanguage: string;
  icon: string;
  level: CertificationLevels;
}

export interface Badge extends BaseBadge {
  description: string;
  type: string;
  createdAt: number;
  updatedAt: number;
}

export enum SvnMergeRequestState {
  OPENED = 'opened',
  REOPENED = 'reopened',
  MERGED = 'merged',
  CLOSED = 'closed',
  COMMITTED = 'committed',
}

export interface SvnMergeRequest {
  id: number;
  authorId: number;
  title: string;
  titleGfm: string;
  targetProjectId: number;
  targetPath: string;
  sourceProjectId: number;
  sourcePath: string;
  state: SvnMergeRequestState;
  iid: number;
  description: string;
  createdAt: number;
  updatedAt: number;
}
