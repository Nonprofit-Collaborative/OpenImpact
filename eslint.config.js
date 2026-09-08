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
    // Jest test files load the wire adapter factories with require() inside jest.mock, which is
    // hoisted above the imports, so require is available to them and to nothing else.
    files: ['packages/**/lwc/**/__tests__/**/*.js'],
    languageOptions: {
      globals: {
        require: 'readonly'
      }
    }
  }
];
