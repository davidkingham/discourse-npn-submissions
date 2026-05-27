import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";

// A small modal for inserting a Markdown link into a form textarea. The host
// component (NpnField) opens it with the textarea's current selection
// pre-filled as `defaultText`, and provides `onInsert({ text, url })` which is
// called once Insert is clicked with a non-empty URL. The actual textarea
// write is performed by the host via TextareaTextManipulation so the cursor /
// selection logic matches what the Discourse composer does for its own link
// toolbar button.
export default class NpnLinkModal extends Component {
  @tracked text = this.args.model?.defaultText ?? "";
  @tracked url = "";

  get insertDisabled() {
    return this.url.trim().length === 0;
  }

  @action
  updateText(event) {
    this.text = event.target.value;
  }

  @action
  updateUrl(event) {
    this.url = event.target.value;
  }

  @action
  submit(event) {
    event?.preventDefault();
    if (this.insertDisabled) {
      return;
    }
    this.args.model.onInsert({ text: this.text, url: this.url.trim() });
    this.args.closeModal();
  }

  <template>
    <DModal
      @title={{i18n "npn_submissions.form.toolbar.link_modal.title"}}
      @closeModal={{@closeModal}}
      class="npn-link-modal"
    >
      <:body>
        <form
          class="npn-link-modal__form"
          {{on "submit" this.submit}}
        >
          <label class="npn-link-modal__label">
            <span>{{i18n "npn_submissions.form.toolbar.link_modal.url_label"}}</span>
            <input
              class="npn-link-modal__input"
              type="url"
              autocomplete="off"
              placeholder={{i18n "npn_submissions.form.toolbar.link_modal.url_placeholder"}}
              value={{this.url}}
              {{on "input" this.updateUrl}}
              required
              autofocus
            />
          </label>
          <label class="npn-link-modal__label">
            <span>{{i18n "npn_submissions.form.toolbar.link_modal.text_label"}}</span>
            <input
              class="npn-link-modal__input"
              type="text"
              value={{this.text}}
              {{on "input" this.updateText}}
            />
          </label>
          {{! Hidden submit so pressing Enter inside either input submits the
          form (not the parent submission form). }}
          <button type="submit" class="npn-link-modal__hidden-submit" tabindex="-1" aria-hidden="true">
            {{i18n "npn_submissions.form.toolbar.link_modal.insert"}}
          </button>
        </form>
      </:body>
      <:footer>
        <DButton
          @label="npn_submissions.form.toolbar.link_modal.cancel"
          @action={{@closeModal}}
          class="btn-default"
        />
        <DButton
          @label="npn_submissions.form.toolbar.link_modal.insert"
          @action={{this.submit}}
          @disabled={{this.insertDisabled}}
          class="btn-primary"
        />
      </:footer>
    </DModal>
  </template>
}
