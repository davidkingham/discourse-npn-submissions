import { i18n } from "discourse-i18n";

const NpnAdminSubmissionsTable = <template>
  {{#if @submissions.length}}
    <table class="npn-admin-submissions">
      <thead>
        <tr>
          <th>ID</th>
          <th>User</th>
          <th>Type</th>
          <th>Style</th>
          <th>Status</th>
          <th>Title</th>
          <th>Updated</th>
          <th>Topic</th>
          {{#if @showError}}<th>Error</th>{{/if}}
        </tr>
      </thead>
      <tbody>
        {{#each @submissions as |submission|}}
          <tr>
            <td>{{submission.id}}</td>
            <td>{{submission.username}}</td>
            <td>{{submission.submission_type}}</td>
            <td>{{submission.critique_style}}</td>
            <td>{{submission.status}}</td>
            <td>{{submission.title}}</td>
            <td>{{submission.updated_at}}</td>
            <td>
              {{#if submission.topic_id}}
                <a href={{submission.topic_url}}>#{{submission.topic_id}}</a>
              {{/if}}
            </td>
            {{#if @showError}}<td>{{submission.error_message}}</td>{{/if}}
          </tr>
        {{/each}}
      </tbody>
    </table>
  {{else}}
    <p>{{i18n "npn_submissions.admin.empty"}}</p>
  {{/if}}
</template>;

export default NpnAdminSubmissionsTable;
