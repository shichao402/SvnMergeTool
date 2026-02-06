/**
 * @see https://github.com/okonet/lint-staged
 */
module.exports = {
  '*.{js,jsx,ts,tsx}': ['yarn eslint'],
  '*.md': ['tg-lint prettier --write'],
};
