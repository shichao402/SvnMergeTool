/**
 * 限制字符串长度为指定长度的半角字符
 * @param str 被限制的字符串
 * @param maxLength 最大长度
 */
export function truncateHalfAngleString(str: string, maxLength: number, ellipsis = '…') {
  const ellipsisLength = ellipsis.length;
  // 由于至少会有 '…' (1个半角字符), 由于 oclif 中使用的默认缩略字符为 … 因此此处沿用 …
  if (maxLength <= ellipsisLength) {
    throw new Error(`maxLength must be greater than ${ellipsisLength}`);
  }
  const exactMaxLength = maxLength - ellipsisLength;
  // 不区分半角、全角，只限制长度，
  const maxLengthStr = str.slice(0, exactMaxLength);
  // 如果小于长度的一半，则说明无论半角还是全角，都符合要求，直接返回
  if (maxLengthStr.length <= exactMaxLength / 2) {
    return maxLengthStr;
  }

  let resStr = '';
  let halfAngleLength = 0;
  let i = 0;
  // 遍历 maxLengthStr, 若字符为半角，则 halfAngleLength += 1, 若为全角则 halfAngleLength += 2
  while (halfAngleLength < exactMaxLength && i < maxLengthStr.length) {
    if (maxLengthStr[i].charCodeAt(0) < 128) {
      halfAngleLength += 1;
    } else {
      halfAngleLength += 2;
    }
    if (halfAngleLength > exactMaxLength) {
      break;
    }
    resStr += maxLengthStr[i];
    i += 1;
  }
  resStr += ellipsis;
  return resStr;
}
