module.exports = {
  extends: ['@commitlint/config-conventional', '@tencent/tg-commitlint-conventional-scopes-lerna'],
  // @see https://github.com/conventional-changelog/commitlint/blob/master/docs/reference-rules.md
  rules: {
    'scope-empty': [2, 'never'],
    'body-leading-blank': [2, 'always'],
    'footer-leading-blank': [2, 'always'],
  },
};
