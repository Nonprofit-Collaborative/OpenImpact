const lwcConfig = require('@salesforce/eslint-config-lwc/recommended');

module.exports = [
  {
    ignores: [
      'node_modules/**',
      '**/main/default/staticresources/**',
      '**/__tests__/**/*.snap',
      'coverage/**'
    ]
  },
  ...lwcConfig,
  {
    files: ['packages/**/lwc/**/*.js'],
    rules: {}
  }
];
