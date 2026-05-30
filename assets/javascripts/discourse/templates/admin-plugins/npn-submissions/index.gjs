export default <template>
  <div class="npn-submissions-admin__dashboard">
    <h3>Submissions</h3>
    <ul>
      <li>Drafts: {{@model.counts.drafts}}</li>
      <li>Submitted: {{@model.counts.submitted}}</li>
      <li>Failed: {{@model.counts.failed}}</li>
    </ul>
  </div>
</template>
