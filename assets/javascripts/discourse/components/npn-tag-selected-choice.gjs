import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import dDiscourseTag from "discourse/ui-kit/helpers/d-discourse-tag";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

// Selected-pill renderer (the X-button chip shown in the chooser body for
// each already-selected tag). Replaces the generic `<span
// class="d-button-label">{{itemName}}</span>` text rendering of core's
// `selected-choice.gjs` with `dDiscourseTag`, so the pill goes through
// `renderTag` — and therefore picks up whatever the Tag Icons theme
// component (or any future global tag renderer) injects.
//
// Contract matches core's SelectedChoice: receives `@item` (`{id, name}`) and
// `@selectKit` (used for the `deselect` action). We deliberately skip the
// `mandatoryValues` / readOnly path — the submission tag choosers never set
// it, so the branch would be unreachable.
const NpnTagSelectedChoice = <template>
  <button
    {{on "click" (fn @selectKit.deselect @item)}}
    aria-label={{i18n "select_kit.delete_item" name=@item.name}}
    data-value={{@item.id}}
    data-name={{@item.name}}
    type="button"
    class="btn btn-default selected-choice npn-tag-selected-choice"
  >
    {{dIcon "xmark"}}
    {{dDiscourseTag @item.name noHref=true}}
  </button>
</template>;

export default NpnTagSelectedChoice;
