const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
  ...jestConfig,
  roots: ['<rootDir>/packages'],
  moduleNameMapper: {
    // sfdx-lwc-jest ships no stub for lightning/actions, which a quick action screen uses to
    // close itself.
    '^lightning/actions$': '<rootDir>/packages/giving/test/jest-mocks/lightning/actions.js'
  },
  // No LWC components exist yet in any package; allow jest to pass cleanly until they do.
  passWithNoTests: true
};
