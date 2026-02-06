import { Project4Detail, User, Commit, ProtectedBranch, Role, Milestone, Label } from '@tencent/gongfeng-cli-base';
import {
  ApiUserMixin,
  Badge,
  CertifiedReviewerType,
  CommitCheckState,
  Review,
  ReviewState,
  ReviewerApproveState,
} from '@tencent/gongfeng-cli-base/dist/gong-feng';

export enum ProjectVisibilityLevel {
  Private = 0,
  Internal = 10,
  Public = 20,
}

export interface ReadyMergeRequest {
  author: User;
  commitChecks: CommitCheck[];
  diffStartCommitSha: string;
  fileCount: number;
  fullName: string;
  fullPath: string;
  id: number;
  iid: number;
  noteCount: number;
  labels: Label[];
  prePushMR: boolean;
  readyToMergeAt: number;
  sourceBranch: string;
  sourceFullName: string;
  sourceFullPath: string;
  state: ReviewState;
  targetBranch: string;
  title: string;
}

export interface MergeRequestFacade {
  mergeRequest: MergeRequest;
  mergeRequestDiff: MergeRequestDiff;
  commitChecks: CommitCheck[];
  noteCount: number;
  commentCount: number;
}

export interface MergeRequest4Detail extends MergeRequestFacade {
  targetProject: Project4Detail;
  sourceProject: Project4Detail;
  milestone: Milestone;
  labels: Label[];
  review: Review;
  commitChecks: CommitCheck[];
  patchSets: PatchSet[];
  protectedBranch: ProtectedBranch | null;
  authorProjectRole: Role;
  permissions: string[];
  workInProgress: boolean;
  sourceBranchExist: boolean;
  targetBranchExist: boolean;
  canSkipReviewer: boolean;
  allNormalReviewersApproved: boolean;
  allCertifiedReviewersApproved: boolean;
  necessaryReviewersSize: number;
  normalReviewersSize: number;
  source2TargetDistance: number;
  target2SourceDistance: number;
  sourceProjectPermissions: string[];
}

export interface PatchSet {
  projectId: number;
  pushCommitSha1: string;
  targetCommitSha1: string;
  baseCommitSha1: string;
  count: number;
  patchSetNo: number;
  mergeRequestIid: number;
  commitTime: number;
  pushCommit: Commit;
}

export enum ReviewEvent {
  COMMENT = 'comment',
  DENY = 'deny',
  APPROVE = 'approve',
  CHANGE_REQUIRE = 'require_change',
  REOPEN = 'reopen',
}

export enum FileReviewState {
  EMPTY = 'empty',
  APPROVING = 'approving',
  DENIED = 'denied',
  APPROVED = 'approved',
}

export interface MergeRequest {
  authorId: number;
  assigneeId: number;
  milestoneId: number;
  targetProjectId: number;
  targetBranch: string;
  sourceProjectId: number;
  sourceBranch: string;
  state: MergeRequestState;
  mergeStatus: MergeStatus;
  commitCheckState: string;
  commitCheckBlock: boolean;
  iid: number;
  createdAt: number;
  updatedAt: number;
  mergeType: MergeType;
  mergeCommitSha: string;
  rebaseCommitSha: string;
  prePushMR: boolean;
  assignee?: User;
  author: User;
  titleRaw: string;
  descriptionRaw: string;
}

export interface MergeRequestDiff {
  state: MergeRequestDiffState;
  realSize: number;
  commitsSize: number;
  baseCommitSha: string;
  headCommitSha: string;
  startCommitSha: string;
}

export interface CommitCheck {
  commitId: string;
  state: CommitCheckState;
  targetUrl: string;
  description: string;
  block: boolean;
  context: string;
  createdAt: number;
  updatedAt: number;
  application: CommitCheckApplication;
}

export interface CommitCheckApplication {
  name: string;
  simpleDescription: string;
  description: string;
  appIconUrl: string | null;
  createdAt: number;
  updatedAt: number;
}

export interface ApiCertifiedReviewer {
  id: number;
  reviewId: number;
  userId: number;
  projectId: number;
  type: CertifiedReviewerType;
  state?: ReviewerApproveState;
  user: ApiUserMixin;
  badges?: Badge[];
  updatedAt: number;
}

/**
 * 前端持证评审人 Model
 */
export interface CertifiedReviewer extends Partial<ApiCertifiedReviewer> {
  user: ApiUserMixin;
}

export interface TapdItem {
  id: number;
  name: string;
  sourceId: number;
  sourceProjectId: number;
  sourceType: string;
  status: string;
  statusZh: string;
  tapdId: string;
  tapdType: TapdType;
  workspaceId: number;
}

export enum TapdType {
  STORY = 'story',
  TASK = 'task',
  BUG = 'bug',
}

export enum CertificationLevels {
  ICODE,
  IREAD,
  ITEST,
  IWORK,
  IMASTER,
}

/**
 * 评审人列表分组：普通评审人 + 必要评审人
 */
export type GroupedReviewers = {
  /**
   * 普通评审人列表
   *
   * @notice
   * - 对应接口的两种类型 {@link CertifiedReviewerType.SUGGESTION} 和 {@link CertifiedReviewerType.INVITE}
   *
   * @see CertifiedReviewerType
   */
  ordinary?: CertifiedReviewer[];
  /**
   * 必要评审人列表
   *
   * @see CertifiedReviewerType
   */
  necessary?: CertifiedReviewer[];
};

export enum MergeRequestDiffState {
  EMPTY = 'empty',
  COLLECTED = 'collected',
  TIMEOUT = 'timeout',
}

export enum MergeType {
  COMMIT = 'merge',
  SQUASH = 'squash',
  REBASE = 'rebase',
}

export enum MergeRequestState {
  OPENED = 'opened',
  REOPENED = 'reopened',
  CLOSED = 'closed',
  MERGED = 'merged',
  LOCKED = 'locked',
}

export enum MergeStatus {
  UNCHECKED = 'unchecked',
  CAN_BE_MERGED = 'can_be_merged',
  CAN_NOT_BE_MERGED = 'cannot_be_merged',
  HOOK_INTERCEPT = 'hook_intercept',
  MISS_BRANCH = 'miss_branch',
}

export enum BadgeLanguage {
  'DEFAULT',
  'Cpp',
  'Go',
  'Java',
  'JSorTS',
  'OC',
  'Python',
}

export interface MergeRequestParams {
  title: string;
  description?: string;
  targetBranch: string;
  sourceBranch: string;
  targetProjectId: number;
  sourceProjectId: number;
  approverRule: number;
  approverRuleNumber: number;
  necessaryApproverRule: number;
  necessaryApproverRuleNumber: number;
  assigneeId?: number;
  labelIds?: number[];
  ccUserIds?: number[];
  tapdRelModels?: string;
  reviewerIds?: string;
  necessaryReviewerIds?: string;
  milestoneId?: number;
}

export interface MergeRequestReviewers {
  reviewers: CertifiedReviewer[];
  necessaryReviewers: CertifiedReviewer[];
  removedReviewers: CertifiedReviewer[];
}

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

export interface UserSelectChoice {
  name: string;
  value: string;
  description?: string;
  disabled?: boolean;
}
