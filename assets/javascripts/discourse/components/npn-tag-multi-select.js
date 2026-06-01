import MultiSelectComponent from "discourse/select-kit/components/multi-select";
import { selectKitOptions } from "discourse/select-kit/components/select-kit";
import NpnTagRow from "./npn-tag-row";
import NpnTagSelectedChoice from "./npn-tag-selected-choice";

// Thin MultiSelect subclass used in tag-group-constrained mode (when
// `npn_submissions_descriptive_tag_group` is set). Wires our tag-aware row +
// selected-pill renderers and switches the header to "filter in header" mode
// so the selected chips (with icons) are visible whether the chooser is open
// or closed.
//
// Subclassing is required for two reasons:
//   1. `rowComponent` isn't exposed as a chooser option; the chooser only
//      consults `modifyComponentForRow` on the instance.
//   2. `useHeaderFilter` has to be declared at the chooser-class level via
//      `@selectKitOptions` rather than the per-instance `@options={{hash ...}}`
//      so multi-select's header template picks the chips-in-header branch.
//
// Falls back gracefully: if the Tag Icons theme component isn't installed,
// `dDiscourseTag` inside the row / pill returns plain tag HTML with no icon
// span, and the chooser keeps working exactly as it does today.
@selectKitOptions({
  selectedChoiceComponent: NpnTagSelectedChoice,
  useHeaderFilter: true,
})
export default class NpnTagMultiSelect extends MultiSelectComponent {
  modifyComponentForRow() {
    return NpnTagRow;
  }
}
