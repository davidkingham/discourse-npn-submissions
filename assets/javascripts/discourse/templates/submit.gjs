import { concat } from "@ember/helper";
import bodyClass from "discourse/helpers/body-class";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import NpnImageForm from "../components/npn-image-form";
import NpnIntroductionForm from "../components/npn-introduction-form";
import NpnProjectForm from "../components/npn-project-form";

const TYPES = ["image", "project", "weekly_challenge", "introduction"];

export default <template>
  {{! Route-scoped page class — added to <body> only while the submit route is
    rendered and removed on leave. Lets us give the page a calm, dedicated
    "submission workspace" treatment without affecting any other route. }}
  {{bodyClass "npn-submit-page"}}

  <div class="npn-submissions">
    {{#if @controller.model.canSubmit}}
      {{#if @controller.model.invalid}}
        <div class="alert alert-error">
          {{i18n "npn_submissions.errors.invalid_type"}}
        </div>
      {{/if}}

      {{#if @controller.model.resolvedType}}
        {{#if (eq @controller.model.resolvedType "image")}}
          <NpnImageForm @submissionType="image" />
        {{else if (eq @controller.model.resolvedType "weekly_challenge")}}
          <NpnImageForm @submissionType="weekly_challenge" />
        {{else if (eq @controller.model.resolvedType "project")}}
          <NpnProjectForm />
        {{else if (eq @controller.model.resolvedType "introduction")}}
          <NpnIntroductionForm />
        {{else}}
          <div class="alert alert-error">
            {{i18n "npn_submissions.errors.invalid_type"}}
          </div>
        {{/if}}
      {{else}}
        <h2>{{i18n "npn_submissions.chooser.heading"}}</h2>
        <ul class="npn-submissions__chooser">
          {{#each TYPES as |type|}}
            <li>
              <a href={{concat "/submit?type=" type}}>{{i18n
                  (concat "npn_submissions.types." type)
                }}</a>
            </li>
          {{/each}}
        </ul>
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
