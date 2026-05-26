import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import DButton from "discourse/ui-kit/d-button";
import DCookText from "discourse/ui-kit/d-cook-text";
import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";

// Read-only preview of the post that will be created. The Markdown comes from the
// backend (the same shared PostBuilder used at submit time), and DCookText cooks +
// decorates it with Discourse's own pipeline (short-url image resolution, spoilers,
// oneboxes) so the preview matches a real post without duplicating any formatting.
// "Submit for Critique" delegates to the form's own submit via `@model.onSubmit`;
// this modal never submits on its own.
export default class NpnPreviewModal extends Component {
  @tracked submitting = false;

  @action
  async submit() {
    this.submitting = true;
    try {
      // The form submits and, on success, transitions to the new topic. Close
      // the dialog on success; on failure leave it open so the error is visible.
      const succeeded = await this.args.model.onSubmit();
      if (succeeded) {
        this.args.closeModal();
      }
    } finally {
      this.submitting = false;
    }
  }

  <template>
    <DModal
      @title={{i18n "npn_submissions.form.preview.title"}}
      @closeModal={{@closeModal}}
      class="npn-preview-modal"
    >
      <:body>
        {{#if @model.title}}
          <h1 class="npn-preview-modal__title">{{@model.title}}</h1>
        {{/if}}

        {{#if @model.tags.length}}
          <div class="npn-preview-modal__meta">
            <span class="npn-preview-modal__meta-label">
              {{i18n "npn_submissions.form.preview.tags_label"}}
            </span>
            {{#each @model.tags as |tag|}}
              <span class="npn-preview-modal__tag">{{tag}}</span>
            {{/each}}
          </div>
        {{/if}}

        <DCookText
          @rawText={{@model.markdown}}
          class="npn-preview-modal__post cooked"
        />
      </:body>
      <:footer>
        {{#if @model.submitDisabledReason}}
          <span class="npn-preview-modal__notice">
            {{@model.submitDisabledReason}}
          </span>
        {{/if}}
        <DButton
          @label="npn_submissions.form.preview.close"
          @action={{@closeModal}}
          class="btn-default"
        />
        <DButton
          @label="npn_submissions.form.preview.submit"
          @action={{this.submit}}
          @isLoading={{this.submitting}}
          @disabled={{@model.submitDisabled}}
          class="btn-primary"
        />
      </:footer>
    </DModal>
  </template>
}
