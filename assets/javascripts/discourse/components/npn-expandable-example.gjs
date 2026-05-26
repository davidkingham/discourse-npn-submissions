// Mobile- and accessibility-friendly expandable help, using native <details>
// rather than hover-only tooltips.
const NpnExpandableExample = <template>
  <details class="npn-expandable">
    <summary>{{@summary}}</summary>
    <div class="npn-expandable__content">
      {{yield}}
    </div>
  </details>
</template>;

export default NpnExpandableExample;
