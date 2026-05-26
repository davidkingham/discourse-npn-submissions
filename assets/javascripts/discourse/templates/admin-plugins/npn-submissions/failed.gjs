
import NpnAdminSubmissionsTable from "../../../components/npn-admin-submissions-table";

export default <template>
    <div class="npn-submissions-admin__failed">
      <NpnAdminSubmissionsTable
        @submissions={{@model.submissions}}
        @showError={{true}}
      />
    </div>
  </template>;
