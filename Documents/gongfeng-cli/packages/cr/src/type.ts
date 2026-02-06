import { User } from '@tencent/gongfeng-cli-base';
import { Label, Review, ReviewState, Badge, Reviewer } from '@tencent/gongfeng-cli-base/dist/gong-feng';

export interface TapdModel {
  id: number;
  workspaceId: number | null;
  sourceProjectId: number | null;
  sourceId: number | null;
  sourceType: number | null;
  tapdId: string;
  tapdType: string;
  name: string;
  status: string;
  statusZh: string;
  minProject: boolean;
}

export interface OwnerRuleConfig {
  count: number;
}

export interface FileOwner {
  username: string;
  approverRule: string;
  ownerRuleConfig: OwnerRuleConfig;
}

export interface FileOwnerConfigFacade {
  username: string;
  approverRule: string;
  ownerRuleConfig: OwnerRuleConfig;
  user: User;
  hasPermission: boolean;
}

export interface SvnPresetReviewFileOwner {
  filePath: string;
  authorSkipOwnersRule: boolean;
  fileOwners: FileOwnerConfigFacade[];
  rawFileOwners: FileOwner[];
}

export interface SvnPresetReviewConfigFacade {
  projectId: number;
  canApproveByCreator: boolean;
  forceAddLabelsInNote: boolean;
  resolvedCheck: boolean;
  ownersReviewEnabled: boolean;
  pushResetEnabled: boolean;
  pushResetRule: number;
  mustBindTapdInReview: boolean;
  deleted: boolean;
  fileOwners: SvnPresetReviewFileOwner[];
  reviewers: User[];
}

export interface TapdTicketForm {
  workspaceId: number | null;
  id: string;
  type: string;
}

export enum ProjectVisibilityLevel {
  Private = 0,
  Internal = 10,
  Public = 20,
}

export enum ReviewEventEnum {
  CREATE = 'create',
  COMMENT = 'comment',
  APPROVE = 'approve',
  LEAVE = 'leave',
  DENY = 'deny',
  REQUIRE_CHANGE = 'requireChange',
  REOPEN = 'reopen',
  CLOSE = 'close',
  CLOSE_BY_MERGE = 'closeByMerge',
  PUSH_ON_SOURCE_BRANCH = 'pushOnSourceBranch',
  INVITE = 'invite',
  LEAVE_ALL = 'leaveAll',
  NOTE_UNRESOLVED = 'noteUnresolved',
  NOTE_RESOLVED = 'noteResolved',
}

export interface ReviewForm {
  /** 评审人状态 */
  reviewerEvent?: ReviewEventEnum;
  /** 评审评论内容 */
  summary?: string;
  /** 是否提交全部评论草稿 */
  saveDrafts?: boolean;
  /** 严重程度 */
  risk?: number;
  /** 问题解决状态 */
  resolveState?: number;
  /** 分类标签列表 */
  labelIds?: number[];
}

export interface ReviewFacade extends Review {
  labels: Label[];
  noteCount: number;
  titleRaw: string;
  titleGfm: string;
  /** 描述markdown */
  prePushMR: boolean;
  targetBranch: string;
  sourceBranch: string;
  /** 普通评审人、必要评审人的审核结果 */
  allNormalReviewersApproved: boolean;
  /** 持证评审人的审核结果 */
  allCertifiedReviewersApproved: boolean;
  reviewableIid: number;
}

export interface ReviewWrapperDocFacadeMixIn {
  /** 作者 */
  author: User;
  /** 评审人 */
  reviewers: User[];
  /** 文件负责人 */
  owners: User[];
  /** 项目名称 */
  fullName: string;
  /** 项目路径 */
  fullPath: string;
  /** 源项目名称 */
  sourceFullName: string;
  /** 源项目路径 */
  sourceFullPath: string;
  /** 评审 id */
  id: number;
  /** 评审 iid */
  iid: number;
  /** mr id or comparison id */
  reviewableId: number;
  /** mr iid or comparison iid */
  reviewableIid: number;
  /** 作者 id */
  authorId: number;
  /** review 对象类型 merge_request/comparison */
  reviewableType: string;
  /** 状态 approving/change_denied/change_required/approved/closed */
  state: ReviewState;
  /** 评审状态 */
  reviewableState: string;
  /** 文件数 */
  fileCount: string;
  /** 评论数 */
  noteCount: string;
  /** 标题 */
  title: string;
  /** 标签 */
  labels: Label[];
  /** 目标提交点 */
  targetCommit: string;
  /** 源提交点 */
  sourceCommit: string;
  /** 是否 prePush */
  prePushMR: boolean;
  /** diff 起始 commit */
  diffStartCommitSha: string;
}

export interface ReviewSearchForm {
  /** 查询类型 */
  type?: string;
  /** 标签名 */
  labelTitle?: string;
  /** 评审状态 */
  reviewStates?: string[];
  /** 评审类型 */
  reviewableType?: string;
  /** 代码评审作者 id */
  authorId?: number;
  /** 评审人 id */
  reviewerId?: number;
  /** 分配人 id */
  assigneeId?: number;
  /** 排序字段 */
  order?: string;
  /** 排序规则 */
  sort?: string;
  /** 标签 id */
  labelIds?: number[];
  /** 当前页码  */
  page?: number;
  /** 每页数量 */
  perPage?: number;
  /** 指定路径 */
  path?: string;
  /** 最小创建时间 */
  minCreatedAt?: number;
  /** 最大创建时间 */
  maxCreateTime?: number;
}

export interface Review4DisplayItem extends Record<string, unknown> {
  iid: number;
  title: string;
  author: string;
  state: string;
}

export enum SvnReviewableType {
  COMPARISON = 'comparison',
  SVN_MERGE_REQUEST = 'svn_merge_request',
}

export interface ReviewCreatedForm {
  // 标题
  title: string;
  // 描述
  description: string;
  // 目标分支
  targetBranch?: string;
  // 源分支
  sourceBranch?: string;
  // 目标提交点
  targetCommit?: string;
  // 源提交点
  sourceCommit?: string;
  // 目标项目ID
  targetProjectId: number;
  // 源项目ID
  sourceProjectId?: number;
  // 合并负责人用户ID
  assigneeId?: number;

  /* --------------------------------关联数据-------------------------------*/
  // 关联的Label id列表
  labelIds?: number[];
  // 抄送人列表
  ccUserIds?: number[];
  // tapd关联关系
  tapdRelModels?: string;

  /* --------------------------review 关联数据----------------------------*/
  // 关联的 reviewer user id列表，以逗号分割
  reviewerIds?: string;
  // 关联的 necessary reviewer user id列表，以逗号分割
  necessaryReviewerIds?: string;
  // 评审规则
  approverRule?: number;
  // 通过评委数量
  approverRuleNumber?: number;
  // necessary评审规则
  necessaryApproverRule?: number;
  // 必须通过评委数量
  necessaryApproverRuleNumber?: number;
  // 不是需评审文件列表
  unselectedReviewFiles?: string[];
  // 是否全部反选中需评审文件，默认值false
  unselectedAllReviewFiles?: boolean;
}

export interface SvnReviewCreatedForm extends ReviewCreatedForm {
  // 目标版本号
  targetRevision: string;
  // 源版本号
  sourceRevision: string;
  // 目标目录
  targetPath: string;
  // 源目录
  sourcePath?: string;
  // tapd 关联关系
  tapdTickets?: TapdTicket[];
}

export interface TapdTicket {
  workspaceId: number;
  type: TapdType;
  id: number;
}

export enum TapdType {
  STORY = 'story',
  TASK = 'task',
  BUG = 'bug',
}

export interface ReviewConfigMixIn {
  normalReviewers: Reviewer[];
  necessaryReviewers: Reviewer[];
  certifiedReviewers: Reviewer[];
  author: User;
  invalidUsers: User[];
  validBadges: Badge[];
}
