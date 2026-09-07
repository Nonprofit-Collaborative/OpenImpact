const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
  ...jestConfig,
  roots: ['<rootDir>/packages'],
  moduleNameMapper: {},
  // No LWC components exist yet in any package; allow jest to pass cleanly until they do.
  passWithNoTests: true
};
