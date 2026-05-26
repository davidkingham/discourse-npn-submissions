
import NpnAdminSubmissionsTable from "../../../components/npn-admin-submissions-table";

export default <template>
    <div class="npn-submissions-admin__drafts">
      <NpnAdminSubmissionsTable @submissions={{@model.submissions}} />
    </div>
  </template>;
