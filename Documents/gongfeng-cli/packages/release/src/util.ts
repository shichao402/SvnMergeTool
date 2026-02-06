/**
 * 判断是否是字符数字
 * @param value
 */
export function isNumeric(value: string) {
  return /^\d+$/.test(value);
}
