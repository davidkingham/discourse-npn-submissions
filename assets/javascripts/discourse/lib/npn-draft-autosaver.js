import { tracked } from "@glimmer/tracking";
import { cancel, later } from "@ember/runloop";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

const DEBOUNCE_MS = 2500;
const TICK_MS = 60000;

// Shared autosave engine for the submission forms. Debounced, quiet, and uses a
// single draft record (creating one only once there is meaningful content, then
// updating it). Manual "Save Draft" goes through the same path (saveNow) so it
// never creates a duplicate.
//
// status: "idle" | "saving" | "saved" | "failed"
export default class NpnDraftAutosaver {
  @tracked status = "idle";
  @tracked lastSavedAt = null;
  // Advances each minute so the "saved N minutes ago" label refreshes while idle.
  @tracked tick = 0;

  constructor({ buildPayload, hasContent, getDraftId, setDraftId }) {
    this._buildPayload = buildPayload;
    this._hasContent = hasContent;
    this._getDraftId = getDraftId;
    this._setDraftId = setDraftId;
    this._debounce = null;
    this._tickTimer = null;
    this._stopped = false;
    this._inFlight = false;
    // Bumped by reset() so an in-flight save started for an abandoned draft can't
    // re-attach the freshly reset form to it.
    this._generation = 0;
  }

  get isSaving() {
    return this.status === "saving";
  }

  // True when there are edits that aren't safely persisted yet: a debounced save
  // is pending or a save is in flight. Used to decide whether resetting the form
  // needs a confirmation.
  get hasPendingChanges() {
    return !!this._debounce || this._inFlight;
  }

  get minutesSinceSave() {
    // Reading `tick` (always >= 0) keeps this reactive to the minute timer.
    if (!this.lastSavedAt || this.tick < 0) {
      return 0;
    }
    return Math.floor((Date.now() - this.lastSavedAt) / 60000);
  }

  // Call on any meaningful change. Debounced; won't create an empty draft.
  schedule() {
    if (this._stopped || !this._shouldSave()) {
      return;
    }
    if (this._debounce) {
      cancel(this._debounce);
    }
    this._debounce = later(() => this.save(), DEBOUNCE_MS);
  }

  // Manual Save Draft: save immediately, surfacing errors to the user.
  async saveNow() {
    if (this._debounce) {
      cancel(this._debounce);
      this._debounce = null;
    }
    await this.save({ manual: true });
  }

  async save({ manual = false } = {}) {
    if (this._stopped || !this._shouldSave()) {
      return;
    }
    if (this._inFlight) {
      // A save is already running; reschedule so the latest edit isn't lost.
      this.schedule();
      return;
    }

    const generation = this._generation;
    this._inFlight = true;
    this.status = "saving";
    try {
      const payload = this._buildPayload();
      const draftId = this._getDraftId();
      if (draftId) {
        await ajax(`/npn-submissions/drafts/${draftId}`, {
          type: "PUT",
          contentType: "application/json",
          data: JSON.stringify(payload),
        });
      } else {
        const result = await ajax("/npn-submissions/drafts", {
          type: "POST",
          contentType: "application/json",
          data: JSON.stringify(payload),
        });
        // If the form was reset (Start New) while this save was in flight, don't
        // re-attach the now-blank form to the abandoned draft.
        if (generation === this._generation) {
          this._setDraftId(result.submission.id);
        }
      }
      if (generation === this._generation) {
        this.lastSavedAt = Date.now();
        this.status = "saved";
        this._startTicking();
      }
    } catch (e) {
      if (generation === this._generation) {
        this.status = "failed";
      }
      // Autosave failures stay quiet (inline status); manual saves surface.
      if (manual) {
        popupAjaxError(e);
      }
    } finally {
      if (generation === this._generation) {
        this._inFlight = false;
      }
    }
  }

  // Stop autosaving (e.g. after a successful submit) without tearing down so the
  // final status remains visible until the route changes.
  stop() {
    this._stopped = true;
    this._clearTimers();
  }

  teardown() {
    this._clearTimers();
  }

  // Discard any pending/in-flight save and return to the idle state, ready for a
  // brand-new submission (used by the form's "Start New" action). Does NOT stop
  // autosaving — the new submission will autosave once it has meaningful content.
  reset() {
    this._generation += 1;
    this._clearTimers();
    this._inFlight = false;
    this.status = "idle";
    this.lastSavedAt = null;
    this.tick = 0;
  }

  // Only save once there's something worth saving, unless a draft already exists
  // (then keep it current).
  _shouldSave() {
    return !!this._getDraftId() || this._hasContent();
  }

  _startTicking() {
    if (this._tickTimer || this._stopped) {
      return;
    }
    const loop = () => {
      this.tick++;
      this._tickTimer = later(loop, TICK_MS);
    };
    this._tickTimer = later(loop, TICK_MS);
  }

  _clearTimers() {
    if (this._debounce) {
      cancel(this._debounce);
      this._debounce = null;
    }
    if (this._tickTimer) {
      cancel(this._tickTimer);
      this._tickTimer = null;
    }
  }
}
