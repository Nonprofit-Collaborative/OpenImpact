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
  },
  {
    // Jest module factories run in CommonJS, so a mock factory may call require.
    files: ['packages/**/lwc/**/__tests__/**/*.js'],
    languageOptions: {
      globals: {
        require: 'readonly'
      }
    }
  }
];
