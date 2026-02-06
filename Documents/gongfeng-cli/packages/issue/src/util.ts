/**
 * 判断是否是数字字符
 * @param value
 */
export function isNumeric(value: string) {
  return /^\d+$/.test(value);
}
