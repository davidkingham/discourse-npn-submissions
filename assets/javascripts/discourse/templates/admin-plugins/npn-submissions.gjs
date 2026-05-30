import DNavItem from "discourse/ui-kit/d-nav-item";
import { i18n } from "discourse-i18n";

export default <template>
  <h2>{{i18n "npn_submissions.admin.title"}}</h2>

  <ul class="nav nav-pills">
    <DNavItem
      @route="adminPlugins.npn-submissions.index"
      @label="npn_submissions.admin.tabs.dashboard"
    />
    <DNavItem
      @route="adminPlugins.npn-submissions.drafts"
      @label="npn_submissions.admin.tabs.drafts"
    />
    <DNavItem
      @route="adminPlugins.npn-submissions.failed"
      @label="npn_submissions.admin.tabs.failed"
    />
  </ul>

  <hr />

  <div id="npn-submissions-admin">
    {{outlet}}
  </div>
</template>
