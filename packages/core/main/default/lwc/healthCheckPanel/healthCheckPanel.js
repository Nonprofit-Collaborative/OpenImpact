import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

import getReport from '@salesforce/apex/HealthCheckController.getReport';
import applyRecommendedMode from '@salesforce/apex/HealthCheckController.applyRecommendedMode';
import applyJunctionMembership from '@salesforce/apex/HealthCheckController.applyJunctionMembership';

import CATEGORY_ACCESS from '@salesforce/label/c.Core_HealthCheck_CategoryAccess';
import CATEGORY_LICENSES from '@salesforce/label/c.Core_HealthCheck_CategoryLicenses';
import CATEGORY_ORG_SHAPE from '@salesforce/label/c.Core_HealthCheck_CategoryOrgShape';
import CATEGORY_SETTINGS from '@salesforce/label/c.Core_HealthCheck_CategorySettings';
import CURRENT_MODE from '@salesforce/label/c.Core_HealthCheck_CurrentModeLabel';
import INTRO from '@salesforce/label/c.Core_HealthCheck_Intro';
import LOAD_FAILED from '@salesforce/label/c.Core_HealthCheck_LoadFailed';
import LOADING from '@salesforce/label/c.Core_HealthCheck_Loading';
import NO_FINDINGS from '@salesforce/label/c.Core_HealthCheck_NoFindings';
import ORG_SHAPE_CARD from '@salesforce/label/c.Core_HealthCheck_OrgShapeCardTitle';
import READ_ONLY from '@salesforce/label/c.Core_HealthCheck_ReadOnlyNotice';
import RECOMMENDED_MODE from '@salesforce/label/c.Core_HealthCheck_RecommendedModeLabel';
import RERUN from '@salesforce/label/c.Core_HealthCheck_RerunButton';
import SEVERITY_ERROR from '@salesforce/label/c.Core_HealthCheck_SeverityError';
import SEVERITY_INFO from '@salesforce/label/c.Core_HealthCheck_SeverityInfo';
import SEVERITY_WARNING from '@salesforce/label/c.Core_HealthCheck_SeverityWarning';
import TITLE from '@salesforce/label/c.Core_HealthCheck_Title';
import USE_RECOMMENDED from '@salesforce/label/c.Core_HealthCheck_UseRecommendedButton';

const ACTION_PREFIX = 'action:';
const ACTION_RECOMMENDED_MODE = 'action:applyRecommendedMode';
const ACTION_JUNCTION_MEMBERSHIP = 'action:applyJunctionMembership';

const SEVERITY_DISPLAY = {
  Error: { icon: 'utility:error', variant: 'error', order: 0 },
  Warning: { icon: 'utility:warning', variant: 'warning', order: 1 },
  Info: { icon: 'utility:info', variant: '', order: 2 }
};

const CATEGORY_ORDER = ['OrgShape', 'Licenses', 'Access', 'Settings'];

// The Nonprofit Settings console tab, which hosts every section a fix can point at.
const SETTINGS_TAB = 'Nonprofit_Settings';

/**
 * Health Check: what Open Impact found in this org and what to do about it (feature C-11).
 *
 * The panel is readable by anyone. The Fix buttons appear only when the report says the
 * viewer holds the Manage Nonprofit Settings permission, which Apex checks again before it
 * changes anything.
 */
export default class HealthCheckPanel extends NavigationMixin(LightningElement) {
  report;
  loading = false;
  errorMessage;

  labels = {
    title: TITLE,
    intro: INTRO,
    rerun: RERUN,
    useRecommended: USE_RECOMMENDED,
    orgShapeCard: ORG_SHAPE_CARD,
    readOnly: READ_ONLY,
    loading: LOADING,
    noFindings: NO_FINDINGS,
    currentMode: CURRENT_MODE,
    recommendedMode: RECOMMENDED_MODE
  };

  connectedCallback() {
    this.load();
  }

  /** Run Health Check again. Also the Re-run button's handler. */
  @api
  async load() {
    this.loading = true;
    this.errorMessage = undefined;
    try {
      this.report = await getReport();
    } catch (error) {
      this.report = undefined;
      this.errorMessage = this.messageFrom(error);
    } finally {
      this.loading = false;
    }
  }

  get hasReport() {
    return !!this.report;
  }

  get canManageSettings() {
    return !!(this.report && this.report.canManageSettings);
  }

  get isReadOnly() {
    return this.hasReport && !this.canManageSettings;
  }

  get orgShapeSummary() {
    return this.report ? this.report.orgShapeSummary : '';
  }

  get currentModeLabel() {
    return this.report ? this.report.currentModeLabel : '';
  }

  get recommendedModeLabel() {
    return this.report ? this.report.recommendedModeLabel : '';
  }

  /** The "Use recommended mode" button only makes sense when the mode is wrong. */
  get showUseRecommended() {
    return this.canManageSettings && !!(this.report && this.report.modeNeedsAttention);
  }

  get hasFindings() {
    return !!(this.report && this.report.findings && this.report.findings.length > 0);
  }

  get showNoFindings() {
    return this.hasReport && !this.hasFindings;
  }

  /** Findings grouped by category, in reading order, with their severity display. */
  get groups() {
    if (!this.hasFindings) {
      return [];
    }

    const byCategory = new Map();
    this.report.findings.forEach((finding) => {
      const category = finding.category || 'Settings';
      if (!byCategory.has(category)) {
        byCategory.set(category, []);
      }
      byCategory.get(category).push(this.decorate(finding));
    });

    return CATEGORY_ORDER.filter((category) => byCategory.has(category)).map((category) => {
      const findings = byCategory.get(category);
      findings.sort((left, right) => left.order - right.order);
      return { key: category, label: this.categoryLabel(category), findings };
    });
  }

  decorate(finding) {
    const display = SEVERITY_DISPLAY[finding.severity] || SEVERITY_DISPLAY.Info;
    return {
      key: finding.key,
      title: finding.title,
      detail: finding.detail,
      severity: finding.severity,
      severityText: this.severityText(finding.severity),
      iconName: display.icon,
      iconVariant: display.variant,
      order: display.order,
      fixLabel: finding.fixLabel,
      fixTarget: finding.fixTarget,
      showFix: !!finding.fixTarget && !!finding.fixLabel && this.canManageSettings
    };
  }

  categoryLabel(category) {
    switch (category) {
      case 'OrgShape':
        return CATEGORY_ORG_SHAPE;
      case 'Licenses':
        return CATEGORY_LICENSES;
      case 'Access':
        return CATEGORY_ACCESS;
      default:
        return CATEGORY_SETTINGS;
    }
  }

  severityText(severity) {
    switch (severity) {
      case 'Error':
        return SEVERITY_ERROR;
      case 'Warning':
        return SEVERITY_WARNING;
      default:
        return SEVERITY_INFO;
    }
  }

  handleRerun() {
    this.load();
  }

  handleUseRecommended() {
    this.runAction(applyRecommendedMode);
  }

  /**
   * A fix is one of three things: a method on the controller, a page to navigate to, or a
   * section of the settings console for the console to open.
   */
  handleFix(event) {
    const target = event.currentTarget.dataset.target;
    if (!target) {
      return;
    }

    if (target === ACTION_RECOMMENDED_MODE) {
      this.runAction(applyRecommendedMode);
      return;
    }
    if (target === ACTION_JUNCTION_MEMBERSHIP) {
      this.runAction(applyJunctionMembership);
      return;
    }
    if (target.startsWith(ACTION_PREFIX)) {
      return;
    }
    if (target.startsWith('/')) {
      this[NavigationMixin.Navigate]({
        type: 'standard__webPage',
        attributes: { url: target }
      });
      return;
    }

    // A section fix opens the settings console at that section. The event lets a console
    // that is already hosting this panel switch section in place; the navigation is what
    // makes the button work everywhere else, including the Hub home page.
    this.dispatchEvent(
      new CustomEvent('navigatetosection', {
        detail: { section: target },
        bubbles: true,
        composed: true
      })
    );

    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: SETTINGS_TAB },
      state: { c__section: target }
    });
  }

  async runAction(action) {
    this.loading = true;
    this.errorMessage = undefined;
    try {
      this.report = await action();
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    } finally {
      this.loading = false;
    }
  }

  messageFrom(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    if (error && error.message) {
      return error.message;
    }
    return LOAD_FAILED;
  }
}
