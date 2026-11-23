import { array } from "@ember/helper";
import PluginOutlet from "discourse/components/plugin-outlet";
import bodyClass from "discourse/helpers/body-class";
import lazyHash from "discourse/helpers/lazy-hash";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import NpnHelpForm from "../components/npn-help-form";
import NpnImageForm from "../components/npn-image-form";
import NpnIntroductionForm from "../components/npn-introduction-form";
import NpnNewMemberImageForm from "../components/npn-new-member-image-form";
import NpnPhotoForm from "../components/npn-photo-form";
import NpnProjectForm from "../components/npn-project-form";
import NpnSubmitChooser from "../components/npn-submit-chooser";

// Image for Critique and the Weekly Challenge share one form.
function isImageType(type) {
  return type === "image" || type === "weekly_challenge";
}

export default <template>
  {{! Route-scoped page class — added to <body> only while the submit route is
    rendered and removed on leave. Lets us give the page a calm, dedicated
    "submission workspace" treatment without affecting any other route. }}
  {{bodyClass "npn-submit-page"}}

  <div class="npn-submissions">
    {{#if @controller.model.canSubmit}}
      {{#if @controller.model.editError}}
        <div class="alert alert-error">
          {{@controller.model.editError}}
        </div>
      {{/if}}
      {{#if @controller.model.invalid}}
        <div class="alert alert-error">
          {{i18n "npn_submissions.errors.invalid_type"}}
        </div>
      {{/if}}

      {{#if @controller.model.resolvedType}}
        {{! Seam for sibling plugins to speak before the form — e.g. the
          critique-engagement plugin's give-and-take reminder. }}
        <PluginOutlet
          @name="npn-submit-above-form"
          @outletArgs={{lazyHash submissionType=@controller.model.resolvedType}}
        />
        {{! Keyed on the route model so moving between /submit URLs (e.g. from
          editing one post to another, or to a new submission) builds a fresh
          form instead of reusing one that is still in edit mode. }}
        {{#each (array @controller.model) key="@identity"}}
          {{#if (isImageType @controller.model.resolvedType)}}
            {{#if @controller.model.useNewForm}}
              <NpnPhotoForm
                @submissionType={{@controller.model.resolvedType}}
                @editState={{@controller.model.editState}}
                @resumeDraftId={{@controller.model.resumeDraftId}}
              />
            {{else}}
              <NpnImageForm
                @submissionType={{@controller.model.resolvedType}}
                @editState={{@controller.model.editState}}
                @resumeDraftId={{@controller.model.resumeDraftId}}
              />
            {{/if}}
          {{else if (eq @controller.model.resolvedType "project")}}
            <NpnProjectForm @editState={{@controller.model.editState}} />
          {{else if (eq @controller.model.resolvedType "introduction")}}
            <NpnIntroductionForm @editState={{@controller.model.editState}} />
          {{else if (eq @controller.model.resolvedType "new_member_image")}}
            <NpnNewMemberImageForm @editState={{@controller.model.editState}} />
          {{else if (eq @controller.model.resolvedType "help")}}
            <NpnHelpForm @editState={{@controller.model.editState}} />
          {{else}}
            <div class="alert alert-error">
              {{i18n "npn_submissions.errors.invalid_type"}}
            </div>
          {{/if}}
        {{/each}}
      {{else if @controller.model.editError}}
        {{! The error alert above says why the post can't be edited. }}
      {{else}}
        <NpnSubmitChooser />
      {{/if}}
    {{else if @controller.model.signedIn}}
      <div class="alert alert-error">
        {{i18n "npn_submissions.errors.not_allowed"}}
      </div>
    {{else}}
      <div class="alert alert-info">
        {{i18n "npn_submissions.must_sign_in"}}
      </div>
    {{/if}}
  </div>
</template>
