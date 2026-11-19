import { i18n } from "discourse-i18n";

// Header for a form opened in edit-with-form mode, plus the warning shown when
// the post was changed outside the form since it was last saved from it.
const NpnEditIntro = <template>
  <h2>{{i18n "npn_submissions.form.edit.title"}}</h2>
  <p class="npn-image-form__lead">
    {{i18n "npn_submissions.form.edit.lead"}}
  </p>
  {{#if @editedOutsideForm}}
    <div class="npn-image-form__notice" role="alert">
      {{i18n "npn_submissions.form.edit.edited_outside_form"}}
    </div>
  {{/if}}
</template>;

export default NpnEditIntro;
