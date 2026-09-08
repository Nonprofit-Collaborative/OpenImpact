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
    // importWizard (C-14) polls ImportController.getBatch while a dry run or a commit runs,
    // for the same reason and by the same supported mechanism as sampleDataManager.
    files: ['packages/core/main/default/lwc/importWizard/importWizard.js'],
    rules: {
      '@lwc/lwc/no-async-operation': 'off'
    }
  },
  {
    // Test-only timer helpers: a real setTimeout to flush promises, and a microtask
    // drain loop used under jest.useFakeTimers().
    files: [
      'packages/core/main/default/lwc/sampleDataManager/__tests__/*.js',
      'packages/core/main/default/lwc/importWizard/__tests__/*.js'
    ],
    rules: {
      '@lwc/lwc/no-async-operation': 'off',
      'no-await-in-loop': 'off'
    }
  }
];
