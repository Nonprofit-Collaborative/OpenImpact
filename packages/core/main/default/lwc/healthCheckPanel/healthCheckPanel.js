import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

import getReport from '@salesforce/apex/HealthCheckController.getReport';
import previewFix from '@salesforce/apex/HealthCheckController.previewFix';
import applyFix from '@salesforce/apex/HealthCheckController.applyFix';

import CANCEL_FIX from '@salesforce/label/c.Core_HealthCheckFix_CancelButton';
import CATEGORY_ACCESS from '@salesforce/label/c.Core_HealthCheck_CategoryAccess';
import CATEGORY_LICENSES from '@salesforce/label/c.Core_HealthCheck_CategoryLicenses';
import CATEGORY_ORG_SHAPE from '@salesforce/label/c.Core_HealthCheck_CategoryOrgShape';
import CATEGORY_SETTINGS from '@salesforce/label/c.Core_HealthCheck_CategorySettings';
import CONFIRM_FIX from '@salesforce/label/c.Core_HealthCheckFix_ConfirmButton';
import CURRENT_MODE from '@salesforce/label/c.Core_HealthCheck_CurrentModeLabel';
import INTRO from '@salesforce/label/c.Core_HealthCheck_Intro';
import LOAD_FAILED from '@salesforce/label/c.Core_HealthCheck_LoadFailed';
import LOADING from '@salesforce/label/c.Core_HealthCheck_Loading';
import NOTHING_TO_DO from '@salesforce/label/c.Core_HealthCheckFix_NothingToDo';
import NO_FINDINGS from '@salesforce/label/c.Core_HealthCheck_NoFindings';
import ORG_SHAPE_CARD from '@salesforce/label/c.Core_HealthCheck_OrgShapeCardTitle';
import PREVIEW_HEADING from '@salesforce/label/c.Core_HealthCheckFix_PreviewHeading';
import READ_ONLY from '@salesforce/label/c.Core_HealthCheck_ReadOnlyNotice';
import RECOMMENDED_MODE from '@salesforce/label/c.Core_HealthCheck_RecommendedModeLabel';
import RERUN from '@salesforce/label/c.Core_HealthCheck_RerunButton';
import RESULT_HEADING from '@salesforce/label/c.Core_HealthCheckFix_ResultHeading';
import SEVERITY_ERROR from '@salesforce/label/c.Core_HealthCheck_SeverityError';
import SEVERITY_INFO from '@salesforce/label/c.Core_HealthCheck_SeverityInfo';
import SEVERITY_WARNING from '@salesforce/label/c.Core_HealthCheck_SeverityWarning';
import TITLE from '@salesforce/label/c.Core_HealthCheck_Title';
import USE_RECOMMENDED from '@salesforce/label/c.Core_HealthCheck_UseRecommendedButton';
import WILL_CHANGE from '@salesforce/label/c.Core_HealthCheckFix_WillChange';

const ACTION_PREFIX = 'action:';
const ACTION_RECOMMENDED_MODE = 'applyRecommendedMode';

const SEVERITY_DISPLAY = {
  Error: { icon: 'utility:error', variant: 'error', order: 0 },
  Warning: { icon: 'utility:warning', variant: 'warning', order: 1 },
  Info: { icon: 'utility:info', variant: '', order: 2 }
};

const CATEGORY_ORDER = ['OrgShape', 'Licenses', 'Access', 'Settings'];

/**
 * Health Check: what Open Impact found in this org and what to do about it (features C-11
 * and C-21).
 *
 * The panel is readable by anyone. The Fix buttons appear only when the report says the
 * viewer holds the Manage Nonprofit Settings permission, which Apex checks again before it
 * previews or changes anything.
 *
 * A fix is never one click. Pressing a fix button asks Apex what that fix would change and
 * shows it; only the confirm button in that panel applies it. Which findings may carry a fix
 * button at all is ADR-0029, and the answer is decided in Apex, not here: this component runs
 * whatever key the finding carries.
 */
export default class HealthCheckPanel extends NavigationMixin(LightningElement) {
  report;
  loading = false;
  errorMessage;
  pendingFix;
  fixResult;

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
    recommendedMode: RECOMMENDED_MODE,
    previewHeading: PREVIEW_HEADING,
    willChange: WILL_CHANGE,
    confirmFix: CONFIRM_FIX,
    cancelFix: CANCEL_FIX,
    resultHeading: RESULT_HEADING
  };

  connectedCallback() {
    this.load();
  }

  /** Run Health Check again. Also the Re-run button's handler. */
  @api
  async load() {
    this.loading = true;
    this.errorMessage = undefined;
    this.pendingFix = undefined;
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

  /** True while a fix is waiting for the person to confirm or cancel it. */
  get hasPendingFix() {
    return !!this.pendingFix;
  }

  /** The things the pending fix says it will create or change, ready for the template. */
  get pendingFixItems() {
    const items = (this.pendingFix && this.pendingFix.items) || [];
    return items.map((label, index) => ({ key: `${index}-${label}`, label }));
  }

  get hasPendingFixItems() {
    return this.pendingFixItems.length > 0;
  }

  get pendingFixMoreLabel() {
    return this.pendingFix ? this.pendingFix.moreLabel : undefined;
  }

  get hasFixResult() {
    return !!this.fixResult;
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
    this.startFix(ACTION_RECOMMENDED_MODE);
  }

  /**
   * A fix is one of three things: a fix action, a page to navigate to, or a section of the
   * settings console for the console to open.
   */
  handleFix(event) {
    const target = event.currentTarget.dataset.target;
    if (!target) {
      return;
    }

    if (target.startsWith(ACTION_PREFIX)) {
      this.startFix(target.slice(ACTION_PREFIX.length));
      return;
    }
    if (target.startsWith('/')) {
      this[NavigationMixin.Navigate]({
        type: 'standard__webPage',
        attributes: { url: target }
      });
      return;
    }

    // A section fix opens the settings console at that section. Offer it to the host first:
    // a console already showing this panel switches section in place and calls
    // preventDefault, and the event then reports itself as handled. Only when nobody
    // handles it, which is every other placement including the Hub home page, does the
    // panel navigate to the console itself.
    const handled = !this.dispatchEvent(
      new CustomEvent('navigatetosection', {
        detail: { section: target },
        bubbles: true,
        composed: true,
        cancelable: true
      })
    );
    if (handled) {
      return;
    }

    this.navigateToSettings(target);
  }

  /**
   * Open the settings console at a section. The tab API name and the page state key both
   * carry the package namespace, so they come from Apex rather than being written here
   * (see docs/contributor-guide/environment.md, "Namespace registration").
   */
  navigateToSettings(section) {
    const apiName = this.report && this.report.settingsTabApiName;
    const stateKey = this.report && this.report.sectionStateKey;
    if (!apiName || !stateKey) {
      return;
    }

    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName },
      state: { [stateKey]: section }
    });
  }

  /** Ask Apex what this fix would change. Nothing is changed by asking. */
  async startFix(fixKey) {
    this.loading = true;
    this.errorMessage = undefined;
    this.fixResult = undefined;
    this.pendingFix = undefined;
    try {
      const preview = await previewFix({ fixKey });
      if (preview && preview.nothingToDo) {
        // The finding was already answered, by someone else or by an earlier press on a page
        // this browser tab has not refreshed. Say so, refresh, and change nothing.
        this.fixResult = { fixKey, title: preview.title, summary: NOTHING_TO_DO, changed: 0 };
        await this.load();
        return;
      }
      this.pendingFix = preview;
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    } finally {
      this.loading = false;
    }
  }

  handleCancelFix() {
    this.pendingFix = undefined;
  }

  /** The second click, and the only one that changes anything. */
  async handleConfirmFix() {
    const fixKey = this.pendingFix && this.pendingFix.fixKey;
    if (!fixKey) {
      return;
    }
    this.loading = true;
    this.errorMessage = undefined;
    try {
      const outcome = await applyFix({ fixKey });
      this.pendingFix = undefined;
      this.fixResult = outcome.result;
      this.report = outcome.report;
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
