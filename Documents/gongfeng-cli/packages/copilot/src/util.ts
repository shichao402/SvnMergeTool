export function extractCommand(content: string) {
  const reg = /(?:^|[\s\S]*?)```bash([\s\S]*?)```(?:[\s\S]*?|$)/;
  const match = content.match(reg);
  if (match) {
    return match[1].trim();
  }
  return '';
}

export const COPY = 'copy';
export const CANCEL = 'cancel';
export const EDIT = 'edit';
export const SCORE = 'score';
export const YES = 'yes';
export const NO = 'no';
