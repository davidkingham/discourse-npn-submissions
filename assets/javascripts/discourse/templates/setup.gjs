import bodyClass from "discourse/helpers/body-class";
import { i18n } from "discourse-i18n";
import NpnSetupForm from "../components/npn-setup-form";

export default <template>
  {{! Route-scoped page class, mirroring the submit page treatment. }}
  {{bodyClass "npn-submit-page npn-setup-page"}}

  <div class="npn-submissions">
    {{#if @controller.model.signedIn}}
      <NpnSetupForm @user={{@controller.model.user}} />
    {{else}}
      <div class="alert alert-info">
        {{i18n "npn_submissions.setup.must_sign_in"}}
      </div>
    {{/if}}
  </div>
</template>
