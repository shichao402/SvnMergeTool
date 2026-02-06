module.exports = {
  extends: ['@tencent/tg-lint/configs/eslint'],
  env: {
    jest: true,
  },
  plugins: ['file-progress'],
  rules: {
    'file-progress/activate': 1,
  },
  parserOptions: {
    project: ['./tsconfig.json', './test/tsconfig.json'],
  },
};
