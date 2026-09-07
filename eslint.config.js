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
    // sampleDataManager (C-10) polls SampleDataController.getStatus while a load runs;
    // setInterval/clearInterval is the standard, supported way to do that in an LWC.
    files: ['packages/core/main/default/lwc/sampleDataManager/sampleDataManager.js'],
    rules: {
      '@lwc/lwc/no-async-operation': 'off'
    }
  },
  {
    // Test-only timer helpers: a real setTimeout to flush promises, and a microtask
    // drain loop used under jest.useFakeTimers().
    files: ['packages/core/main/default/lwc/sampleDataManager/__tests__/*.js'],
    rules: {
      '@lwc/lwc/no-async-operation': 'off',
      'no-await-in-loop': 'off'
    }
  }
];
